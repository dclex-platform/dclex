// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

interface ITokenBuilder {
    function createToken(string calldata name, string calldata symbol) external returns (address);

    function getFactory() external view returns (address);
}
