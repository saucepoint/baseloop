// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test, console2} from "forge-std/Test.sol";
import {Counter} from "../src/Counter.sol";
import {IERC20} from "forge-std/interfaces/IERC20.sol";

contract CounterTest is Test {
    Counter public counter;
    IERC20 cbETH;

    address alice = makeAddr("alice");

    function setUp() public {
        counter = new Counter();
        cbETH = IERC20(address(counter.cbETH()));
        deal(alice, 10 ether);
        deal(address(cbETH), address(counter), 1 wei); // dust
    }

    function test_up() public {
        vm.startPrank(alice);
        counter.upETH{value: 1 ether}(4e18, 0.8e18, 1.047e18);
        assertEq(cbETH.balanceOf(address(counter)), 1 wei);
    }
}
