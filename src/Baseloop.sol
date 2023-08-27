// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import {IPool} from "aave-v3-core/contracts/interfaces/IPool.sol";
import {IFlashLoanSimpleReceiver} from "aave-v3-core/contracts/flashloan/interfaces/IFlashLoanSimpleReceiver.sol";
import {IPoolAddressesProvider} from "aave-v3-core/contracts/interfaces/IPoolAddressesProvider.sol";
import {IV3SwapRouter} from "swap-router-contracts/interfaces/IV3SwapRouter.sol";
import {IERC20} from "forge-std/interfaces/IERC20.sol";
import {WETH} from "solmate/tokens/WETH.sol";
import {ICometMinimal} from "./interfaces/ICometMinimal.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";

contract Baseloop is IFlashLoanSimpleReceiver, Test {
    using FixedPointMathLib for uint256;

    IPool public constant aave = IPool(0xA238Dd80C259a72e81d7e4664a9801593F98d1c5);
    ICometMinimal public constant compound = ICometMinimal(0x46e6b214b524310239732D51387075E0e70970bf);
    IV3SwapRouter public constant router = IV3SwapRouter(0x2626664c2603336E57B271c5C0b26F421741e481);

    IERC20 public constant cbETH = IERC20(0x2Ae3F1Ec7F1F5012CFEab0185bfc7aa3cf0DEc22);
    WETH public constant weth = WETH(payable(0x4200000000000000000000000000000000000006));

    // tightly pack with uint176, max of 9.57e34 ether or 9.57e52 wei
    struct FlashCallbackData {
        uint176 amountToSupply; // amount of cbETH to supply on compound
        uint176 amountToBorrow; // amount of ETH to borrow from compound
        address user;
    }

    constructor() {
        maxApprove();
    }

    // -- Leverage Up (User Facing) -- //
    function openWithETH(uint256 leverageMultiplier, uint256 collateralFactor, uint256 cbETHPrice) external payable {
        weth.deposit{value: msg.value}();
        openWithWETH(msg.value, leverageMultiplier, collateralFactor, cbETHPrice);
    }

    function openWithWETH(uint256 wethAmount, uint256 leverageMultiplier, uint256 collateralFactor, uint256 cbETHPrice)
        public
    {
        // target ETH exposure
        uint256 wethAmountTotal = wethAmount.mulWadDown(leverageMultiplier);

        // target ETH exposure, in the form of cbETH tokens
        uint256 cbETHAmount = wethAmountTotal.divWadDown(cbETHPrice);

        // how much borrow according to a collateral factor / LTV
        uint256 amountToBorrow = wethAmountTotal.mulWadDown(collateralFactor);

        bytes memory data = abi.encode(FlashCallbackData(uint176(cbETHAmount), uint176(amountToBorrow), msg.sender));
        aave.flashLoanSimple(address(this), address(cbETH), cbETHAmount, data, 0);

        // return excess, keeping 1 wei for gas optimization
        weth.transfer(msg.sender, weth.balanceOf(address(this)) - 1);
    }

    function openWithCBETH(
        uint256 cbETHAmount,
        uint256 leverageMultiplier,
        uint256 collateralFactor,
        uint256 cbETHPrice
    ) public {
        cbETH.transferFrom(msg.sender, address(this), cbETHAmount);

        // target cbETH exposure
        uint256 amountTotal = cbETHAmount.mulWadDown(leverageMultiplier);
        uint256 amountToFlash = amountTotal - cbETHAmount - 1;

        // how much ETH borrow according to a collateral factor / LTV
        uint256 amountToBorrow = amountTotal.mulWadDown(cbETHPrice).mulWadDown(collateralFactor);

        bytes memory data = abi.encode(FlashCallbackData(uint176(amountTotal), uint176(amountToBorrow), msg.sender));
        aave.flashLoanSimple(address(this), address(cbETH), amountToFlash, data, 0);
    }

    // -- Leverage Down (User Facing) -- //

    function close() external {
        uint256 totalCompoundRepay = compound.borrowBalanceOf(msg.sender);
        bytes memory data = abi.encode(FlashCallbackData(uint176(totalCompoundRepay), 0, msg.sender));
        aave.flashLoanSimple(address(this), address(weth), totalCompoundRepay, data, 0);

        // return excess, keeping 1 wei for gas optimization
        cbETH.transfer(msg.sender, cbETH.balanceOf(address(this)) - 1);
    }

    function replace() external {}

    function executeOperation(address asset, uint256 amount, uint256 premium, address initiator, bytes calldata params)
        external
        override
        returns (bool)
    {
        require(initiator == address(this), "Baseloop: initiator not self");
        require(asset == address(cbETH) || asset == address(weth), "Baseloop: unknown asset");

        FlashCallbackData memory data = abi.decode(params, (FlashCallbackData));

        unchecked {
            uint256 amountToRepay = amount + premium + 1;
            if (asset == address(cbETH)) {
                // flash borrowed cbETH: leveraging up
                leverage(data, amountToRepay);
            } else {
                // flash borrowed WETH: deleveraging
                deleverage(data, amountToRepay);
            }
        }
        return true;
    }

    // -- Internal Leverage Up/Down -- //

    function leverage(FlashCallbackData memory data, uint256 amountToRepay) internal {
        address user = data.user;
        // collateralize on compound
        compound.supplyTo(user, address(cbETH), data.amountToSupply);

        // borrow eth from compound
        compound.withdrawFrom(user, address(this), address(weth), data.amountToBorrow);

        // swap WETH to cbETH to repay flashloan
        router.exactOutputSingle(
            IV3SwapRouter.ExactOutputSingleParams({
                tokenIn: address(weth),
                tokenOut: address(cbETH),
                fee: 500,
                recipient: address(this),
                amountOut: amountToRepay,
                amountInMaximum: type(uint256).max, // TODO: set max slippage
                sqrtPriceLimitX96: 0
            })
        );
    }

    function deleverage(FlashCallbackData memory data, uint256 amountToRepay) internal {
        address user = data.user;

        // repay on compound
        compound.supplyTo(user, address(weth), data.amountToSupply);

        // withdraw cbETH
        compound.withdrawFrom(user, address(this), address(cbETH), compound.collateralBalanceOf(user, address(cbETH)));

        // swap cbETH to WETH
        router.exactOutputSingle(
            IV3SwapRouter.ExactOutputSingleParams({
                tokenIn: address(cbETH),
                tokenOut: address(weth),
                fee: 500,
                recipient: address(this),
                amountOut: amountToRepay,
                amountInMaximum: type(uint256).max, // TODO: set max slippage
                sqrtPriceLimitX96: 0
            })
        );
    }

    // -- Flashloan Misc -- //
    function ADDRESSES_PROVIDER() external view override returns (IPoolAddressesProvider) {
        return aave.ADDRESSES_PROVIDER();
    }

    function POOL() external pure override returns (IPool) {
        return aave;
    }

    // -- Utils & Helpers -- //
    function maxApprove() public {
        cbETH.approve(address(aave), type(uint256).max);
        weth.approve(address(aave), type(uint256).max);

        cbETH.approve(address(compound), type(uint256).max);
        weth.approve(address(compound), type(uint256).max);

        cbETH.approve(address(router), type(uint256).max);
        weth.approve(address(router), type(uint256).max);
    }

    function rescueERC20(address token) external {
        IERC20(token).transfer(msg.sender, IERC20(token).balanceOf(address(this)));
    }

    function rescueETH() external {
        payable(msg.sender).transfer(address(this).balance);
    }
}
