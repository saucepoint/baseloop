// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.20;

interface ICometMinimal {
    function supply(address asset, uint256 amount) external;
    function supplyTo(address dst, address asset, uint256 amount) external;
    function supplyFrom(address from, address dst, address asset, uint256 amount) external;

    function withdraw(address asset, uint256 amount) external;
    function withdrawTo(address to, address asset, uint256 amount) external;
    function withdrawFrom(address src, address to, address asset, uint256 amount) external;

    function borrowBalanceOf(address account) external view returns (uint256);

    function allow(address manager, bool isAllowed) external;
}
