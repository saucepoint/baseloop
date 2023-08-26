// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.20;

interface ICometMinimal {
    function supply(address asset, uint256 amount) external;
    function withdraw(address asset, uint256 amount) external;
}
