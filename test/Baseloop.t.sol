// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.20;

import {Test, console2} from "forge-std/Test.sol";
import {Baseloop} from "../src/Baseloop.sol";
import {IERC20} from "forge-std/interfaces/IERC20.sol";
import {ICometMinimal} from "../src/interfaces/ICometMinimal.sol";
import {IAggregatorMinimal} from "../src/interfaces/IAggregatorMinimal.sol";
import {IV3SwapRouter} from "swap-router-contracts/interfaces/IV3SwapRouter.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";

contract BaseloopTest is Test {
    using FixedPointMathLib for uint256;

    Baseloop public baseloop;
    IERC20 cbETH;
    IERC20 weth;
    ICometMinimal compound;
    IAggregatorMinimal priceFeed;
    IV3SwapRouter router;

    address alice = makeAddr("alice");
    uint256 cbETHPrice;

    function setUp() public {
        baseloop = new Baseloop();
        cbETH = IERC20(address(baseloop.cbETH()));
        weth = IERC20(address(baseloop.weth()));
        compound = ICometMinimal(address(baseloop.compound()));
        priceFeed = IAggregatorMinimal(address(baseloop.priceFeed()));
        router = IV3SwapRouter(address(baseloop.router()));

        cbETHPrice = uint256(priceFeed.latestAnswer());

        vm.startPrank(alice);
        compound.allow(address(baseloop), true);
        cbETH.approve(address(baseloop), type(uint256).max);
        vm.stopPrank();

        vm.label(address(cbETH), "cbETH");
        vm.label(address(weth), "WETH");
        vm.label(address(compound), "Compound");
        vm.label(address(priceFeed), "PriceFeed");
        vm.label(address(baseloop.router()), "SwapRouter");
    }

    function test_adjustPosition() public {
        uint256 amount = 1 ether;
        uint256 targetAmount = 6 ether;
        uint256 targetCollateralFactor = 0.85e18;

        deal(alice, amount);
        vm.startPrank(alice);
        // 6 ETH exposure (on 1 eth deposit, 6x) at 85% LTV
        baseloop.adjustPosition{value: amount}(targetAmount, targetCollateralFactor);
        vm.stopPrank();

        assertApproxEqRel(compound.borrowBalanceOf(alice), targetAmount.mulWadDown(targetCollateralFactor), 0.9999e18);
        assertApproxEqRel(
            compound.collateralBalanceOf(alice, address(cbETH)),
            targetAmount.divWadDown(uint256(priceFeed.latestAnswer())),
            0.9999e18
        );

        assertEq(cbETH.balanceOf(alice), 0);
        assertEq(weth.balanceOf(alice), 0);
        assertEq(address(alice).balance > 0, true);
    }

    // Given an existing position, readjust it for MORE leverage
    function test_adjustPositionUp() public {
        uint256 amount = 1 ether;
        uint256 targetAmount = 6 ether;
        uint256 targetCollateralFactor = 0.85e18;

        deal(alice, amount);
        vm.startPrank(alice);
        compound.allow(address(baseloop), true);

        // 6 ETH exposure (on 1 eth deposit, 6x) at 85% LTV
        baseloop.adjustPosition{value: amount}(targetAmount, targetCollateralFactor);
        vm.stopPrank();

        // -- Readjust Position -- //
        amount = 0.2 ether; // small amount to ensure swap
        uint256 newTargetAmount = 8 ether;
        uint256 newTargetCollateralFactor = 0.88e18;
        deal(alice, amount);
        vm.prank(alice);
        baseloop.adjustPosition{value: amount}(newTargetAmount, newTargetCollateralFactor);

        assertApproxEqRel(
            compound.borrowBalanceOf(alice), newTargetAmount.mulWadDown(newTargetCollateralFactor), 0.9999e18
        );
        assertApproxEqRel(
            compound.collateralBalanceOf(alice, address(cbETH)),
            newTargetAmount.divWadDown(uint256(priceFeed.latestAnswer())),
            0.9999e18
        );
    }

    // Given an existing position, readjust it for LESS leverage
    function test_adjustPositionDown() public {
        uint256 amount = 1 ether;
        uint256 targetAmount = 6 ether;
        uint256 targetCollateralFactor = 0.85e18;

        deal(alice, amount);
        vm.startPrank(alice);
        compound.allow(address(baseloop), true);

        // 6 ETH exposure (on 1 eth deposit, 6x) at 85% LTV
        baseloop.adjustPosition{value: amount}(targetAmount, targetCollateralFactor);
        vm.stopPrank();

        // -- Readjust Position -- //
        // amount = 0.2 ether; // small amount to ensure swap
        uint256 newTargetAmount = 4 ether;
        uint256 newTargetCollateralFactor = 0.88e18;
        deal(alice, amount);
        vm.prank(alice);
        baseloop.adjustPosition{value: amount}(newTargetAmount, newTargetCollateralFactor);

        assertApproxEqRel(
            compound.borrowBalanceOf(alice), newTargetAmount.mulWadDown(newTargetCollateralFactor), 0.9999e18
        );
        assertApproxEqRel(
            compound.collateralBalanceOf(alice, address(cbETH)),
            newTargetAmount.divWadDown(uint256(priceFeed.latestAnswer())),
            0.9999e18
        );
    }

    // Given an existing position, readjust it for MORE leverage using cbETH token
    function test_adjustPositionUpCBETH() public {
        uint256 amount = 1 ether;
        uint256 targetAmount = 6 ether;
        uint256 targetCollateralFactor = 0.85e18;

        deal(address(cbETH), alice, amount);
        vm.prank(alice);
        // 6 ETH exposure (on 1 eth deposit, 6x) at 85% LTV
        baseloop.adjustPositionCBETH(amount, targetAmount, targetCollateralFactor);

        assertApproxEqRel(compound.borrowBalanceOf(alice), targetAmount.mulWadDown(targetCollateralFactor), 0.9999e18);
        assertApproxEqRel(
            compound.collateralBalanceOf(alice, address(cbETH)),
            targetAmount.divWadDown(uint256(priceFeed.latestAnswer())),
            0.9999e18
        );

        // -- Readjust Position -- //
        amount = 1 ether;
        uint256 newTargetAmount = 8 ether;
        uint256 newTargetCollateralFactor = 0.88e18;
        deal(address(cbETH), alice, amount);
        vm.prank(alice);
        baseloop.adjustPositionCBETH(amount, newTargetAmount, newTargetCollateralFactor);

        assertApproxEqRel(
            compound.borrowBalanceOf(alice), newTargetAmount.mulWadDown(newTargetCollateralFactor), 0.9999e18
        );
        assertApproxEqRel(
            compound.collateralBalanceOf(alice, address(cbETH)),
            newTargetAmount.divWadDown(uint256(priceFeed.latestAnswer())),
            0.9999e18
        );
    }

    function test_close() public {
        // -- Leverage Up -- //
        uint256 amount = 1 ether;
        uint256 targetAmount = 4 ether;
        uint256 targetCollateralFactor = 0.8e18;

        deal(alice, amount);
        vm.startPrank(alice);
        // 6 ETH exposure (on 1 eth deposit, 6x) at 85% LTV
        baseloop.adjustPosition{value: amount}(targetAmount, targetCollateralFactor);
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
        assertApproxEqRel(weth.balanceOf(alice), wethBalBefore, 0.999e18);
    }

    // test the position can be closed by providing ETH in case of depeg
    function test_paidClose() public {
        // -- Leverage Up -- //
        // -- Leverage Up -- //
        uint256 amount = 1 ether;
        uint256 targetAmount = 4 ether;
        uint256 targetCollateralFactor = 0.8e18;

        deal(alice, amount);
        vm.startPrank(alice);
        // 6 ETH exposure (on 1 eth deposit, 6x) at 85% LTV
        baseloop.adjustPosition{value: amount}(targetAmount, targetCollateralFactor);
        vm.stopPrank();

        // 80% of 4 ETH = borrowed balance
        assertEq(compound.borrowBalanceOf(alice), 3.2e18);
        // ----------------- //

        // depeg cbETH
        uint256 cbethAmount = 200 ether;
        deal(address(cbETH), alice, cbethAmount);
        vm.startPrank(alice);
        cbETH.approve(address(router), cbethAmount);
        router.exactInputSingle(
            IV3SwapRouter.ExactInputSingleParams({
                tokenIn: address(cbETH),
                tokenOut: address(weth),
                fee: 500,
                recipient: address(this),
                amountIn: cbethAmount,
                amountOutMinimum: 0, // TODO: set max slippage
                sqrtPriceLimitX96: 0
            })
        );
        vm.stopPrank();

        // -- Leverage Down -- //
        assertEq(cbETH.balanceOf(alice), 0);
        deal(alice, 3 ether);
        vm.prank(alice);
        baseloop.close{value: 3 ether}();

        // no borrows or collateral left on Compound
        assertEq(compound.borrowBalanceOf(alice), 0);
        assertEq(compound.collateralBalanceOf(alice, address(cbETH)), 0);
    }

    function test_donate() public {
        uint256 balanceBefore = address(baseloop.DEV_DONATE()).balance;
        deal(alice, 0.01 ether);
        vm.prank(alice);
        baseloop.developerDonate{value: 0.01 ether}();

        assertEq(address(baseloop.DEV_DONATE()).balance, balanceBefore + 0.01 ether);
    }
}
