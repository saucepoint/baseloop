// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.13;

import {Script, console2} from "forge-std/Script.sol";

contract BaseloopScript is Script {
    function setUp() public {}

    function run() public {
        vm.broadcast();
    }
}
