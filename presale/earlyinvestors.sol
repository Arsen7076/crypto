// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
import "./access.sol";

interface IToken {
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
}

contract EarlyInvestors is AccessControlBase {
    struct VestingSchedule {
        uint256 totalAmount;       // Total tokens allocated
        uint256 releasedAmount;    // Amount of tokens already released
        uint256 startTime;  
        uint256 cliff;
        uint256 duration; 
        bool [36] monthsClaimed;
    }

    bool isListed;


    address public admin;                // Admin address
    IToken public token;                 // Token being vested
    address presale;
    mapping (address => bool) blacklisted;
    mapping(address => mapping(uint => VestingSchedule)) public schedules; // Vesting schedules per beneficiary
    mapping (address => uint256) scheduleCount;

    event TokensReleased(address beneficiary, uint256 amount);
    event VestingScheduleAdded(address beneficiary, uint256 totalAmount, uint256 startTime, uint256 cliff, uint256 duration);


    constructor(address _token) {
        require(_token != address(0), "Invalid token address");
        admin = msg.sender;
        token = IToken(_token);
    }
    modifier onlyPresale() {
        require(msg.sender == presale, "Not Presale");
        _;
    }
    function setPresaleAddress(address _presale) external onlyAdminOrOwner{
        require(_presale != address(0), "Master can't be 0 address");
        presale = _presale;
    }
    function setListed()external onlyAdminOrOwner{
        isListed = true;
    }


    function addVestingSchedule(
    address _beneficiary,
    uint256 _totalAmount
) external onlyPresale {
    require(_beneficiary != address(0), "Invalid beneficiary address");
    require(_totalAmount > 0, "Total amount must be greater than zero");

    uint256 _startTime = block.timestamp;
    uint256 _cliff = 90 days;
    uint256 _duration = 1080 days;

    uint256 currentIndex = scheduleCount[_beneficiary];

    // Проверяем пересечение временных интервалов
    for (uint256 i = 0; i < currentIndex; i++) {
        VestingSchedule memory existingSchedule = schedules[_beneficiary][i];
        uint256 existingStart = existingSchedule.startTime;
        uint256 existingEnd = existingSchedule.startTime + existingSchedule.cliff + existingSchedule.duration;
        uint256 newStart = _startTime;
        uint256 newEnd = _startTime + _cliff + _duration;

        require(
            newEnd <= existingStart || newStart >= existingEnd,
            "Vesting period conflicts with an existing schedule"
        );
    }

    schedules[_beneficiary][currentIndex] = VestingSchedule({
        totalAmount: _totalAmount,
        releasedAmount: 0,
        startTime: _startTime,
        cliff: _cliff,
        duration: _duration,
        monthsClaimed: [
            false, false, false, false, false, false, false, false, false, false, false, false,
            false, false, false, false, false, false, false, false, false, false, false, false,
            false, false, false, false, false, false, false, false, false, false, false, false
        ]
    });

    scheduleCount[_beneficiary] += 1;

    emit VestingScheduleAdded(_beneficiary, _totalAmount, _startTime, _cliff, _duration);
    }


    function releaseTokens() external {
        require(!blacklisted[msg.sender], "You are blacklisted");
        uint256 count = scheduleCount[msg.sender];
        require(count > 0, "No vesting schedules for this beneficiary");

        uint256 totalReleasable = 0;

        for (uint256 i = 0; i < count; i++) {
            VestingSchedule storage schedule = schedules[msg.sender][i]; // Используем `storage` для сохранения изменений

            if (block.timestamp > schedule.startTime + schedule.cliff && !isListed) {
                uint256 currentMonth = (block.timestamp - (schedule.startTime + schedule.cliff)) / 30 days;

                if (currentMonth < 36 && !schedule.monthsClaimed[currentMonth]) {
                    uint256 vestedAmount = _vestedAmount(schedule);
                    uint256 releasableAmount = vestedAmount - schedule.releasedAmount;

                    if (releasableAmount > 0) {
                        schedule.releasedAmount += releasableAmount;
                        totalReleasable += releasableAmount;
                    }
                    schedule.monthsClaimed[currentMonth] = true;
                }
            } else if (block.timestamp > schedule.startTime + schedule.cliff && isListed) {
                uint256 currentMonth = (block.timestamp - (schedule.startTime + schedule.cliff)) / 30 days;

                for (uint256 j = 0; j <= currentMonth && j < 36; j++) {
                    if (!schedule.monthsClaimed[j]) {
                        uint256 percentage = j <= 10
                            ? 5
                            : j <= 22
                            ? 3
                            : 1;

                        uint256 monthlyAmount = (schedule.totalAmount * percentage) / 100;
                        totalReleasable += monthlyAmount;
                        schedule.releasedAmount += monthlyAmount;
                        schedule.monthsClaimed[j] = true;
                    }
                }
            }
        }

        require(totalReleasable > 0, "No tokens to release");
        require(token.balanceOf(address(this)) >= totalReleasable, "Insufficient balance");
        require(token.transferFrom(presale, msg.sender, totalReleasable), "Token transfer failed");

        emit TokensReleased(msg.sender, totalReleasable);
    }


    function _vestedAmount(VestingSchedule memory schedule) internal view returns (uint256) {
        if (block.timestamp >= schedule.startTime + schedule.duration + schedule.cliff) {
            return schedule.totalAmount;
        } else {
            uint256 elapsedMonths = ((block.timestamp - (schedule.startTime + schedule.cliff)) / 30 days) ;
            if (elapsedMonths == 0) {
                return 0;
            } else if (elapsedMonths <= 10) {
                return (schedule.totalAmount * 5 ) / 100;
            } else if (elapsedMonths <= 22) {
                return (schedule.totalAmount  * 3) / 100;
            } else {
                return (schedule.totalAmount * 1) / 100;
            }
        }
    }


    function withdrawTokens(address _to, uint256 _amount) external onlyAdminOrOwner {
        require(token.balanceOf(address(this)) >= _amount, "Insufficient balance");
        require(token.transfer(_to, _amount), "Token transfer failed");
    }

    function withdrawEther(address _to, uint256 _amount) external onlyAdminOrOwner {
        require(address(this).balance >= _amount, "Insufficient ether balance");
        payable(_to).transfer(_amount);
    }

    function revokeVesting(address user) external onlyAdminOrOwner{
        require(user != address(0), "Invalid beneficiary address");
        blacklisted[user] = true;
    }
}