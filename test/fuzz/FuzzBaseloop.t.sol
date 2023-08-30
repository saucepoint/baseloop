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

        vm.startPrank(alice);
        compound.allow(address(baseloop), true);
        cbETH.approve(address(baseloop), type(uint256).max);
        vm.stopPrank();

        vm.label(address(cbETH), "cbETH");
        vm.label(address(weth), "WETH");
        vm.label(address(compound), "Compound");
        vm.label(address(baseloop.router()), "SwapRouter");
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
        baseloop.adjustPosition{value: amount}(alice, targetAmount, targetCollateralFactor);

        assertApproxEqRel(compound.borrowBalanceOf(alice), targetAmount.mulWadDown(targetCollateralFactor), 0.9999e18);
        assertApproxEqRel(
            compound.collateralBalanceOf(alice, address(cbETH)), targetAmount.divWadDown(uint256(cbETHPrice)), 0.9999e18
        );
    }

    function test_fuzz_adjustPositionClose(uint256 amount, uint256 targetAmount, uint256 targetCollateralFactor)
        public
    {
        amount = bound(amount, 0.01 ether, 10 ether);
        targetCollateralFactor = bound(targetCollateralFactor, 0.1e18, 0.89e18);
        uint256 MAX_LEVERAGE = uint256(1e18).divWadDown(1e18 - targetCollateralFactor + 0.01e18);
        targetAmount = bound(targetAmount, amount.mulWadDown(MIN_LEVERAGE), amount.mulWadDown(MAX_LEVERAGE));

        // ---------------- //
        deal(alice, amount);
        vm.prank(alice);
        baseloop.adjustPosition{value: amount}(alice, targetAmount, targetCollateralFactor);

        assertApproxEqRel(compound.borrowBalanceOf(alice), targetAmount.mulWadDown(targetCollateralFactor), 0.9999e18);
        assertApproxEqRel(
            compound.collateralBalanceOf(alice, address(cbETH)), targetAmount.divWadDown(uint256(cbETHPrice)), 0.9999e18
        );

        uint256 repayment = compound.borrowBalanceOf(alice) / 5;
        deal(alice, repayment);
        vm.prank(alice);
        baseloop.close{value: repayment}();
        // no borrows or collateral left on Compound
        assertEq(compound.borrowBalanceOf(alice), 0);
        assertEq(compound.collateralBalanceOf(alice, address(cbETH)), 0);
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
        baseloop.adjustPosition{value: amount}(alice, targetAmount, targetCollateralFactor);

        assertApproxEqRel(compound.borrowBalanceOf(alice), targetAmount.mulWadDown(targetCollateralFactor), 0.9999e18);
        assertApproxEqRel(
            compound.collateralBalanceOf(alice, address(cbETH)), targetAmount.divWadDown(uint256(cbETHPrice)), 0.9999e18
        );

        // ---------------- //
        amount = baseloop.calcAdditionalETH(alice, newTarget, newFactor);
        deal(alice, amount);
        vm.prank(alice);
        baseloop.adjustPosition{value: amount}(alice, newTarget, newFactor);

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
        baseloop.adjustPosition{value: amount}(alice, targetAmount, targetCollateralFactor);

        assertApproxEqRel(compound.borrowBalanceOf(alice), targetAmount.mulWadDown(targetCollateralFactor), 0.9999e18);
        assertApproxEqRel(
            compound.collateralBalanceOf(alice, address(cbETH)), targetAmount.divWadDown(uint256(cbETHPrice)), 0.9999e18
        );

        // ---------------- //
        amount = baseloop.calcAdditionalETH(alice, newTarget, newFactor);
        deal(alice, amount);
        vm.prank(alice);
        baseloop.adjustPosition{value: amount}(alice, newTarget, newFactor);

        assertApproxEqRel(compound.borrowBalanceOf(alice), newTarget.mulWadDown(newFactor), 0.9999e18);
        assertApproxEqRel(
            compound.collateralBalanceOf(alice, address(cbETH)), newTarget.divWadDown(uint256(cbETHPrice)), 0.9999e18
        );
    }
}
