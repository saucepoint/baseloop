// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.20;

interface IAggregatorMinimal {
    function latestAnswer() external view returns (int256);
}
