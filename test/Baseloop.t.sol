// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test, console2} from "forge-std/Test.sol";
import {Baseloop} from "../src/Baseloop.sol";
import {IERC20} from "forge-std/interfaces/IERC20.sol";
import {ICometMinimal} from "../src/interfaces/ICometMinimal.sol";

contract BaseloopTest is Test {
    Baseloop public baseloop;
    IERC20 cbETH;
    IERC20 weth;
    ICometMinimal compound;

    address alice = makeAddr("alice");

    function setUp() public {
        baseloop = new Baseloop();
        cbETH = IERC20(address(baseloop.cbETH()));
        weth = IERC20(address(baseloop.weth()));
        compound = ICometMinimal(address(baseloop.compound()));

        vm.label(address(cbETH), "cbETH");
        vm.label(address(weth), "WETH");
        vm.label(address(compound), "Compound");
        vm.label(address(baseloop.aave()), "Aave");
        vm.label(address(baseloop.router()), "SwapRouter");
        deal(alice, 10 ether);
    }

    function test_openWithETH() public {
        vm.startPrank(alice);
        compound.allow(address(baseloop), true);

        // obtaining 4x leverage on 1 ETH, with 80% LTV
        baseloop.openWithETH{value: 1 ether}(4e18, 0.8e18, 1.047e18);
        vm.stopPrank();

        // 80% of 4 ETH = borrowed balance
        assertEq(compound.borrowBalanceOf(alice), 3.2e18);
    }

    function test_close() public {
        // -- Leverage Up -- //
        vm.startPrank(alice);
        compound.allow(address(baseloop), true);
        // obtaining 4x leverage on 1 ETH, with 80% LTV
        baseloop.openWithETH{value: 1 ether}(4e18, 0.8e18, 1.047e18);
        vm.stopPrank();
        // 80% of 4 ETH = borrowed balance
        assertEq(compound.borrowBalanceOf(alice), 3.2e18);
        // ----------------- //

        skip(10 * 60 * 60 * 24); // 10 days
        assertEq(compound.borrowBalanceOf(alice) > 3.2e18, true);

        // -- Leverage Down -- //
        assertEq(cbETH.balanceOf(alice), 0);
        uint256 wethBalBefore = weth.balanceOf(alice);
        vm.prank(alice);
        baseloop.close();

        // no borrows or collateral left on Compound
        assertEq(compound.borrowBalanceOf(alice), 0);
        assertEq(compound.collateralBalanceOf(alice, address(cbETH)), 0);

        // alice initially put in 1 ETH, so should have at least ~1 cbETH
        assertEq(cbETH.balanceOf(alice) > 0.5e18, true);
        assertEq(weth.balanceOf(alice), wethBalBefore);
    }
}
