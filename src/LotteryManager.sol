// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/* 
when we add liquidity, we also need to mint equivalent of the other token and deposit into the pool

when we remove liquidity, we also need to burn an equivalent of the other token
 */

import {IPoolManager} from "v4-periphery/base/hooks/BaseHook.sol";
import {PositionManager} from "v4-periphery/PositionManager.sol";
import "./Lottery.sol";
import "./LotteryToken.sol";
import {Actions} from "v4-periphery/libraries/Actions.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {PoolKey, Currency} from "@uniswap/v4-core/src/types/PoolKey.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract LotteryManager {
    using SafeERC20 for IERC20;

    IPoolManager poolManager;
    PositionManager positionManager;
    address usdc;

    struct LotteryInfo {
        address token;
        address lottery;
    }

    mapping(address => LotteryInfo) public lotteries;

    constructor(address _poolManager, address _positionManager, address _usdc) {
        poolManager = IPoolManager(_poolManager);
        positionManager = PositionManager(_positionManager);
        usdc= _usdc;
    }

    function createLottery(string calldata _name, string calldata _symbol) external returns (address) {
        LotteryToken lotteryToken = new LotteryToken(_name, _symbol);


        Lottery lottery = new Lottery(poolManager, usdc, address(lotteryToken));
        lotteries[address(lottery)] = LotteryInfo(address(lotteryToken), address(lottery));

/*         PoolKey memory pool = PoolKey({
            currency0: Currency.wrap(lotteryToken),
            currency1: Currency.wrap(usdc),
            fee: 0,
            tickSpacing: 60,
            hooks: IHooks(lottery.lottery)
        });

        poolManager.initialize(pool, Constants.SQRT_PRICE_1_1, bytes("")); */

        return address(lottery);
    }

    function addLiquidity(address _lottery, uint256 amount) external {
        LotteryInfo memory lottery = lotteries[_lottery];
        PoolKey memory poolKey = PoolKey({
            currency0: Currency.wrap(lottery.token),
            currency1: Currency.wrap(usdc),
            fee: 0,
            tickSpacing: 60,
            hooks: IHooks(lottery.lottery)
        });

        IERC20(usdc).safeTransferFrom(msg.sender, address(this), amount);
        LotteryToken(lottery.token).mint(address(this), amount);

        bytes memory actions = abi.encodePacked(Actions.MINT_POSITION, Actions.SETTLE_PAIR);
        bytes[] memory params = new bytes[](2);
        params[0] = abi.encode(
            poolKey, TickMath.MIN_TICK, TickMath.MAX_TICK, 1, amount, amount, address(this), abi.encode(msg.sender, address(this))
        );
        params[1] = abi.encode(lottery.token, usdc);

        uint256 deadline = block.timestamp + 60;

        positionManager.modifyLiquidities(abi.encode(actions, params), deadline);
    }

    function removeLiquidity(address user, uint256 amount) external {
        if (lotteries[user].lottery != user) {
            revert("Invalid caller");
        }

        LotteryToken(lotteries[user].token).burn(user, amount);
    }
}
