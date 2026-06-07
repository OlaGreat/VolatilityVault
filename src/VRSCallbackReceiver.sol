// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

interface IVRSOracleUpdatable {
    function updateVRS(uint8 score) external;
}

interface IYieldBufferTriggerable {
    function triggerDistribution() external;
}

/// @title VRSCallbackReceiver
/// @notice Destination-chain adapter that receives Reactive Network callbacks and
///         forwards them to the already-deployed VRSOracle and YieldBuffer.
///
/// Reactive's callback proxy calls this contract and injects `address sender`
/// (the RVM id) as the first argument of each callback function. This adapter
/// authorizes only the callback proxy, then forwards to the core contracts —
/// so the oracle/hook/pool never had to be redeployed to be Reactive-compatible.
///
/// Setup after deploy:
///   1. VRSOracle.setAuthorizedUpdater(address(this))
///   2. YieldBuffer.setAuthorizedTrigger(address(this))
///   3. Fund this contract with a little Sepolia ETH to settle callback debt
///
/// Sepolia callback proxy: 0xc9f36411C9897e7F959D99ffca2a0Ba7ee0D7bDA
contract VRSCallbackReceiver {
    address public owner;
    address public callbackProxy;       // Reactive callback proxy (authorized sender)
    IVRSOracleUpdatable    public oracle;
    IYieldBufferTriggerable public buffer;

    event VRSForwarded(uint8 score);
    event DistributionForwarded();
    event CallbackProxyUpdated(address indexed newProxy);

    error Unauthorized();

    constructor(address _callbackProxy, address _oracle, address _buffer) {
        owner         = msg.sender;
        callbackProxy = _callbackProxy;
        oracle        = IVRSOracleUpdatable(_oracle);
        buffer        = IYieldBufferTriggerable(_buffer);
    }

    modifier onlyProxy() {
        if (msg.sender != callbackProxy) revert Unauthorized();
        _;
    }

    modifier onlyOwner() {
        if (msg.sender != owner) revert Unauthorized();
        _;
    }

    // ── Reactive callbacks (first arg `sender` injected by the proxy) ───────────

    /// @notice Called by the Reactive callback proxy to push a new VRS score.
    function updateVRS(address /* sender */, uint8 score) external onlyProxy {
        oracle.updateVRS(score);
        emit VRSForwarded(score);
    }

    /// @notice Called by the Reactive callback proxy when a storm ends.
    function triggerDistribution(address /* sender */) external onlyProxy {
        buffer.triggerDistribution();
        emit DistributionForwarded();
    }

    // ── Payment handling (Reactive debt settlement) ────────────────────────────

    /// @notice The callback proxy calls this to collect payment for callback gas.
    function pay(uint256 amount) external onlyProxy {
        (bool ok, ) = payable(msg.sender).call{value: amount}("");
        require(ok, "pay failed");
    }

    receive() external payable {}

    /// @notice Fund this contract so it can settle callback debt.
    function fund() external payable {}

    // ── Admin ──────────────────────────────────────────────────────────────────

    function setCallbackProxy(address _proxy) external onlyOwner {
        callbackProxy = _proxy;
        emit CallbackProxyUpdated(_proxy);
    }

    function setOracle(address _oracle) external onlyOwner { oracle = IVRSOracleUpdatable(_oracle); }
    function setBuffer(address _buffer) external onlyOwner { buffer = IYieldBufferTriggerable(_buffer); }
    function transferOwnership(address _newOwner) external onlyOwner { owner = _newOwner; }

    function withdraw(uint256 amount) external onlyOwner {
        (bool ok, ) = payable(owner).call{value: amount}("");
        require(ok, "withdraw failed");
    }
}
