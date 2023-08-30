// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.20;

import {Test, console2} from "forge-std/Test.sol";
import {Baseloop} from "../../src/Baseloop.sol";
import {IERC20} from "forge-std/interfaces/IERC20.sol";
import {ICometMinimal} from "../../src/interfaces/ICometMinimal.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import {IAggregatorMinimal} from "../../src/interfaces/IAggregatorMinimal.sol";

contract FuzzBaseloopTest is Test {
    using FixedPointMathLib for uint256;

    Baseloop public baseloop;
    IERC20 cbETH;
    IERC20 weth;
    ICometMinimal compound;
    IAggregatorMinimal priceFeed;

    address alice = makeAddr("alice");
    uint256 cbETHPrice;
    uint256 MIN_LEVERAGE = 1.01e18;

    function setUp() public {
        baseloop = new Baseloop();
        cbETH = IERC20(address(baseloop.cbETH()));
        weth = IERC20(address(baseloop.weth()));
        compound = ICometMinimal(address(baseloop.compound()));
        priceFeed = IAggregatorMinimal(address(baseloop.priceFeed()));

        cbETHPrice = uint256(priceFeed.latestAnswer());

        vm.prank(alice);
        compound.allow(address(baseloop), true);

        vm.label(address(cbETH), "cbETH");
        vm.label(address(weth), "WETH");
        vm.label(address(compound), "Compound");
        vm.label(address(baseloop.aave()), "Aave");
        vm.label(address(baseloop.router()), "SwapRouter");
    }

    function test_fuzz_ETH(uint256 amount, uint256 leverage, uint256 ltv) public {
        // currently Aave has ~20 ETH available for flashloan, so limit how much we intend to borrow
        amount = bound(amount, 0.01 ether, 3 ether);
        ltv = bound(ltv, 0.1e18, 0.85e18);
        leverage = bound(leverage, 1e18, uint256(1e18).divWadDown(1e18 - ltv + 0.01e18));

        deal(alice, amount);
        vm.startPrank(alice);

        baseloop.createPositionETH{value: amount}(leverage, ltv, cbETHPrice);
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
        // currently Aave has ~20 ETH available for flashloan, so limit how much we intend to borrow
        amount = bound(amount, 0.01 ether, 3 ether);
        ltv = bound(ltv, 0.1e18, 0.85e18);
        leverage = bound(leverage, MIN_LEVERAGE, uint256(1e18).divWadDown(1e18 - ltv + 0.01e18));

        deal(address(cbETH), alice, amount);
        vm.startPrank(alice);

        cbETH.approve(address(baseloop), amount);

        // obtaining 3x leverage on 1 cbETH, with 80% LTV
        baseloop.createPositionCBETH(amount, leverage, ltv, cbETHPrice);
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

    function test_fuzz_adjustPositionOpen(uint256 amount, uint256 targetAmount, uint256 targetCollateralFactor)
        public
    {
        amount = bound(amount, 0.01 ether, 3 ether);
        targetCollateralFactor = bound(targetCollateralFactor, 0.1e18, 0.85e18);
        uint256 MAX_LEVERAGE = uint256(1e18).divWadDown(1e18 - targetCollateralFactor + 0.01e18);
        targetAmount = bound(targetAmount, amount.mulWadDown(MIN_LEVERAGE), amount.mulWadDown(MAX_LEVERAGE));

        // ---------------- //
        deal(alice, amount);
        vm.prank(alice);
        baseloop.adjustPosition{value: amount}(targetAmount, targetCollateralFactor);

        assertApproxEqRel(compound.borrowBalanceOf(alice), targetAmount.mulWadDown(targetCollateralFactor), 0.9999e18);
        assertApproxEqRel(
            compound.collateralBalanceOf(alice, address(cbETH)), targetAmount.divWadDown(uint256(cbETHPrice)), 0.9999e18
        );
    }

    function test_fuzz_adjustPositionUp(
        uint256 amount,
        uint256 targetAmount,
        uint256 targetCollateralFactor,
        uint256 newTarget,
        uint256 newFactor
    ) public {
        // Leverage Increase scenarios:
        // Keep collateral, increase factor = use UI to borrow more
        // Keep collateral, keep factor = no change
        // Increase collateral, keep factor
        // Increase collateral, increase factor
        vm.assume(amount < 3 ether);
        vm.assume(targetCollateralFactor < 0.85e18);
        vm.assume(newTarget >= targetAmount);
        vm.assume(newFactor >= targetCollateralFactor);

        // Initial position
        amount = bound(amount, 0.01 ether, 3 ether);
        targetCollateralFactor = bound(targetCollateralFactor, 0.1e18, 0.85e18);
        uint256 MAX_LEVERAGE = uint256(1e18).divWadDown(1e18 - targetCollateralFactor + 0.03e18);
        targetAmount = bound(targetAmount, amount.mulWadDown(MIN_LEVERAGE), amount.mulWadDown(MAX_LEVERAGE));

        // New position
        newFactor = bound(newFactor, targetCollateralFactor, 0.89e18);
        MAX_LEVERAGE = uint256(1e18).divWadDown(1e18 - newFactor + 0.01e18);
        newTarget = bound(newTarget, targetAmount.mulWadDown(MIN_LEVERAGE), amount.mulWadDown(MAX_LEVERAGE));

        // ---------------- //
        deal(alice, amount);
        vm.prank(alice);
        baseloop.adjustPosition{value: amount}(targetAmount, targetCollateralFactor);

        assertApproxEqRel(compound.borrowBalanceOf(alice), targetAmount.mulWadDown(targetCollateralFactor), 0.9999e18);
        assertApproxEqRel(
            compound.collateralBalanceOf(alice, address(cbETH)), targetAmount.divWadDown(uint256(cbETHPrice)), 0.9999e18
        );

        // ---------------- //
        int256 additionalETH = baseloop.calcAdditionalETH(alice, newTarget, newFactor);
        amount = additionalETH < 0 ? uint256(-additionalETH) : uint256(additionalETH);
        console2.log(amount);
        deal(alice, amount);
        vm.prank(alice);
        baseloop.adjustPosition{value: amount}(newTarget, newFactor);

        assertApproxEqRel(compound.borrowBalanceOf(alice), newTarget.mulWadDown(newFactor), 0.9999e18);
        assertApproxEqRel(
            compound.collateralBalanceOf(alice, address(cbETH)), newTarget.divWadDown(uint256(cbETHPrice)), 0.9999e18
        );
    }

    function test_fuzz_adjustPositionDown(
        uint256 amount,
        uint256 targetAmount,
        uint256 targetCollateralFactor,
        uint256 newTarget,
        uint256 newFactor
    ) public {
        // Leverage Decrease scenarios:
        // Keep collateral, decrease factor = use UI to repay
        // Keep collateral, keep factor = no change
        // Decrease collateral, keep factor
        // Decrease collateral, decrease factor
        vm.assume(amount < 3 ether);
        vm.assume(newTarget < targetAmount);
        vm.assume(newFactor <= targetCollateralFactor);

        // Initial position
        amount = bound(amount, 0.01 ether, 3 ether);
        targetCollateralFactor = bound(targetCollateralFactor, 0.1e18, 0.85e18);
        uint256 MAX_LEVERAGE = uint256(1e18).divWadDown(1e18 - targetCollateralFactor + 0.01e18);
        targetAmount = bound(targetAmount, amount.mulWadDown(1.05e18), amount.mulWadDown(MAX_LEVERAGE));

        // New position
        newFactor = bound(newFactor, 0.08e18, targetCollateralFactor);
        newTarget = bound(newTarget, amount.mulWadDown(MIN_LEVERAGE), targetAmount.mulWadDown(0.99e18));

        // ---------------- //
        deal(alice, amount);
        vm.prank(alice);
        baseloop.adjustPosition{value: amount}(targetAmount, targetCollateralFactor);

        assertApproxEqRel(compound.borrowBalanceOf(alice), targetAmount.mulWadDown(targetCollateralFactor), 0.9999e18);
        assertApproxEqRel(
            compound.collateralBalanceOf(alice, address(cbETH)), targetAmount.divWadDown(uint256(cbETHPrice)), 0.9999e18
        );

        // ---------------- //
        int256 additionalETH = baseloop.calcAdditionalETH(alice, newTarget, newFactor);
        amount = additionalETH < 0 ? uint256(-additionalETH) : uint256(additionalETH);
        deal(alice, amount);
        vm.prank(alice);
        baseloop.adjustPosition{value: amount}(newTarget, newFactor);

        assertApproxEqRel(compound.borrowBalanceOf(alice), newTarget.mulWadDown(newFactor), 0.9999e18);
        assertApproxEqRel(
            compound.collateralBalanceOf(alice, address(cbETH)), newTarget.divWadDown(uint256(cbETHPrice)), 0.9999e18
        );
    }
}
