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

contract Counter is IFlashLoanSimpleReceiver, Test {
    using FixedPointMathLib for uint256;

    IPool constant aave = IPool(0xA238Dd80C259a72e81d7e4664a9801593F98d1c5);
    ICometMinimal constant compound = ICometMinimal(0x46e6b214b524310239732D51387075E0e70970bf);
    IV3SwapRouter constant router = IV3SwapRouter(0x2626664c2603336E57B271c5C0b26F421741e481);

    IERC20 public cbETH = IERC20(0x2Ae3F1Ec7F1F5012CFEab0185bfc7aa3cf0DEc22);
    WETH public weth = WETH(payable(0x4200000000000000000000000000000000000006));

    constructor() {
        maxApprove();
    }

    function upETH(uint256 leverage, uint256 collateralFactor, uint256 cbETHPrice) external payable {
        weth.deposit{value: msg.value}();
        up(msg.value, leverage, collateralFactor, cbETHPrice);
    }

    function up(uint256 wethAmount, uint256 leverage, uint256 collateralFactor, uint256 cbETHPrice) public {
        // target ETH exposure
        uint256 wethAmountTotal = wethAmount.mulWadDown(leverage);

        // target ETH exposure, in the form of cbETH tokens
        uint256 cbETHAmount = wethAmountTotal.divWadDown(cbETHPrice);

        // how much borrow according to a collateral factor / LTV
        uint256 borrowAmount = wethAmountTotal.mulWadDown(collateralFactor);

        bytes memory data = abi.encodePacked(borrowAmount);
        aave.flashLoanSimple(address(this), address(cbETH), cbETHAmount, data, 0);
    }

    function executeOperation(address asset, uint256 amount, uint256 premium, address initiator, bytes calldata params)
        external
        override
        returns (bool)
    {
        require(initiator == address(this), "Counter: initiator not self");
        require(asset == address(cbETH) || asset == address(weth), "Counter: unknown asset");

        // flash borrowed cbETH: leveraging up
        if (asset == address(cbETH)) {
            // collateralize on compound
            compound.supply(address(cbETH), amount);

            // borrow eth from compound
            compound.withdraw(address(weth), abi.decode(params, (uint256)));

            // swap WETH to cbETH to repay flashloan
            uint256 repayAmount;
            unchecked {
                repayAmount = amount + premium;
            }
            router.exactOutputSingle(
                IV3SwapRouter.ExactOutputSingleParams({
                    tokenIn: address(weth),
                    tokenOut: address(cbETH),
                    fee: 500,
                    recipient: address(this),
                    amountOut: amount + premium,
                    amountInMaximum: type(uint256).max, // TODO: set max slippage
                    sqrtPriceLimitX96: 0
                })
            );
        } else { // flash borrow WETH: deleveraging
                // repay on compound
                // withdraw cbETH
                // swap cbETH to WETH
                // repay flashloan
        }
        return true;
    }

    function ADDRESSES_PROVIDER() external view override returns (IPoolAddressesProvider) {
        return aave.ADDRESSES_PROVIDER();
    }

    function POOL() external pure override returns (IPool) {
        return aave;
    }

    function maxApprove() public {
        cbETH.approve(address(aave), type(uint256).max);
        weth.approve(address(aave), type(uint256).max);

        cbETH.approve(address(compound), type(uint256).max);

        weth.approve(address(router), type(uint256).max);
    }
}
