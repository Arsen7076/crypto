// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;



contract test {
    function division(uint a,uint b) external pure returns (uint) {
        uint elapsedTime = (a-b)/30 days;
        uint totalAmount = 100;
        if (elapsedTime == 0 ){
            return 0;
        }
        else if (elapsedTime <= 10){
                return (totalAmount * 5)/ 100;
        }else if (elapsedTime <= 22){
                return (totalAmount * 3)/ 100;
        }else {
            return (totalAmount * 1) / 100;
        }}
        
    

    function getDay() external pure returns (uint){
        return  30 days;
    }

    function random()external returns(uint ticket) {
        uint256 ticket =  ((1 - (monthlyJackpotWinningAmount / amountFromCycleToMonthlyJackpot)) * 777) + uint256(keccak256(abi.encodePacked(block.timestamp,block.number, msg.sender))) % (numberOfTickets * (monthlyJackpotWinningAmount / amountFromCycleToMonthlyJackpot)) + 1; 

    }

}