// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/// @title VRSOracle
/// @notice Stores the Volatility Risk Score (0-100) pushed by the Reactive Smart Contract.
/// @dev The RSC callback address is the only authorized updater. Owner can rotate it.
contract VRSOracle {
    address public owner;
    address public authorizedUpdater;

    uint8 public vrs;
    uint256 public lastUpdated;

    // Fee tiers in hundredths of a bip (V4 units). Max fee = 1_000_000 (100%).
    uint24 public constant FEE_CALM      = 500;   // 0.05%
    uint24 public constant FEE_CLOUDY    = 1_500;  // 0.15%
    uint24 public constant FEE_STORM     = 3_000;  // 0.30%
    uint24 public constant FEE_HURRICANE = 5_000;  // 0.50%

    // VRS thresholds
    uint8 public constant THRESHOLD_CALM      = 30;
    uint8 public constant THRESHOLD_CLOUDY    = 60;
    uint8 public constant THRESHOLD_STORM     = 80;

    event VRSUpdated(uint8 indexed score, uint256 timestamp);
    event UpdaterRotated(address indexed oldUpdater, address indexed newUpdater);

    error Unauthorized();
    error InvalidScore();

    constructor(address _authorizedUpdater) {
        owner = msg.sender;
        authorizedUpdater = _authorizedUpdater;
        vrs = 0;
        lastUpdated = block.timestamp;
    }

    /// @notice Called by the Reactive RSC callback to push a new VRS score.
    function updateVRS(uint8 score) external {
        if (msg.sender != authorizedUpdater && msg.sender != owner) revert Unauthorized();
        if (score > 100) revert InvalidScore();
        vrs = score;
        lastUpdated = block.timestamp;
        emit VRSUpdated(score, block.timestamp);
    }

    /// @notice Returns the dynamic fee that the hook should charge for this VRS level.
    function getFee() external view returns (uint24) {
        return _feeForScore(vrs);
    }

    /// @notice Returns whether current conditions are storm-level or above (VRS > 60).
    function isStorm() external view returns (bool) {
        return vrs > THRESHOLD_CLOUDY;
    }

    /// @notice Returns a human-readable risk label for the current VRS.
    function getRiskLevel() external view returns (string memory) {
        if (vrs <= THRESHOLD_CALM)   return "CALM";
        if (vrs <= THRESHOLD_CLOUDY) return "CLOUDY";
        if (vrs <= THRESHOLD_STORM)  return "STORM";
        return "HURRICANE";
    }

    /// @notice Owner can rotate the authorized updater (e.g. after RSC redeployment).
    function setAuthorizedUpdater(address _updater) external {
        if (msg.sender != owner) revert Unauthorized();
        emit UpdaterRotated(authorizedUpdater, _updater);
        authorizedUpdater = _updater;
    }

    function transferOwnership(address _newOwner) external {
        if (msg.sender != owner) revert Unauthorized();
        owner = _newOwner;
    }

    function _feeForScore(uint8 score) internal pure returns (uint24) {
        if (score <= THRESHOLD_CALM)   return FEE_CALM;
        if (score <= THRESHOLD_CLOUDY) return FEE_CLOUDY;
        if (score <= THRESHOLD_STORM)  return FEE_STORM;
        return FEE_HURRICANE;
    }
}
