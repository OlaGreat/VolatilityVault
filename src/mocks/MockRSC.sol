// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {VRSOracle} from "../VRSOracle.sol";
import {YieldBuffer} from "../YieldBuffer.sol";

/// @title MockRSC
/// @notice Simulates the Reactive Smart Contract for local testing and demo.
///         In production this is replaced by the actual VolatilityRSC deployed
///         on Reactive Network, which monitors cross-chain signals automatically.
contract MockRSC {
    VRSOracle   public oracle;
    YieldBuffer public buffer;
    address     public owner;

    event VRSPushed(uint8 score);
    event YieldDeployed(uint256 epoch);
    event DistributionTriggered(uint256 epoch);

    error Unauthorized();

    constructor(VRSOracle _oracle, YieldBuffer _buffer) {
        oracle = _oracle;
        buffer = _buffer;
        owner  = msg.sender;
    }

    modifier onlyOwner() {
        if (msg.sender != owner) revert Unauthorized();
        _;
    }

    /// @notice Push a new VRS score to the oracle (simulates RSC cross-chain callback).
    function pushVRS(uint8 score) external onlyOwner {
        oracle.updateVRS(score);
        emit VRSPushed(score);
    }

    /// @notice Deploy buffered fees to yield protocol (simulates RSC automation).
    function deployBufferToYield() external onlyOwner {
        uint256 epoch = buffer.currentEpoch();
        buffer.deployToYield();
        emit YieldDeployed(epoch);
    }

    /// @notice Trigger LP distribution — call when VRS normalizes (simulates RSC callback).
    function triggerDistribution() external onlyOwner {
        uint256 epoch = buffer.currentEpoch();
        buffer.triggerDistribution();
        emit DistributionTriggered(epoch);
    }

    /// @notice Convenience: push VRS + immediately trigger distribution in one call.
    function stormOver(uint8 calmScore) external onlyOwner {
        oracle.updateVRS(calmScore);
        buffer.triggerDistribution();
        emit VRSPushed(calmScore);
        emit DistributionTriggered(buffer.currentEpoch() - 1);
    }
}
