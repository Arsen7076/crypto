// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

interface IUSDT {
    function transferFrom(address _from, address _to, uint _value) external;
    function allowance(address _owner, address _spender) external returns (uint remaining);
    function balanceOf(address _owner) external view returns (uint256);
}

interface ITicketNFT {
    function safeMint(address _user) external;
    function balanceOf(address _owner) external view returns (uint256);
    function ownerOf(uint256 tokenId) external returns (address);
}

contract MlmLottery is OwnableUpgradeable {


    bool enable;
    /**
    * @notice Struct - UserInfo
    * @param numberOfWonCyclesInRow Count of won cycles in a row.
    * @param lastWonCycle Number of last won cycle.
    * @param soldTicketsCount Count of bought tickets by his referrals.
    * @param ticketsArr Array of user's bought tickets.
    * @param referralsCount Count of invited users aka Referrals.
    * @param addressId ID of the user.
    */
    struct UserInfo{
        uint256 numberOfWonCyclesInRow;
        uint256 lastWonCycle;
        uint256 soldTicketsCount; 
        uint256[] ticketsArr; 
        uint256 referralsCount; 
        uint256 addressId;
        uint256 totalRewards;
        uint256 referrerId; 
    }

    uint256 public numberOfTickets;
    uint256 public numberOfSoldTickets;
    uint256 public ticketPrice; // set in wei
    uint256 public usersCount;
    uint256 public winningTicketsCount;
    uint256 public cycleCount;
    uint256 public monthlyJackpotStartTimestamp;
    uint256 public amountFromCycleToMonthlyJackpot; // set in wei
    address public tetherAddress;
    address public bankAddress;
    address public monthlyJackpotAddress;
    address public ticketNFTAddress;
    address public lastMonthlyJackpotWinner;
    // All winning amounts are in USDT
    uint256 public monthlyJackpotWinningAmount; // set in wei
    // 0 index is jackpotWinningAmount, 1 - top16Winners, 2 - top62Winners, 3 - top125Winners;
    uint256[4] public winningAmounts; // set in wei
    // Bonus functionality variables
    // 0 index is bonusForReferrals, 1 - bonusForSoldTickets, 2 - bonusForWinningInRow, 3 - bonusForBoughtTickets
    // 4 - refferalsCountForBonus, 5 - soldTicketsCountForBonus, 6 - winningInRowCountForBonus, 7 - boughtTicketCountForBonus;
    uint256[8] public bonusParameters; 
    // 0 index is the percentage of 1st parent, 1 - 2rd parent, 2 - 3rd parent 
    uint256[3] public parentsPercentages;
    // 0 index is jackpot winners count, 1 - second reward winners Count, 2 - third reward winners Count, 3 - fourth reward winners Count;
    uint256[4] public winningTicketsCountByLevels;
    // boolean for checking new cycle activness
    bool public isCycleActive;

    mapping(uint256 => address) public ticketNumberToAddress;
    mapping(address => address) public addressToHisReferrer; // Referrer is higher in the tree
    mapping(uint256 => address) public idToHisAddress; // ID is for referral system, user can invite other users by his id
    mapping(uint256 => bool) ticketUniqueness;
    mapping(address => UserInfo) userInfo;
    mapping(address => bool) public isAdmin;
    uint256[] public winningTickets;

    //events
    event TicketBought(address indexed buyer, uint256 indexed count, uint256 indexed timestamp, uint256 userBalance);
    event ReferralsCountBonus(address indexed user, uint256 indexed bonusAmount, uint256 indexed timestamp, uint256 userBalance);
    event BoughtTicketsCountBonus(address indexed user, uint256 indexed bonusAmount, uint256 indexed timestamp, uint256 userBalance);
    event SoldTicketsCountBonus(address indexed user, uint256 indexed bonusAmount, uint256 indexed timestamp, uint256 userBalance);
    event WiningInRowBonus(address indexed user, uint256 indexed bonusAmount, uint256 indexed timestamp, uint256 userBalance);
    event TicketNumberSet(uint256 indexed ticketNumber, uint256 indexed timestamp);
    event TicketPriceSet(uint256 indexed ticketPrice, uint256 indexed timestamp);
    event BankAddressSet(address indexed bank, uint256 indexed timestamp);
    event MonthlyJackpotAddressSet(address indexed monthlyJackpot, uint256 indexed timestamp);
    event TicketNFTAddressSet(address indexed NFTAddress, uint256 indexed timestamp);
    event StableCoinAddressSet(address indexed NFTAddress, uint256 indexed timestamp);
    event NewCycleStarted(address indexed caller, uint256 cycleCount, uint256 indexed timestamp);
    event WinnersRewarded(address indexed caller, uint256 indexed timestamp);
    event MonthlyJackpotExecuted(address indexed winner, uint256 indexed newJackpotStartingTime);

    receive() external payable {}

    fallback() external payable {}

    /**
    * @notice Modifier - activeCycle
    * @dev Ensures that the current lottery cycle is active before allowing function execution.
    * @dev Apply this modifier to functions in the MlmLottery contract that require an active cycle.
    */
    modifier activeCycle(){
        require(isCycleActive, "MlmLottery:: Currently you can not buy new tickets");
        _;
    }

    modifier activeContract(){
        require(enable, "MlmLottery:: contract is not active");
        _;
    }

    modifier OnlyAdmin(){
        require(isAdmin[msg.sender], "MlmLottery:: This function can be called only by admins");
        _;
    }
    
    function initialize() external initializer {
        // __Ownable_init();
        idToHisAddress[0] = owner();
        usersCount = 1;
        monthlyJackpotStartTimestamp = block.timestamp;
    }

    function addUserToMlm(address _user, uint256 _referrerId) external OnlyAdmin activeContract{
        require(!(addressToHisReferrer[_user] != address(0) && idToHisAddress[_referrerId] != addressToHisReferrer[_user]),"MlmLottery:: your referrer is already set and it is another user"); //checking refid
        require(_referrerId < usersCount, "MlmLottery:: Please provide right ID!");

        userInfo[_user].referrerId = _referrerId;
        userInfo[_user].addressId = usersCount;
        idToHisAddress[usersCount] = _user;
        ++usersCount;
        address referrer = idToHisAddress[_referrerId];
        addressToHisReferrer[_user] = referrer;
        ++userInfo[referrer].referralsCount;
        if(addressToHisReferrer[_user] != owner())
            referralCountBonus(referrer);
    }

    /**
    * @notice Allows users to purchase a specified number of tickets for the ongoing lottery cycle.
    * @dev Requires an active lottery cycle as enforced by the activeCycle modifier.
    * @param _countOfTickets The number of tickets to be purchased by the user.
    * @dev Call this function to buy tickets during an active lottery cycle.
    */
 function buyTickets(uint256 _countOfTickets) external activeCycle activeContract {
    require(_countOfTickets > 0, "MlmLottery:: Count of tickets can not be 0");
    require(IUSDT(tetherAddress).allowance(msg.sender, address(this)) >= ticketPrice * _countOfTickets, "MlmLottery:: User has not given enough allowance");
    require((numberOfSoldTickets + _countOfTickets) <= numberOfTickets * cycleCount, "MlmLottery:: tickets count + sold tickets count must be smaller than number of available tickets");
    require(addressToHisReferrer[msg.sender] != address(0), "MlmLottery:: Please sign up to buy Tickets!");

    uint256 totalAmount = ticketPrice * _countOfTickets;
    IUSDT(tetherAddress).transferFrom(msg.sender, bankAddress, totalAmount);

    uint256 boughtTicketsCountBefore = userInfo[msg.sender].ticketsArr.length;
    for (uint256 i = 1; i <= _countOfTickets; ++i) {
        ++numberOfSoldTickets;
        userInfo[msg.sender].ticketsArr.push(numberOfSoldTickets);
        ITicketNFT(ticketNFTAddress).safeMint(msg.sender);
        ticketNumberToAddress[numberOfSoldTickets] = msg.sender;
    }

    boughtTicketsCountBonus(msg.sender, boughtTicketsCountBefore);
    if (addressToHisReferrer[msg.sender] != owner())
        soldTicketsCountBonus(addressToHisReferrer[msg.sender], userInfo[addressToHisReferrer[msg.sender]].soldTicketsCount);

    if (numberOfSoldTickets % numberOfTickets == 0) {
        isCycleActive = false;
        monthlyJackpotWinningAmount += amountFromCycleToMonthlyJackpot;
        IUSDT(tetherAddress).transferFrom(bankAddress, monthlyJackpotAddress, amountFromCycleToMonthlyJackpot);

        // **Automatically distribute rewards when all tickets are sold**
        _rewardWinners();

        // **Automatically run Mega Jackpot if 30 days have passed**
        if (block.timestamp >= monthlyJackpotStartTimestamp + 30 days) {
            _monthlyJackpotExecuting();
        }
    }

    emit TicketBought(msg.sender, _countOfTickets, block.timestamp, IUSDT(tetherAddress).balanceOf(msg.sender));
}

    /**
    * @notice Function - setTicketsNumber
    * @dev Sets the number of tickets for the lottery cycle.
    * @param _numberOfTickets The new number of tickets to be set.
    * @dev Only the contract owner can execute this function.
    */
    function setTicketsNumber(uint256 _numberOfTickets) external onlyOwner{
        numberOfTickets = _numberOfTickets;
        emit TicketNumberSet(_numberOfTickets, block.timestamp);
    }

    /**
    * @notice Function - setTicketPrice
    * @dev Sets the price of the ticket for the lottery cycle.
    * @param _ticketPrice The new price of tickets to be set.
    * @dev Only the contract owner can execute this function.
    */
    function setTicketPrice(uint256 _ticketPrice) external onlyOwner{
        ticketPrice = _ticketPrice;
        emit TicketPriceSet(_ticketPrice, block.timestamp);
    }

    /**
    * @notice Function - setBankAddress
    * @dev Sets the address of the Bank.
    * @param _bank The new address of the Bank.
    * @dev Only the contract owner can execute this function.
    */
    function setBankAddress(address _bank) external onlyOwner{
        bankAddress = _bank;
        emit BankAddressSet(_bank, block.timestamp);
    }

    /**
    * @notice Function - setMonthlyJackpotAddress
    * @dev Sets the address of the Jackpot.
    * @param _jackpot The new address of the Bank.
    * @dev Only the contract owner can execute this function.
    */
    function setMonthlyJackpotAddress(address _jackpot) external onlyOwner{
        monthlyJackpotAddress = _jackpot;
        emit MonthlyJackpotAddressSet(_jackpot, block.timestamp);
    }

    /**
    * @notice Function - setTicketNFTAddress
    * @dev Sets the address of the NFT contract.
    * @param _ticketAddress The new address of the NFT tickets.
    * @dev Only the contract owner can execute this function.
    */
    function setTicketNFTAddress(address _ticketAddress) external onlyOwner{
        ticketNFTAddress = _ticketAddress;
        emit TicketNFTAddressSet(_ticketAddress, block.timestamp);
    }

    /**
    * @notice Function - setStableCoinAddress
    * @dev Sets the address of the Stable coin.
    * @param _tokenAddress The new address of the Stable coin.
    * @dev Only the contract owner can execute this function.
    */
    function setStableCoinAddress(address _tokenAddress) external onlyOwner{
        tetherAddress = _tokenAddress;
        emit StableCoinAddressSet(_tokenAddress, block.timestamp);
    }

    /**
    * @notice Function - setWinningAmounts
    * @dev Sets the winning amount in WEI for each type.
    * @param _amounts The new winning amounts.
    * @dev Only the contract owner can execute this function.
    */
    function setWinningAmounts(uint256[4] memory _amounts) external onlyOwner{
        winningAmounts = _amounts;
    }

    /**
    * @notice Function - setAmountFromCycleToMonthlyJackpot
    * @dev Sets the new amount to be executed after finishing cycle to the jackpot address (WEI).
    * @param _amount The new executing amount for cycle.
    * @dev Only the contract owner can execute this function.
    */
    function setAmountFromCycleToMonthlyJackpot(uint256 _amount) external onlyOwner{
        amountFromCycleToMonthlyJackpot = _amount;
    }

    /**
    * @notice Function - setParentsRewardPercentages
    * @dev Sets the Referrer(Parent) reward percentages for each parent type.
    * @param _percentages The new reward percentages.
    * @dev Only the contract owner can execute this function.
    */
    function setParentsRewardPercentages(uint256[3] memory _percentages) external onlyOwner{
        parentsPercentages = _percentages;
    }

    /**
    * @notice Function - setWinningTicketsCountByLevels
    * @dev Sets the new counts of winning tickets for different levels.
    * @param _winningTicketsCounts The new Winning tickets counts.
    * @dev Only the contract owner can execute this function.
    */
    function setWinningTicketsCountByLevels(uint256[4] memory _winningTicketsCounts) external onlyOwner{
        winningTicketsCountByLevels = _winningTicketsCounts;
        winningTicketsCount = 0;
        for(uint8 i; i < 4; ++i){
            winningTicketsCount += _winningTicketsCounts[i];
        }
    }

    /**
    * @notice Function - setAdminStatus
    * @dev Sets Admin status.
    * @param _admin Address of Admin.
    * @param _status Boolean variable for enabling or disabling Admin.
    * @dev Only the contract owner can execute this function.
    */
    function setAdminStatus(address _admin, bool _status) external onlyOwner{
        isAdmin[_admin] = _status;
    }

    /**
    * @notice Function - setBonusVaraiablesValues
    * @dev Sets the bonus rewards in wei and, conditional counts to get bonuses.
    * @param _bonusParametres The new bonus system parametres.
    * @dev Only the contract owner can execute this function.
    */
    function setBonusVaraiablesValues(uint256[8] memory _bonusParametres) external onlyOwner{
        bonusParameters = _bonusParametres;
    }
    
    /**
    * @notice Function - monthlyJackpotExecuting
    * @dev Executes the monthly Jackot.
    * @dev Only the contract owner can execute this function.
    */
    function monthlyJackpotExecuting() external onlyOwner activeContract{
        _monthlyJackpotExecuting();
    }

    function _monthlyJackpotExecuting()private {
        require(monthlyJackpotStartTimestamp + 30 days <= block.timestamp ,"MlmLottery:: You can call monthlyJackpotExecuting function once in a month!");
        monthlyJackpotStartTimestamp = block.timestamp;
        address winner = getRandomAddressForMonthlyJackpot();
        lastMonthlyJackpotWinner = winner;
        IUSDT(tetherAddress).transferFrom(monthlyJackpotAddress, winner, monthlyJackpotWinningAmount);
        userInfo[winner].totalRewards += monthlyJackpotWinningAmount;
        monthlyJackpotWinningAmount = 0;
        emit MonthlyJackpotExecuted(winner, monthlyJackpotStartTimestamp);
    }
    /**
    * @notice Function - startNewCycle
    * @dev Starts new cycle, after deleting old winning tickets and incrementing cycle count.
    * @dev Only the contract owner can execute this function.
    */
function startNewCycle() external onlyOwner activeContract { 
    require(winningTickets.length > 0 || cycleCount == 0, "MlmLottery:: Can not start new cycle!");
    
    // Reset winning tickets and ticket uniqueness mapping
    for (uint i = 0; i < winningTickets.length; i++) {
        ticketUniqueness[winningTickets[i]] = false;
    }
    delete winningTickets;
    
    isCycleActive = true;
    ++cycleCount;
    
    emit NewCycleStarted(msg.sender, cycleCount, block.timestamp);
}

    /**
    * @notice Function - referralCountBonus
    * @dev Checks conditions to send bonus for invited refferals.
    * @param _bonusWinner The Address of expected bonus winner.
    */
    function referralCountBonus(address _bonusWinner) private {
        if(userInfo[_bonusWinner].referralsCount % bonusParameters[4] == 0){
            IUSDT(tetherAddress).transferFrom(bankAddress, _bonusWinner, bonusParameters[0]);
            userInfo[_bonusWinner].totalRewards += bonusParameters[4];
            emit ReferralsCountBonus(_bonusWinner, bonusParameters[0], block.timestamp, IUSDT(tetherAddress).balanceOf(msg.sender));
        }
    }

    /**
    * @notice Function - soldTicketsCountBonus
    * @dev Checks conditions to send bonus for sold tickets.
    * @param _bonusWinner The Address of expected bonus winner.
    */
    function soldTicketsCountBonus(address _bonusWinner, uint256 _soldTicketsCountBefore) private {
        uint256 diff = userInfo[_bonusWinner].soldTicketsCount / bonusParameters[5] - _soldTicketsCountBefore / bonusParameters[5];
        if(diff > 0){
            IUSDT(tetherAddress).transferFrom(bankAddress, _bonusWinner, diff * bonusParameters[1]);
            userInfo[_bonusWinner].totalRewards += (diff * bonusParameters[1]);
            emit SoldTicketsCountBonus(_bonusWinner, diff * bonusParameters[1], block.timestamp, IUSDT(tetherAddress).balanceOf(msg.sender));
        }
    }

    /**
    * @notice Function - boughtTicketsCountBonus
    * @dev Checks conditions to send bonus for bought tickets.
    * @param _bonusWinner The Address of expected bonus winner.
    */
    function boughtTicketsCountBonus(address _bonusWinner, uint256 _boughtTicketsCountBefore) private {
        uint256 diff = userInfo[_bonusWinner].ticketsArr.length / bonusParameters[7] - _boughtTicketsCountBefore / bonusParameters[7];
        if(diff > 0){
            IUSDT(tetherAddress).transferFrom(bankAddress, _bonusWinner, diff * bonusParameters[3]);
            userInfo[_bonusWinner].totalRewards += (diff * bonusParameters[3]);
            emit BoughtTicketsCountBonus(_bonusWinner, diff * bonusParameters[3], block.timestamp, IUSDT(tetherAddress).balanceOf(msg.sender));
        }
    }

    /**
    * @notice Function - winningInRowBonus
    * @dev Checks conditions to send bonus for winning in a Row.
    * @param _bonusWinner The Address of expected bonus winner.
    */
    function winningInRowBonus(address _bonusWinner) private {
        if(userInfo[_bonusWinner].numberOfWonCyclesInRow == bonusParameters[6]){
            IUSDT(tetherAddress).transferFrom(bankAddress, _bonusWinner, bonusParameters[2]);
            userInfo[_bonusWinner].totalRewards += bonusParameters[2];
            emit WiningInRowBonus(_bonusWinner, bonusParameters[2], block.timestamp, IUSDT(tetherAddress).balanceOf(msg.sender));
        }
    }

    /**
    * @notice Function - rewardWinners
    * @dev After selling all tickets owner calls this function to distribute rewards.
    * @dev Only the contract owner can execute this function.
    */
    function rewardWinners() external onlyOwner activeContract{
        _rewardWinners();
    }

    function _rewardWinners()private {
        require(isCycleActive == false, "MlmLottery:: You can call rewardWinners function only after quiting cycle");
        require(numberOfSoldTickets > (cycleCount - 1) * numberOfTickets, "MlmLottery:: No tickets were sold in this cycle!");
        
        getRandomNumbers();
        for(uint256 i; i < winningTicketsCount; ++i) {
            if(i < winningTicketsCountByLevels[0]){
                rewardingReferrers(winningAmounts[0], ticketNumberToAddress[winningTickets[i]]);
            }
            else if(i >= winningTicketsCountByLevels[0] && i < winningTicketsCountByLevels[1] + winningTicketsCountByLevels[0]){
                rewardingReferrers(winningAmounts[1], ticketNumberToAddress[winningTickets[i]]);
            }
            else if(i >= winningTicketsCountByLevels[1] + winningTicketsCountByLevels[0] && i < winningTicketsCountByLevels[2] + winningTicketsCountByLevels[1] + winningTicketsCountByLevels[0]){
                rewardingReferrers(winningAmounts[2], ticketNumberToAddress[winningTickets[i]]);
            }
            else if(i >= winningTicketsCountByLevels[2] + winningTicketsCountByLevels[1] + winningTicketsCountByLevels[0] && i < winningTicketsCount){
                rewardingReferrers(winningAmounts[3], ticketNumberToAddress[winningTickets[i]]);
            }

            if(cycleCount > userInfo[ticketNumberToAddress[winningTickets[i]]].lastWonCycle){
                if(cycleCount - userInfo[ticketNumberToAddress[winningTickets[i]]].lastWonCycle == 1) {
                    userInfo[ticketNumberToAddress[winningTickets[i]]].numberOfWonCyclesInRow++;
                    if(userInfo[ticketNumberToAddress[winningTickets[i]]].numberOfWonCyclesInRow == bonusParameters[6]){
                        winningInRowBonus(ticketNumberToAddress[winningTickets[i]]);
                        userInfo[ticketNumberToAddress[winningTickets[i]]].numberOfWonCyclesInRow = 0;
                    }
                }
                else {
                    userInfo[ticketNumberToAddress[winningTickets[i]]].numberOfWonCyclesInRow = 1;
                }
                userInfo[ticketNumberToAddress[winningTickets[i]]].lastWonCycle = cycleCount;
            }   
        }
        emit WinnersRewarded(msg.sender, block.timestamp);
    }
    /**
    * @notice Function - rewardingReferrers
    * @dev Checking if winner is in MLM structure, and after it distribute rewards to his referrers.
    * @param _winningAmount Reward of winner.
    * @param _winnerAddress The Address of winner.
    * @dev Only the contract owner can execute this function.
    */
    function rewardingReferrers(uint256 _winningAmount, address _winnerAddress) private {
        address temp = addressToHisReferrer[_winnerAddress]; 
        for(uint8 j; j < 3; ++j) {
            if(temp == owner())
                break;
            IUSDT(tetherAddress).transferFrom(bankAddress, temp, (_winningAmount * parentsPercentages[j]) / 100);
            userInfo[temp].totalRewards += (_winningAmount * parentsPercentages[j]) / 100;
            temp = addressToHisReferrer[temp];
        }
        IUSDT(tetherAddress).transferFrom(bankAddress, _winnerAddress, _winningAmount);
        userInfo[_winnerAddress].totalRewards += _winningAmount; 
    }

    /**
    * @notice Function - getRandomNumbers
    * @dev Generating random numbers on chain for getting winning tickets (777 lottery).
    */
    function getRandomNumbers() private {
        uint16 i;
        uint256 ticketNumber;
        uint256 cycleStartTicket = (cycleCount - 1) * numberOfTickets + 1; // First ticket of this cycle
        uint256 cycleEndTicket = cycleCount * numberOfTickets; // Last ticket of this cycle

        while (winningTickets.length < winningTicketsCount) {
            ++i;
            ticketNumber = cycleStartTicket + 
                        (uint256(keccak256(abi.encodePacked(block.timestamp + i, block.number, msg.sender))) % numberOfTickets);

            // Ensure the ticket is unique
            if (!ticketUniqueness[ticketNumber]) {
                ticketUniqueness[ticketNumber] = true;
                winningTickets.push(ticketNumber);
            }
        }
}


    /**
    * @notice Function - getRandomNumberForMonthlyJackpot
    * @dev Generating only one random number on chain for getting winner of monthly jackpot.
    */
    function getRandomAddressForMonthlyJackpot() private view returns(address){
        uint256 ticket =  ((cycleCount - (monthlyJackpotWinningAmount / amountFromCycleToMonthlyJackpot)) * numberOfTickets) + uint256(keccak256(abi.encodePacked(block.timestamp,block.number, msg.sender))) % (numberOfTickets * (monthlyJackpotWinningAmount / amountFromCycleToMonthlyJackpot)) + 1; 
        return ticketNumberToAddress[ticket];
    }
    
    /**
    * @notice Function - getUserInfo
    * @param _user Address of User.
    * @dev Returns information about user.
    */
    function getUserInfo(address _user) external view OnlyAdmin returns(UserInfo memory) {
        return userInfo[_user];
    }

    function transferOwnership(address newOwner) public override onlyOwner {
        idToHisAddress[0] = newOwner;
        _transferOwnership(newOwner);
    }

    function enableContract(bool _isEnabled) external onlyOwner{
        enable = _isEnabled;
    }
}