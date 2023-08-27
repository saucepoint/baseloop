// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.20;

import {IPool} from "aave-v3-core/contracts/interfaces/IPool.sol";
import {IFlashLoanSimpleReceiver} from "aave-v3-core/contracts/flashloan/interfaces/IFlashLoanSimpleReceiver.sol";
import {IPoolAddressesProvider} from "aave-v3-core/contracts/interfaces/IPoolAddressesProvider.sol";
import {IV3SwapRouter} from "swap-router-contracts/interfaces/IV3SwapRouter.sol";
import {IERC20} from "forge-std/interfaces/IERC20.sol";
import {WETH} from "solmate/tokens/WETH.sol";
import {ICometMinimal} from "./interfaces/ICometMinimal.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";

contract Baseloop is IFlashLoanSimpleReceiver {
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
    /// @notice Open a leveraged position starting with native Ether. The Ether gets swapped into cbETH to be collateralized
    /// @param leverageMultiplier The amount of desired leverage relative to the provided ether. In WAD format (1e18 = 1x, 4e18 = 4x)
    /// @param collateralFactor The desired collateral factor (LTV) on compound. In WAD format (0.7e18 = 70% loan-to-collateral)
    /// @param cbETHPrice The current price of cbETH as reported by the Compound oracle. Units are ETH/cbETH, in WAD format (1.04e18 = 1.04 ETH per each cbETH token)
    function openWithETH(uint256 leverageMultiplier, uint256 collateralFactor, uint256 cbETHPrice) external payable {
        weth.deposit{value: msg.value}();
        openWithWETH(msg.value, leverageMultiplier, collateralFactor, cbETHPrice, false);
    }

    /// @notice Open a leveraged position starting with WETH. The WETH gets swapped into cbETH to be collateralized
    /// @param wethAmount The amount of WETH to initially provide as collateral
    /// @param leverageMultiplier The amount of desired leverage relative to the provided ether. In WAD format (1e18 = 1x, 4e18 = 4x)
    /// @param collateralFactor The desired collateral factor (LTV) on compound. In WAD format (0.7e18 = 70% loan-to-collateral)
    /// @param cbETHPrice The current price of cbETH as reported by the Compound oracle. Units are ETH/cbETH, in WAD format (1.04e18 = 1.04 ETH per each cbETH token)
    /// @param transferWETH Provide as TRUE if WETH should be transferred from caller to Baseloop
    function openWithWETH(
        uint256 wethAmount,
        uint256 leverageMultiplier,
        uint256 collateralFactor,
        uint256 cbETHPrice,
        bool transferWETH
    ) public {
        if (transferWETH) {
            weth.transferFrom(msg.sender, address(this), wethAmount);
        }
        // target ETH exposure
        uint256 wethAmountTotal = wethAmount.mulWadDown(leverageMultiplier);

        // target ETH exposure, in the form of cbETH tokens
        uint256 cbETHAmount = wethAmountTotal.divWadDown(cbETHPrice);

        // how much borrow according to a collateral factor / LTV
        uint256 amountToBorrow = wethAmountTotal.mulWadDown(collateralFactor);

        aave.flashLoanSimple(
            address(this),
            address(cbETH),
            cbETHAmount,
            abi.encode(FlashCallbackData(uint176(cbETHAmount), uint176(amountToBorrow), msg.sender)),
            0
        );

        // return excess, keeping 1 wei for gas optimization
        uint256 excess = weth.balanceOf(address(this));
        unchecked {
            if (0 != excess) weth.transfer(msg.sender, excess - 1);
        }
    }

    /// @notice Open a leveraged position starting with cbETH. The cbETH + flashloan get provided as collateral to compound
    /// @param cbETHAmount The amount of cbETH to initially provide as collateral
    /// @param leverageMultiplier The amount of desired leverage relative to the provided cbETH. In WAD format (1e18 = 1x, 4e18 = 4x)
    /// @param collateralFactor The desired collateral factor (LTV) on compound. In WAD format (0.7e18 = 70% loan-to-collateral)
    /// @param cbETHPrice The current price of cbETH as reported by the Compound oracle. Units are ETH/cbETH, in WAD format (1.04e18 = 1.04 ETH per each cbETH token)
    function openWithCBETH(
        uint256 cbETHAmount,
        uint256 leverageMultiplier,
        uint256 collateralFactor,
        uint256 cbETHPrice
    ) public {
        cbETH.transferFrom(msg.sender, address(this), cbETHAmount);

        // target cbETH exposure
        uint256 amountTotal = cbETHAmount.mulWadDown(leverageMultiplier);
        uint256 amountToFlash;
        unchecked {
            amountToFlash = amountTotal - cbETHAmount;
        }

        // how much ETH borrow according to a collateral factor / LTV
        uint256 amountToBorrow = amountTotal.mulWadDown(cbETHPrice).mulWadDown(collateralFactor);

        aave.flashLoanSimple(
            address(this),
            address(cbETH),
            amountToFlash,
            abi.encode(FlashCallbackData(uint176(amountTotal), uint176(amountToBorrow), msg.sender)),
            0
        );

        // return excess, keeping 1 wei for gas optimization
        uint256 excess = weth.balanceOf(address(this));
        unchecked {
            if (0 != excess) weth.transfer(msg.sender, excess - 1);
        }
    }

    // -- Leverage Down (User Facing) -- //

    /// @notice Fully close a leveraged position
    function close() external {
        uint256 totalCompoundRepay = compound.borrowBalanceOf(msg.sender);
        aave.flashLoanSimple(
            address(this),
            address(weth),
            totalCompoundRepay,
            abi.encode(FlashCallbackData(uint176(totalCompoundRepay), 0, msg.sender)),
            0
        );

        // return excess, keeping 1 wei for gas optimization
        unchecked {
            cbETH.transfer(msg.sender, cbETH.balanceOf(address(this)) - 1);
        }
    }

    /// @notice Flashloan handler. Only callable by Aave
    /// @param asset The asset being flashborrowed
    /// @param amount The amount being flashborrowed
    /// @param premium The fee being charged by Aave
    /// @param initiator The initiator of the flashloan
    /// @param params Arbitrary data from the initiator
    function executeOperation(address asset, uint256 amount, uint256 premium, address initiator, bytes calldata params)
        external
        override
        returns (bool)
    {
        require(msg.sender == address(aave), "only aave");
        require(initiator == address(this), "initiator not self");
        require(asset == address(cbETH) || asset == address(weth), "unknown asset");

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
