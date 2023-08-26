// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test, console2} from "forge-std/Test.sol";
import {Counter} from "../src/Counter.sol";
import {IERC20} from "forge-std/interfaces/IERC20.sol";
import {ICometMinimal} from "../src/interfaces/ICometMinimal.sol";

contract CounterTest is Test {
    Counter public counter;
    IERC20 cbETH;
    IERC20 weth;
    ICometMinimal compound;

    address alice = makeAddr("alice");

    function setUp() public {
        counter = new Counter();
        cbETH = IERC20(address(counter.cbETH()));
        weth = IERC20(address(counter.weth()));
        compound = ICometMinimal(address(counter.compound()));

        vm.label(address(cbETH), "cbETH");
        vm.label(address(weth), "WETH");
        vm.label(address(compound), "Compound");
        vm.label(address(counter.aave()), "Aave");
        vm.label(address(counter.router()), "SwapRouter");
        deal(alice, 10 ether);
    }

    function test_upAllow() public {
        vm.startPrank(alice);
        compound.allow(address(counter), true);

        // obtaining 4x leverage on 1 ETH, with 80% LTV
        counter.upETH{value: 1 ether}(4e18, 0.8e18, 1.047e18);
        vm.stopPrank();

        // 80% of 4 ETH = borrowed balance
        assertEq(compound.borrowBalanceOf(alice), 3.2e18);
    }
}
