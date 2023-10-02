// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "./IDID.sol";

interface IFactory {
    function getDID() external view returns (IDID);

    function getSCID() external view returns (IDID);
}
