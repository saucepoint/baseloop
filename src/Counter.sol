// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.20;

import {IPool} from "aave-v3-core/contracts/interfaces/IPool.sol";
import {IFlashLoanSimpleReceiver} from "aave-v3-core/contracts/flashloan/interfaces/IFlashLoanSimpleReceiver.sol";
import {IPoolAddressesProvider} from "aave-v3-core/contracts/interfaces/IPoolAddressesProvider.sol";
import {ISwapRouter} from "v3-periphery/interfaces/ISwapRouter.sol";
import {IERC20} from "forge-std/interfaces/IERC20.sol";

contract Counter is IFlashLoanSimpleReceiver {
    IPool aave = IPool(0xA238Dd80C259a72e81d7e4664a9801593F98d1c5);
    ISwapRouter router = ISwapRouter(0x2626664c2603336E57B271c5C0b26F421741e481);
    IERC20 public cbETH = IERC20(0x2Ae3F1Ec7F1F5012CFEab0185bfc7aa3cf0DEc22);

    constructor() {
        cbETH.approve(address(aave), type(uint256).max);
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
        return true;
    }

    function ADDRESSES_PROVIDER() external view override returns (IPoolAddressesProvider) {
        return aave.ADDRESSES_PROVIDER();
    }

    function POOL() external view override returns (IPool) {
        return aave;
    }
}
