// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test, console2} from "forge-std/Test.sol";
import {Baseloop} from "../../src/Baseloop.sol";
import {IERC20} from "forge-std/interfaces/IERC20.sol";
import {ICometMinimal} from "../../src/interfaces/ICometMinimal.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";

contract FuzzBaseloopTest is Test {
    using FixedPointMathLib for uint256;

    Baseloop public baseloop;
    IERC20 cbETH;
    IERC20 weth;
    ICometMinimal compound;

    address alice = makeAddr("alice");

    uint256 cbETHPrice = 1.047e18;

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
    }

    function test_fuzz_ETH(uint256 amount, uint256 leverage, uint256 ltv) public {
        amount = bound(amount, 0.01 ether, 4 ether);
        ltv = bound(ltv, 0.1e18, 0.88e18);
        leverage = bound(leverage, 1e18, uint256(1e18).divWadDown(1e18 - ltv + 0.01e18));

        deal(alice, amount);
        vm.startPrank(alice);
        compound.allow(address(baseloop), true);

        baseloop.openWithETH{value: amount}(leverage, ltv, cbETHPrice);
        vm.stopPrank();

        uint256 expectedBorrow = amount.mulWadDown(leverage).mulWadDown(ltv);
        assertApproxEqRel(compound.borrowBalanceOf(alice), expectedBorrow, 0.999e18);
        assertApproxEqRel(
            compound.collateralBalanceOf(alice, address(cbETH)),
            amount.mulWadDown(leverage).divWadDown(cbETHPrice),
            0.999e18
        );

        // -- Fast forward -- //
        skip(10 * 60 * 60 * 24); // 10 days

        // -- Leverage Down -- //
        assertEq(cbETH.balanceOf(alice), 0);
        vm.prank(alice);
        baseloop.close();

        // no borrows or collateral left on Compound
        assertEq(compound.borrowBalanceOf(alice), 0);
        assertEq(compound.collateralBalanceOf(alice, address(cbETH)), 0);

        // alice gets back the ~initial cbETH
        assertApproxEqRel(cbETH.balanceOf(alice), amount.divWadDown(cbETHPrice), 0.99e18);
    }

    function test_fuzz_CBWETH(uint256 amount, uint256 leverage, uint256 ltv) public {
        amount = bound(amount, 0.01 ether, 4 ether);
        ltv = bound(ltv, 0.1e18, 0.88e18);
        leverage = bound(leverage, 1e18, uint256(1e18).divWadDown(1e18 - ltv + 0.01e18));

        deal(address(cbETH), alice, amount);
        vm.startPrank(alice);
        compound.allow(address(baseloop), true);

        cbETH.approve(address(baseloop), amount);

        // obtaining 3x leverage on 1 cbETH, with 80% LTV
        baseloop.openWithCBETH(amount, leverage, ltv, cbETHPrice);
        vm.stopPrank();

        uint256 expectedBorrow = amount.mulWadDown(leverage).mulWadDown(ltv);
        assertApproxEqRel(compound.borrowBalanceOf(alice), expectedBorrow, 0.999e18);
        assertApproxEqRel(
            compound.collateralBalanceOf(alice, address(cbETH)),
            amount.mulWadDown(leverage).divWadDown(cbETHPrice),
            0.999e18
        );

        // -- Fast forward -- //
        skip(10 * 60 * 60 * 24); // 10 days

        // -- Leverage Down -- //
        assertEq(cbETH.balanceOf(alice), 0);
        vm.prank(alice);
        baseloop.close();

        // no borrows or collateral left on Compound
        assertEq(compound.borrowBalanceOf(alice), 0);
        assertEq(compound.collateralBalanceOf(alice, address(cbETH)), 0);

        // alice gets back the ~initial cbETH
        assertApproxEqRel(cbETH.balanceOf(alice), amount.divWadDown(cbETHPrice), 0.99e18);
    }
}
