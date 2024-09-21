// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "forge-std/src/console.sol";
import "forge-std/src/Script.sol";
import "../src/LotteryManager.sol";
import "../src/Lottery.sol";

contract Deployer is Script{
    uint256 immutable BASE_SEPOLIA_CHAIN_ID = 84532;

    function run() external {
        uint256 deployerPrivKey = vm.envUint("KEY");

        vm.startBroadcast(deployerPrivKey);

        LotteryManager manager = new LotteryManager(0xf242cE588b030d0895C51C0730F2368680f80644,0xA2f16f0BB5dEA7c9A6675Ec88193471dEe805e6e,0xc130b81bf6DCC5b53250Ab61c9111BDa24310747);

        address lottery = manager.createLottery("Lottery", "L");

        console.log("Manager deployed to: ", address(manager));
        console.log("Lottery deployed to: ", lottery);
    }
}