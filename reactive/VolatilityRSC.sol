// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

// ─────────────────────────────────────────────────────────────────────────────
// Reactive Network interfaces (inlined from reactive-lib to avoid extra dep)
// Source: https://github.com/Reactive-Network/reactive-lib
// ─────────────────────────────────────────────────────────────────────────────

interface IPayable {
    receive() external payable;
    function debt(address _contract) external view returns (uint256);
}

interface IPayer {
    function pay(uint256 amount) external;
    receive() external payable;
}

interface ISubscriptionService is IPayable {
    function subscribe(
        uint256 chain_id,
        address _contract,
        uint256 topic_0,
        uint256 topic_1,
        uint256 topic_2,
        uint256 topic_3
    ) external;

    function unsubscribe(
        uint256 chain_id,
        address _contract,
        uint256 topic_0,
        uint256 topic_1,
        uint256 topic_2,
        uint256 topic_3
    ) external;
}

interface ISystemContract is IPayable, ISubscriptionService {}

interface IReactive is IPayer {
    struct LogRecord {
        uint256 chain_id;
        address _contract;
        uint256 topic_0;
        uint256 topic_1;
        uint256 topic_2;
        uint256 topic_3;
        bytes   data;
        uint256 block_number;
        uint256 op_code;
        uint256 block_hash;
        uint256 tx_hash;
        uint256 log_index;
    }

    event Callback(
        uint256 indexed chain_id,
        address indexed _contract,
        uint64  indexed gas_limit,
        bytes payload
    );

    function react(LogRecord calldata log) external;
}

// ─────────────────────────────────────────────────────────────────────────────
// VolatilityRSC — Reactive Smart Contract for VolatilityVault
// ─────────────────────────────────────────────────────────────────────────────

/// @title VolatilityRSC
/// @notice Reactive Smart Contract deployed on Reactive Network.
///
/// Subscribes to Uniswap V4 Swap events from PoolManager contracts across
/// multiple chains. On each swap event:
///   1. Decodes sqrtPriceX96 and swap amounts from log data
///   2. Computes a Volatility Risk Score (VRS) 0-100 from price movement
///      and swap size signals
///   3. If VRS changed significantly, emits a Callback to push the new score
///      to VRSOracle.sol on the destination chain
///   4. If VRS just dropped to calm (storm over), also triggers
///      YieldBuffer.triggerDistribution()
///
/// Deployment: forge script or direct deploy on Reactive Lasna testnet.
/// After deploy: set this contract's callback proxy as the authorized
/// updater in VRSOracle and authorized trigger in YieldBuffer.
///
/// @dev Reactive Network docs: https://dev.reactive.network/
contract VolatilityRSC is IReactive {

    // ── Constants ─────────────────────────────────────────────────────────────

    // Reactive Network system contract address (same on all Reactive deployments)
    ISystemContract internal constant SERVICE =
        ISystemContract(payable(0x0000000000000000000000000000000000fffFfF));

    // REACTIVE_IGNORE: wildcard for subscribe() — matches any value
    uint256 internal constant REACTIVE_IGNORE =
        0xa65f96fc951c35ead38878e0f0b7a3c744a6f5ccc1476b313353ce31712313ad;

    // keccak256("Swap(bytes32,address,int128,int128,uint160,uint128,int24,uint24)")
    // This is the topic_0 of the Uniswap V4 PoolManager Swap event (verified via cast keccak)
    uint256 public constant SWAP_TOPIC_0 =
        0x40e9cecb9f5f1f1c5b9c97dec2917b7ee92e57ba5563708daca94dd84ad7112f;

    uint64 internal constant GAS_LIMIT = 500_000;

    // VRS thresholds — match VRSOracle.sol
    uint8 constant THRESHOLD_CALM    = 30;
    uint8 constant THRESHOLD_CLOUDY  = 60;
    uint8 constant THRESHOLD_STORM   = 80;

    // Minimum VRS change to trigger an oracle update (saves gas on tiny moves)
    uint8 constant MIN_VRS_DELTA = 3;

    // ── State ─────────────────────────────────────────────────────────────────

    address public owner;
    bool    internal isVm;  // true when running inside ReactVM (not top-level RN)

    // Destination chain and the callback receiver adapter on that chain.
    // Reactive calls the receiver (through the callback proxy), injecting
    // `address sender` as the first arg; the receiver forwards to VRSOracle/YieldBuffer.
    uint256 public destinationChainId;
    address public callbackReceiver;

    // Rolling volatility state
    uint160 public lastSqrtPrice;
    uint256 public lastBlockNumber;
    uint256 public swapCountInWindow;
    uint8   public currentVRS;
    bool    public wasStorm;  // tracks transition from storm -> calm for buffer trigger

    // ── Events ────────────────────────────────────────────────────────────────

    event VRSComputed(uint8 vrs, uint256 priceChangeBps, uint256 swapCount);
    event OracleUpdateTriggered(uint8 vrs, uint256 destinationChainId);
    event BufferDistributionTriggered(uint256 destinationChainId);

    // ── Errors ────────────────────────────────────────────────────────────────

    error Unauthorized();

    // ── Constructor ───────────────────────────────────────────────────────────

    /// @param _originChainIds     Chain IDs to subscribe to (e.g. [11155111] for Sepolia)
    /// @param _poolManagers       PoolManager addresses on each origin chain
    /// @param _destinationChainId Chain ID where the callback receiver lives
    /// @param _callbackReceiver   VRSCallbackReceiver adapter on destination chain
    constructor(
        uint256[] memory _originChainIds,
        address[]  memory _poolManagers,
        uint256 _destinationChainId,
        address _callbackReceiver
    ) payable {
        require(_originChainIds.length == _poolManagers.length, "length mismatch");

        owner              = msg.sender;
        destinationChainId = _destinationChainId;
        callbackReceiver   = _callbackReceiver;

        // Detect whether we're inside ReactVM or on top-level Reactive Network
        uint256 size;
        assembly { size := extcodesize(0x0000000000000000000000000000000000fffFfF) }
        isVm = (size == 0);

        // Subscribe to Swap events from each PoolManager on each origin chain
        // Only subscribe on top-level RN (not inside ReactVM)
        if (!isVm) {
            for (uint256 i = 0; i < _originChainIds.length; i++) {
                SERVICE.subscribe(
                    _originChainIds[i],
                    _poolManagers[i],
                    SWAP_TOPIC_0,
                    REACTIVE_IGNORE,  // any poolId
                    REACTIVE_IGNORE,  // any sender
                    REACTIVE_IGNORE
                );
            }
        }
    }

    // ── IPayer ────────────────────────────────────────────────────────────────

    receive() external payable {}

    function pay(uint256 amount) external {
        require(msg.sender == address(SERVICE), "SERVICE only");
        _pay(payable(msg.sender), amount);
    }

    function _pay(address payable recipient, uint256 amount) internal {
        require(address(this).balance >= amount, "Insufficient funds");
        if (amount > 0) {
            (bool ok,) = recipient.call{value: amount}(new bytes(0));
            require(ok, "Transfer failed");
        }
    }

    // ── Core logic — react() ──────────────────────────────────────────────────

    /// @notice Called by Reactive Network every time a subscribed Swap event fires.
    /// @dev Only executes inside ReactVM (vmOnly pattern).
    function react(LogRecord calldata log) external override {
        require(isVm, "VM only");

        // Decode the Uniswap V4 Swap event data
        // Event data layout: (int128 amount0, int128 amount1, uint160 sqrtPriceX96,
        //                     uint128 liquidity, int24 tick, uint24 fee)
        (
            ,              // amount0 (unused)
            ,              // amount1 (unused)
            uint160 sqrtPriceX96,
            ,              // liquidity
            ,              // tick
                           // fee
        ) = abi.decode(log.data, (int128, int128, uint160, uint128, int24, uint24));

        // ── Compute VRS ───────────────────────────────────────────────────────

        uint8 newVRS = _computeVRS(sqrtPriceX96, log.block_number);

        emit VRSComputed(newVRS, _priceChangeBps(sqrtPriceX96), swapCountInWindow);

        // Only trigger callback if VRS moved enough to matter
        if (_abs8(newVRS, currentVRS) >= MIN_VRS_DELTA) {
            // Reactive injects `address sender` (the RVM id) as the first arg of the
            // callback; we pass address(0) as the placeholder the network fills in.
            bytes memory updatePayload = abi.encodeWithSignature(
                "updateVRS(address,uint8)",
                address(0),
                newVRS
            );
            emit Callback(destinationChainId, callbackReceiver, GAS_LIMIT, updatePayload);
            emit OracleUpdateTriggered(newVRS, destinationChainId);

            // If transitioning from storm -> calm, trigger yield buffer distribution
            bool isNowCalm = newVRS <= THRESHOLD_CALM;
            if (wasStorm && isNowCalm) {
                bytes memory distributePayload = abi.encodeWithSignature(
                    "triggerDistribution(address)",
                    address(0)
                );
                emit Callback(destinationChainId, callbackReceiver, GAS_LIMIT, distributePayload);
                emit BufferDistributionTriggered(destinationChainId);
            }

            // Update state
            wasStorm   = newVRS > THRESHOLD_CALM;
            currentVRS = newVRS;
        }

        // Update price tracking state
        lastSqrtPrice   = sqrtPriceX96;
        lastBlockNumber = log.block_number;
    }

    // ── VRS computation ───────────────────────────────────────────────────────

    /// @notice Compute VRS 0-100 from current swap data.
    /// @dev Combines price velocity (how far price moved) and swap frequency
    ///      (how many swaps in recent blocks).
    function _computeVRS(uint160 sqrtPriceX96, uint256 blockNumber) internal returns (uint8) {
        // Track swap count in a sliding window (reset every 10 blocks)
        if (blockNumber > lastBlockNumber + 10) {
            swapCountInWindow = 1;
        } else {
            swapCountInWindow++;
        }

        // Price change signal (in basis points relative to last price)
        uint256 priceChangeBps = _priceChangeBps(sqrtPriceX96);

        // Swap frequency signal (swaps per window)
        uint256 freqScore = swapCountInWindow * 5;

        // Combine: price change dominates, frequency adds pressure
        // Scale: 100 bps price change = VRS 20, 10 swaps = VRS 50
        uint256 rawScore = (priceChangeBps * 20) / 100 + freqScore;

        return uint8(rawScore > 100 ? 100 : rawScore);
    }

    function _priceChangeBps(uint160 sqrtPriceX96) internal view returns (uint256) {
        if (lastSqrtPrice == 0) return 0;
        uint256 delta = sqrtPriceX96 > lastSqrtPrice
            ? sqrtPriceX96 - lastSqrtPrice
            : lastSqrtPrice - sqrtPriceX96;
        return (delta * 10_000) / lastSqrtPrice;
    }

    function _abs8(uint8 a, uint8 b) internal pure returns (uint8) {
        return a > b ? a - b : b - a;
    }

    // ── Admin ─────────────────────────────────────────────────────────────────

    modifier onlyOwner() {
        if (msg.sender != owner) revert Unauthorized();
        _;
    }

    /// @notice Add a new chain+pool subscription after deployment.
    function subscribe(uint256 chainId, address poolManager) external onlyOwner {
        SERVICE.subscribe(chainId, poolManager, SWAP_TOPIC_0, REACTIVE_IGNORE, REACTIVE_IGNORE, REACTIVE_IGNORE);
    }

    /// @notice Remove a subscription.
    function unsubscribe(uint256 chainId, address poolManager) external onlyOwner {
        SERVICE.unsubscribe(chainId, poolManager, SWAP_TOPIC_0, REACTIVE_IGNORE, REACTIVE_IGNORE, REACTIVE_IGNORE);
    }

    function setCallbackReceiver(address _receiver) external onlyOwner { callbackReceiver = _receiver; }
    function setDestinationChain(uint256 _chainId) external onlyOwner { destinationChainId = _chainId; }
    function transferOwnership(address _newOwner) external onlyOwner { owner = _newOwner; }

    /// @notice Withdraw ETH (used to fund gas for callbacks).
    function withdraw(uint256 amount) external onlyOwner {
        _pay(payable(owner), amount);
    }
}
