// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "./access.sol";

/**
 * @title GenericLinearVesting
 * @notice A linear vesting contract that unlocks a constant percentage each month.
 *         Supports batch creation of vesting schedules with the same parameters.
 */
contract GenericLinearVesting is AccessControlBase {
    ERC20 public token;

    struct VestingSchedule {
        address beneficiary;
        uint256 total;
        uint256 claimed;
        uint256 startTime;
        uint256 totalMonths;
        bool isActive;
    }

    mapping(uint256 => VestingSchedule) public schedules;
    uint256 public scheduleCount;

    event VestingCreated(uint256 indexed scheduleId, address beneficiary, uint256 total);
    event BatchVestingCreated(uint256[] scheduleIds, address[] beneficiaries, uint256 totalAmount);
    event Claimed(uint256 indexed scheduleId, address beneficiary, uint256 amount);
    event Revoked(uint256 scheduleId);

    constructor(address _token) {
        require(_token != address(0), "Token address cannot be zero");
        token = ERC20(_token);
    }

    // ------------------------------------------------------------------------
    // Create Vesting Schedule
    // ------------------------------------------------------------------------
    function createVesting(
        address beneficiary,
        uint256 totalAmount,
        uint256 startTime,
        uint256 totalMonths
    ) external onlyAdminOrOwner returns (uint256 scheduleId) {
        require(beneficiary != address(0), "Beneficiary address cannot be zero");
        require(totalAmount > 0, "Total amount must be greater than zero");
        require(totalMonths > 0, "Total months must be greater than zero");

        scheduleId = scheduleCount;
        schedules[scheduleId] = VestingSchedule({
            beneficiary: beneficiary,
            total: totalAmount,
            claimed: 0,
            startTime: startTime,
            totalMonths: totalMonths,
            isActive: true
        });
        scheduleCount += 1;
        emit VestingCreated(scheduleId, beneficiary, totalAmount);
    }

    function createBatchVesting(
        address[] calldata beneficiaries,
        uint256 totalAmount,
        uint256 startTime,
        uint256 totalMonths
    ) external onlyAdminOrOwner returns (uint256[] memory scheduleIds) {
        require(beneficiaries.length > 0, "No beneficiaries provided");
        require(totalAmount > 0, "Total amount must be greater than zero");
        require(totalMonths > 0, "Total months must be greater than zero");

        scheduleIds = new uint256[](beneficiaries.length);
        uint256 amountPerBeneficiary = totalAmount / beneficiaries.length;

        for (uint256 i = 0; i < beneficiaries.length; i++) {
            require(beneficiaries[i] != address(0), "Beneficiary address cannot be zero");

            uint256 scheduleId = scheduleCount;
            schedules[scheduleId] = VestingSchedule({
                beneficiary: beneficiaries[i],
                total: amountPerBeneficiary,
                claimed: 0,
                startTime: startTime,
                totalMonths: totalMonths,
                isActive: true
            });
            scheduleIds[i] = scheduleId;
            scheduleCount += 1;

            emit VestingCreated(scheduleId, beneficiaries[i], amountPerBeneficiary);
        }

        emit BatchVestingCreated(scheduleIds, beneficiaries, totalAmount);
    }

    // ------------------------------------------------------------------------
    // Revoke Vesting Schedule
    // ------------------------------------------------------------------------
    function revokeVesting(uint256 scheduleId) external onlyAdminOrOwner {
        VestingSchedule storage vs = schedules[scheduleId];
        require(vs.isActive, "Already inactive");
        vs.isActive = false;
        emit Revoked(scheduleId);
    }

    // ------------------------------------------------------------------------
    // Claim Tokens
    // ------------------------------------------------------------------------
    function claim(uint256 scheduleId) external {
        VestingSchedule storage vs = schedules[scheduleId];
        require(vs.isActive, "Not active");
        require(vs.beneficiary == msg.sender, "Not beneficiary");

        uint256 vested = _vestedAmount(vs);
        uint256 unreleased = vested > vs.claimed ? vested - vs.claimed : 0;
        require(unreleased > 0, "No tokens to claim");
        vs.claimed += unreleased;
        token.transfer(msg.sender, unreleased);

        emit Claimed(scheduleId, msg.sender, unreleased);
    }

    // ------------------------------------------------------------------------
    // Get Vesting Schedules for User
    // ------------------------------------------------------------------------
    function getUserSchedules() external view returns (uint256[] memory userSchedules) {
        uint256 count = 0;

        // First, count the schedules for the user
        for (uint256 i = 0; i < scheduleCount; i++) {
            if (schedules[i].beneficiary == msg.sender) {
                count++;
            }
        }

        // Create an array and populate it with the user's schedule IDs
        userSchedules = new uint256[](count);
        uint256 index = 0;
        for (uint256 i = 0; i < scheduleCount; i++) {
            if (schedules[i].beneficiary == msg.sender) {
                userSchedules[index] = i;
                index++;
            }
        }
    }

    // ------------------------------------------------------------------------
    // Internal Logic for Vested Amount
    // ------------------------------------------------------------------------
    function _vestedAmount(VestingSchedule memory vs) internal view returns (uint256) {
        uint256 start = vs.startTime;
        if (block.timestamp < start) {
            return 0;
        }
        uint256 endTime = start + vs.totalMonths * 30 days;
        if (block.timestamp >= endTime) {
            return vs.total;
        }
        // Calculate linear vesting
        uint256 elapsedMonths = (block.timestamp - start) / 30 days;
        uint256 vestedAmount = (vs.total * elapsedMonths) / vs.totalMonths;
        return vestedAmount;
    }
}
