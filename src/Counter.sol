// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.20;

import {IPool} from "aave-v3-core/contracts/interfaces/IPool.sol";
import {IFlashLoanSimpleReceiver} from "aave-v3-core/contracts/flashloan/interfaces/IFlashLoanSimpleReceiver.sol";
import {IPoolAddressesProvider} from "aave-v3-core/contracts/interfaces/IPoolAddressesProvider.sol";
import {ISwapRouter} from "v3-periphery/interfaces/ISwapRouter.sol";
import {IERC20} from "forge-std/interfaces/IERC20.sol";
import {WETH} from "solmate/tokens/WETH.sol";
import {ICometMinimal} from "./interfaces/ICometMinimal.sol";

contract Counter is IFlashLoanSimpleReceiver {
    IPool constant aave = IPool(0xA238Dd80C259a72e81d7e4664a9801593F98d1c5);
    ICometMinimal constant compound = ICometMinimal(0x46e6b214b524310239732D51387075E0e70970bf);
    ISwapRouter constant router = ISwapRouter(0x2626664c2603336E57B271c5C0b26F421741e481);

    IERC20 public cbETH = IERC20(0x2Ae3F1Ec7F1F5012CFEab0185bfc7aa3cf0DEc22);
    WETH public weth = WETH(payable(0x4200000000000000000000000000000000000006));

    constructor() {
        cbETH.approve(address(aave), type(uint256).max);
        weth.approve(address(aave), type(uint256).max);

        cbETH.approve(address(compound), type(uint256).max);
    }

    function up() public {
        uint256 amount = 1 ether;
        aave.flashLoanSimple(address(this), address(cbETH), amount, new bytes(0), 0);
    }

    function executeOperation(address asset, uint256 amount, uint256 premium, address initiator, bytes calldata params)
        external
        override
        returns (bool)
    {
        require(asset == address(cbETH) || asset == address(weth), "Counter: unknown asset");

        // flash borrowed cbETH: leveraging up
        if (asset == address(cbETH)) {
            // collateralize on compound
            compound.supply(address(cbETH), amount);

            // borrow eth from compound
            compound.withdraw(address(weth), amount / 3);

            // swap WETH to cbETH

            // repay flashloan
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
}
