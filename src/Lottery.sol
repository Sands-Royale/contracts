// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {BaseHook, Hooks, IPoolManager} from "v4-periphery/base/hooks/BaseHook.sol";

import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";

import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {BeforeSwapDelta} from "@uniswap/v4-core/src/types/BeforeSwapDelta.sol";
import {StateLibrary} from "@uniswap/v4-core/src/libraries/StateLibrary.sol";
import {LiquidityAmounts} from "./external/LiquidityAmounts.sol";

import "./ILottery.sol";
import "./external/IEntropy.sol";
import "./external/IEntropyConsumer.sol";
import "./LotteryManager.sol";

contract Lottery is ILottery, IEntropyConsumer, BaseHook {
    LotteryState public lotteryState;

    IEntropy private entropy;
    address private entropyProvider;

    // set to true when run lottery is initiated, if true, lottery cannot be run twice
    bool public lotteryLock;
    // set to true when entropy callback has been run, if true, entropy callback cannot be run twice
    bool public entropyCallbackLock;

    IERC20 public usdcToken;
    IERC20 public lotteryToken;

    uint256 public constant DRAW_INTERVAL = 100; // 100 blocks
    uint256 public constant TICKET_PRICE = 10 * 1e6; // 10 USDC
    uint8 public constant LP_RISK_PERCENTAGE = 80; // 80% of LP funds at risk

    mapping(address => User) public usersInfo;
    mapping(address => LP) public lpsInfo;

    mapping(address => uint256) public lpStakes;
    mapping(address => uint256) public playerTickets;

    address[] public activeUserAddresses;
    address[] public activeLpAddresses;

    uint256 totalTicketCountBps;

    // total amount in user pool in ETH
    uint256 public userPoolTotal;

    // total amount in LP pool
    uint256 public lpPoolTotal;

    address public lastWinnerAddress;

    LotteryManager manager;

    constructor(IPoolManager _poolManager, address _usdcToken, address _lotteryToken) BaseHook(_poolManager) {
        usdcToken = IERC20(_usdcToken);
        lotteryToken = IERC20(_lotteryToken);
        lotteryState.isActive = true;
        manager = LotteryManager(msg.sender);
    }

    function getHookPermissions() public pure override returns (Hooks.Permissions memory) {
        return Hooks.Permissions({
            beforeInitialize: true,
            afterInitialize: false,
            beforeAddLiquidity: true,
            afterAddLiquidity: false,
            beforeRemoveLiquidity: true,
            afterRemoveLiquidity: false,
            beforeSwap: true,
            afterSwap: true,
            beforeDonate: false,
            afterDonate: false,
            beforeSwapReturnDelta: false,
            afterSwapReturnDelta: false,
            afterAddLiquidityReturnDelta: false,
            afterRemoveLiquidityReturnDelta: false
        });
    }

    function beforeSwap(address, PoolKey calldata, IPoolManager.SwapParams calldata params, bytes calldata hookData)
        external
        virtual
        override
        returns (bytes4, BeforeSwapDelta, uint24)
    {
        (address user, bytes32 randomNumber) = abi.decode(hookData, (address, bytes32));

        if (params.zeroForOne) {
            // Buying lottery tickets (USDC -> Lottery Token)
            uint256 ticketsBought = (uint256(params.amountSpecified) / TICKET_PRICE) * 10000;
            require(ticketsBought > 0, "Must buy at least one ticket");
            playerTickets[user] += ticketsBought;
            lotteryState.userPool += uint256(params.amountSpecified);
            totalTicketCountBps += ticketsBought;
            userPoolTotal += uint256(params.amountSpecified);
            _addActiveUser(user);
        } else {
            // Selling lottery tickets (Lottery Token -> USDC)
            uint256 ticketsSold = (uint256(params.amountSpecified) / TICKET_PRICE) * 10000;
            require(ticketsSold > 0, "Must sell at least one ticket");
            require(playerTickets[user] >= ticketsSold, "Not enough tickets");

            playerTickets[user] -= ticketsSold;
            lotteryState.userPool -= uint256(params.amountSpecified);
            totalTicketCountBps -= ticketsSold;
            userPoolTotal -= uint256(params.amountSpecified);
        }

        if (block.number >= lotteryState.lastDrawBlock + DRAW_INTERVAL) {
            runLottery(randomNumber);
        }

        return (BaseHook.beforeSwap.selector, BeforeSwapDelta.wrap(0), 0);
    }

    function _addActiveUser(address _user) private {
        User storage user = usersInfo[_user];
        if (!user.active) {
            user.active = true;
            // Add new user address, will be reset when lottery ends
            activeUserAddresses.push(_user);
        }
    }

    function _addActiveLP(address _lp) private {
        LP storage lp = lpsInfo[_lp];
        if (!lp.active) {
            lp.active = true;
            // Add newly active LP address
            activeLpAddresses.push(_lp);
        }
    }

    function beforeAddLiquidity(
        address,
        PoolKey calldata key,
        IPoolManager.ModifyLiquidityParams calldata params,
        bytes calldata hookData
    ) external override returns (bytes4) {
        (address user, address _manager) = abi.decode(hookData, (address,address));
        if (address(manager) != _manager) {
            revert("Invalid caller");
        }

        (uint160 sqrtPriceX96,,,) = StateLibrary.getSlot0(IPoolManager(address(poolManager)), key.toId());

        (, uint256 amount1) = LiquidityAmounts.getAmountsForLiquidity(
            sqrtPriceX96,
            TickMath.getSqrtPriceAtTick(params.tickLower),
            TickMath.getSqrtPriceAtTick(params.tickUpper),
            uint128(int128(params.liquidityDelta))
        );

        if (params.liquidityDelta > 0) {
            // Adding liquidity
            lpStakes[user] += amount1;
            lotteryState.lpPool += amount1 * LP_RISK_PERCENTAGE / 100;
            lpPoolTotal += amount1;
            lpsInfo[user].principal += amount1;
            _addActiveLP(user);
        }

        return BaseHook.beforeAddLiquidity.selector;
    }

    function beforeRemoveLiquidity(
        address,
        PoolKey calldata key,
        IPoolManager.ModifyLiquidityParams calldata params,
        bytes calldata hookData
    ) external override returns (bytes4) {
        address user = abi.decode(hookData, (address));

        (uint160 sqrtPriceX96,,,) = StateLibrary.getSlot0(IPoolManager(address(poolManager)), key.toId());

        (, uint256 amount1) = LiquidityAmounts.getAmountsForLiquidity(
            sqrtPriceX96,
            TickMath.getSqrtPriceAtTick(int24(params.tickLower)),
            TickMath.getSqrtPriceAtTick(int24(params.tickUpper)),
            uint128(int128(params.liquidityDelta))
        );

        if (params.liquidityDelta < 0) {
            // Removing liquidity
            uint256 stake = lpStakes[user];
            require(stake >= amount1, "Insufficient LP stake");
            lpStakes[user] -= amount1;
            lotteryState.lpPool -= amount1 * LP_RISK_PERCENTAGE / 100;
            lpPoolTotal -= amount1;
            lpsInfo[user].principal -= amount1;
        }

        manager.removeLiquidity(user, amount1);

        return BaseHook.beforeRemoveLiquidity.selector;
    }

    function runLottery(bytes32 randomNumber) internal {
        if (!lotteryState.isActive) {
            revert("Lottery not active");
        }

        if (lotteryLock) {
            revert("Lottery is running");
        }

        lotteryLock = true;

        uint256 fee = entropy.getFee(entropyProvider);

        if (address(this).balance < fee) {
            revert("Pyth fee must be provided to the contract");
        }

        entropy.requestWithCallback{value: fee}(entropyProvider, randomNumber);
    }

    function drawWinner(bytes32 randomNumber) internal {
        if (userPoolTotal >= lotteryState.lpPool) {
            // Jackpot is fully funded by users, so winner gets the user pool and LP's get the LP pool
            uint256 winningTicket = getWinningTicket(randomNumber, totalTicketCountBps);
            lastWinnerAddress = findWinnerFromUsers(winningTicket);

            uint256 winAmount = userPoolTotal;
            User storage winner = usersInfo[lastWinnerAddress];
            winner.winningsClaimable += winAmount;

            returnLpPoolBackToLps();

            // TODO: emit event
        } else {
            // Jackpot is not fully funded by users, i.e. partially funded by LP's
            uint256 winningTicket = getWinningTicket(randomNumber, (lotteryState.lpPool * 10000) / TICKET_PRICE);

            if (winningTicket <= totalTicketCountBps) {
                lastWinnerAddress = findWinnerFromUsers(winningTicket);

                uint256 winAmount = lotteryState.lpPool;
                User storage winner = usersInfo[lastWinnerAddress];
                winner.winningsClaimable += winAmount;

                // TODO: distributeUserPoolToLps();
                // TODO: returnLpPoolBackToLps();
                returnLpPoolBackToLps();

                // TODO: emit event
            }
        }

        // Reset ticket purchases and lottery variables for the next round
        clearUserTicketPurchases();
        userPoolTotal = 0;
        lpPoolTotal = 0;
        totalTicketCountBps = 0;
        // Reset fee accumulators, LP fee total reset in its own function
        lotteryState.lastDrawBlock = block.number;
        lotteryState.lpPool = 0;

        // Stake the LP's
        stakeLps();
    }


    function stakeLps() private {
        for (uint256 i = 0; i < activeLpAddresses.length; i++) {
            address lpAddress = activeLpAddresses[i];
            LP storage lp = lpsInfo[lpAddress];
            if (lp.active) {
                // lp.principal is always dividable by 100
                lp.stake = (lp.principal * LP_RISK_PERCENTAGE) / 100;
                // lp.stake is always non-negative
                lpPoolTotal += lp.stake;
                lp.principal -= lp.stake;
            }
        }
    }

    function clearUserTicketPurchases() internal {
        for (uint256 i = 0; i < activeUserAddresses.length; i++) {
            address userAddress = activeUserAddresses[i];
            usersInfo[userAddress].ticketsPurchasedTotalBps = 0;
            usersInfo[userAddress].active = false;
        }
        // After resetting usersInfo, reset the activeUserAddresses array
        delete activeUserAddresses;
    }

    function returnLpPoolBackToLps() private {
        for (uint256 i = 0; i < activeLpAddresses.length; i++) {
            address lpAddress = activeLpAddresses[i];
            LP storage lp = lpsInfo[lpAddress];
            // Add each LP's stake back to their principal
            if (lp.active) {
                lp.principal = lp.stake + lp.principal;
                lp.stake = 0;
            }
        }
    }

    function findWinnerFromUsers(uint256 winningTicket) private view returns (address) {
        uint256 cumulativeTicketsBps = 0;
        for (uint256 i = 0; i < activeUserAddresses.length; i++) {
            address userAddress = activeUserAddresses[i];
            User memory user = usersInfo[userAddress];
            cumulativeTicketsBps += user.ticketsPurchasedTotalBps;
            if (winningTicket <= cumulativeTicketsBps) {
                return userAddress;
            }
        }
        // No winner found, this should never happen
        return address(0);
    }

    function getWinningTicket(bytes32 rawRandomNumber, uint256 max) private pure returns (uint256) {
        return (uint256(rawRandomNumber) % max) + 1;
    }

    function getEntropy() internal view override returns (address) {
        return address(entropy);
    }

    function entropyCallback(uint64 sequenceNumber, address, bytes32 randomNumber) internal override {
        emit EntropyResult(sequenceNumber, randomNumber);
        if (entropyCallbackLock) {
            revert("Entropy callback locked");
        }
        if (!lotteryLock) {
            revert("Lottery is not locked");
        }

        entropyCallbackLock = true;
        drawWinner(randomNumber);

        // release both locks
        lotteryLock = false;
        entropyCallbackLock = false;
    }

    function getLotteryFee() public view returns (uint256 fee) {
        fee = entropy.getFee(entropyProvider);
    }
}
