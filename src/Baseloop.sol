// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.20;

import {console2} from "forge-std/console2.sol";
import {IV3SwapRouter} from "swap-router-contracts/interfaces/IV3SwapRouter.sol";
import {IERC20} from "forge-std/interfaces/IERC20.sol";
import {WETH} from "solmate/tokens/WETH.sol";
import {ICometMinimal} from "./interfaces/ICometMinimal.sol";
import {IAggregatorMinimal} from "./interfaces/IAggregatorMinimal.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import {IFlashLoanRecipient} from "./interfaces/IFlashLoanRecipient.sol";
import {IVaultMinimal} from "./interfaces/IVaultMinimal.sol";

/// @title Baseloop - leverage long cbETH on Compound III
/// @author saucepoint.eth
contract Baseloop is IFlashLoanRecipient {
    using FixedPointMathLib for uint256;

    mapping(address operator => mapping(address user => bool allowed)) public allowed;

    ICometMinimal public constant compound = ICometMinimal(0x46e6b214b524310239732D51387075E0e70970bf);
    IAggregatorMinimal public constant priceFeed = IAggregatorMinimal(0x806b4Ac04501c29769051e42783cF04dCE41440b);
    IV3SwapRouter public constant router = IV3SwapRouter(0x2626664c2603336E57B271c5C0b26F421741e481);
    IVaultMinimal public constant balancerVault = IVaultMinimal(0xBA12222222228d8Ba445958a75a0704d566BF2C8);

    IERC20 public constant cbETH = IERC20(0x2Ae3F1Ec7F1F5012CFEab0185bfc7aa3cf0DEc22);
    WETH public constant weth = WETH(payable(0x4200000000000000000000000000000000000006));

    address public constant DEV_DONATE = address(0x46792084f2FA64244ec3Ab3e9F992E01dbFB023d);

    // tightly pack with uint144, max of 2.23e25 ether
    struct FlashCallbackData {
        uint144 amountToSupply; // amount of cbETH to supply on compound
        uint144 amountToWithdraw; // amount of ETH to borrow from compound
        uint64 cbETHPrice; // price of cbETH in ETH, in WAD format. 1.04e18 = 1.04 ETH per each cbETH token
        address user;
    }

    constructor() {
        cbETH.approve(address(compound), type(uint256).max);
        weth.approve(address(compound), type(uint256).max);

        cbETH.approve(address(router), type(uint256).max);
        weth.approve(address(router), type(uint256).max);
    }

    // -- Leverage Up (User Facing) -- //
    function adjustPosition(address user, uint256 targetCollateralValue, uint256 targetCollateralFactor) external payable operatorPermission(user) {
        weth.deposit{value: msg.value}();
        uint256 cbETHPrice = uint256(priceFeed.latestAnswer());

        (int256 collateralDelta, int256 borrowDelta) =
            getDeltas(user, targetCollateralValue, targetCollateralFactor, cbETHPrice);

        if (0 < collateralDelta) {
            adjustUp(user, uint256(collateralDelta), uint256(borrowDelta), cbETHPrice);
        } else {
            adjustDown(uint256(-collateralDelta), uint256(-borrowDelta));
        }
    }

    function adjustUp(address user, uint256 collateralDelta, uint256 borrowDelta, uint256 cbETHPrice) internal {
        flashBorrow(cbETH, collateralDelta, collateralDelta, borrowDelta, uint64(cbETHPrice), user);
        returnETH();
    }

    function adjustDown(uint256 collateralDelta, uint256 borrowDelta) internal {
        // withdraw a bit of excess in case trading price != oracle price
        uint256 amountToWithdraw = collateralDelta.mulWadDown(1.01e18);
        amountToWithdraw = compound.collateralBalanceOf(msg.sender, address(cbETH)) < amountToWithdraw
            ? compound.collateralBalanceOf(msg.sender, address(cbETH))
            : amountToWithdraw;

        flashBorrow(
            IERC20(address(weth)),
            msg.value < borrowDelta ? borrowDelta - msg.value : 0,
            borrowDelta,
            amountToWithdraw,
            0,
            msg.sender
        );

        returnETH();
        returnCBETH();
    }

    /// @notice Open a leveraged position starting with cbETH. The cbETH + flashloan get provided as collateral to compound
    function adjustPositionCBETH(uint256 cbETHAmount, uint256 targetCollateral, uint256 targetCollateralFactor)
        external
    {
        uint256 currentCollateral = compound.collateralBalanceOf(msg.sender, address(cbETH));
        require(currentCollateral <= targetCollateral, "new collateral must be higher");

        cbETH.transferFrom(msg.sender, address(this), cbETHAmount);

        uint256 amountToFlash;
        uint256 collateralDelta;
        unchecked {
            collateralDelta = targetCollateral - currentCollateral;
            require(cbETHAmount <= collateralDelta, "providing more cbETH than needed");
            amountToFlash = collateralDelta - cbETHAmount;
        }

        uint256 cbETHPrice = uint256(priceFeed.latestAnswer());

        // how much ETH borrow according to a collateral factor / LTV
        uint256 amountToBorrow = collateralDelta.mulWadDown(cbETHPrice).mulWadDown(targetCollateralFactor);

        flashBorrow(cbETH, amountToFlash, collateralDelta, amountToBorrow, uint64(cbETHPrice), msg.sender);

        returnETH();
        returnCBETH();
    }

    // -- Leverage Down (User Facing) -- //

    /// @notice Fully close a leveraged position. Optionally provide ETH (esp if cbETH depegged on Uni)
    function close() external payable {
        uint256 totalCompoundRepay = compound.borrowBalanceOf(msg.sender);
        uint256 flashAmount = totalCompoundRepay;
        if (0 < msg.value) {
            weth.deposit{value: msg.value}();
            unchecked {
                flashAmount -= msg.value;
            }
        }

        // if user can repay the loan entirely with Ether balance, they might as well use the UI
        // instead of the contract
        flashBorrow(
            IERC20(address(weth)),
            flashAmount,
            totalCompoundRepay,
            compound.collateralBalanceOf(msg.sender, address(cbETH)),
            0,
            msg.sender
        );

        returnETH();
        returnCBETH();
    }

    function flashBorrow(
        IERC20 asset,
        uint256 amount,
        uint256 amountToSupply,
        uint256 amountToWithdraw,
        uint256 cbETHPrice,
        address user
    ) internal {
        IERC20[] memory tokens = new IERC20[](1);
        tokens[0] = asset;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = amount;
        balancerVault.flashLoan(
            this,
            tokens,
            amounts,
            abi.encode(
                FlashCallbackData(uint144(amountToSupply), uint144(amountToWithdraw), uint64(cbETHPrice), user)
            )
        );
    }

    function receiveFlashLoan(
        IERC20[] memory tokens,
        uint256[] memory amounts,
        uint256[] memory feeAmounts,
        bytes calldata params
    ) external override {
        require(msg.sender == address(balancerVault), "only balancer");
        IERC20 asset = tokens[0];
        require(asset == cbETH || address(asset) == address(weth), "unknown asset");

        FlashCallbackData memory data = abi.decode(params, (FlashCallbackData));

        unchecked {
            uint256 amountToRepay = amounts[0] + feeAmounts[0];
            asset == cbETH ? leverage(data, amountToRepay) : deleverage(data, amountToRepay);

            // pay back flashloan
            asset.transfer(msg.sender, amountToRepay);
        }
    }

    // -- Internal Leverage Up/Down -- //
    function leverage(FlashCallbackData memory data, uint256 amountToRepay) internal {
        address user = data.user;
        // collateralize on compound
        compound.supplyTo(user, address(cbETH), data.amountToSupply);

        // borrow eth from compound
        compound.withdrawFrom(user, address(this), address(weth), data.amountToWithdraw);

        // swap WETH to cbETH to repay flashloan
        if (0 < amountToRepay) {
            router.exactOutputSingle(
                IV3SwapRouter.ExactOutputSingleParams({
                    tokenIn: address(weth),
                    tokenOut: address(cbETH),
                    fee: 500,
                    recipient: address(this),
                    amountOut: amountToRepay,
                    amountInMaximum: amountToRepay.mulWadDown(data.cbETHPrice).mulWadDown(1.02e18), // 2% max slippage
                    sqrtPriceLimitX96: 0
                })
            );
        }
    }

    function deleverage(FlashCallbackData memory data, uint256 amountToRepay) internal {
        address user = data.user;

        // repay on compound
        compound.supplyTo(user, address(weth), data.amountToSupply);

        // withdraw cbETH
        compound.withdrawFrom(user, address(this), address(cbETH), data.amountToWithdraw);

        // swap cbETH to WETH
        if (0 < amountToRepay) {
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
    }

    // -- Utils & Helpers -- //
    modifier operatorPermission(address user) {
        require(msg.sender == user || allowed[msg.sender][user], "No Permission");
        _;
    }

    function setAllow(address operator, bool allow) external {
        allowed[operator][msg.sender] = allow;
    }

    function rescueERC20(address token) external {
        IERC20(token).transfer(msg.sender, IERC20(token).balanceOf(address(this)));
    }

    function rescueETH() external {
        payable(msg.sender).transfer(address(this).balance);
    }

    /// @notice Donate to the developer!
    function developerDonate() external payable {
        payable(DEV_DONATE).transfer(msg.value);
    }

    function returnETH() internal {
        uint256 excess = weth.balanceOf(address(this));
        if (0 != excess) {
            weth.withdraw(excess);
            (bool success,) = msg.sender.call{value: excess}("");
            require(success, "transfer failed");
        }
    }

    function returnCBETH() internal {
        uint256 excess = cbETH.balanceOf(address(this));
        if (0 != excess) {
            cbETH.transfer(msg.sender, excess);
        }
    }

    /// @notice Given a new position parameters, get the deltas required to achieve the new position
    function getDeltas(address user, uint256 newCollateralValue, uint256 newFactor, uint256 cbETHPrice)
        internal
        view
        returns (int256 collateralDelta, int256 borrowDelta)
    {
        uint256 currentCollateral = compound.collateralBalanceOf(user, address(cbETH));
        uint256 currentBorrow = compound.borrowBalanceOf(user);

        uint256 targetBorrow = newFactor.mulWadDown(newCollateralValue);
        uint256 targetCollateral = newCollateralValue.divWadDown(cbETHPrice);

        unchecked {
            collateralDelta = int256(targetCollateral) - int256(currentCollateral);
            borrowDelta = int256(targetBorrow) - int256(currentBorrow);
        }
    }

    /// @notice Get a hint on how much additional ETH is required for adjustPosition()
    function calcAdditionalETH(address user, uint256 newCollateralValue, uint256 newFactor)
        external
        view
        returns (uint256 additionalETH)
    {
        uint256 cbETHPrice = uint256(priceFeed.latestAnswer());

        (int256 collateralDelta, int256 borrowDelta) = getDeltas(user, newCollateralValue, newFactor, cbETHPrice);

        // calculate how much ETH was required to change collateral
        uint256 collateralDeltaValue =
            uint256(collateralDelta < 0 ? -collateralDelta : collateralDelta).mulWadDown(cbETHPrice).mulWadDown(1.05e18); // collateral change expressed in ETH
        if (borrowDelta < 0) {
            additionalETH = collateralDeltaValue + uint256(-borrowDelta);
        } else {
            if (uint256(borrowDelta) < collateralDeltaValue) {
                additionalETH = collateralDeltaValue - uint256(borrowDelta);
            }
        }
    }

    receive() external payable {}
    fallback() external {}
}
