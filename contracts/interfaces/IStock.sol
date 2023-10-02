// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../interfaces/IDID.sol";


interface IStock is IERC20 {
    function mintTo(address account, uint256 amount) external;

    function burnFrom(address account, uint256 amount) external;

    function forceTransfer(address from, address to, uint256 amount) external;

    function emergencyTokenWithdrawal(address token, address to, uint256 amount) external;

    function setMultiplier(uint256 numerator, uint256 denominator) external;

    function changeNameSymbol(string calldata name, string calldata symbol_) external;

    function multiplier() external view returns (uint256, uint256);

    function issuer() external pure returns (string calldata);

    function symbol() external view returns (string calldata);

    function DID() external view returns (IDID);

    function SCID() external view returns (IDID);
}
