// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test, console2} from "forge-std/Test.sol";
import {Counter} from "../src/Counter.sol";
import {IERC20} from "forge-std/interfaces/IERC20.sol";

contract CounterTest is Test {
    Counter public counter;

    function setUp() public {
        counter = new Counter();
        deal(address(counter.cbETH()), address(counter), 10 ether);
    }

    function test_up() public {
        counter.up();
    }
}
