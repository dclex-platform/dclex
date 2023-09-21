// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "./Security.sol";
import "./ERC20Named.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "../libs/Model.sol";
import "../interfaces/IStock.sol";
import "../interfaces/IDID.sol";
import "../interfaces/ISignatureUtils.sol";
import "../interfaces/IFactory.sol";


/// @title Stocks token contract
contract Stock is Security, IStock, ERC20Named {

    IFactory private factory;

    /// @notice security properties in case of stock split
    uint256 private mNumerator = 1;
    uint256 private mDenominator = 1;

    constructor(string memory name, string memory _symbol, address _factory)
    ERC20Named(name, _symbol)
    {
        factory = IFactory(_factory);
    }


    /// @notice Mints Stocks tokens to selected address. Only executed by factory
    /// @param account receiving stocks
    /// @param amount of stocks to mint
    function mintTo(address account, uint256 amount) external onlyRole(DEFAULT_ADMIN_ROLE) whenNotPaused {
        if (!DID().isValid(DID().getId(account))) revert InvalidDID();
        _mint(account, amount);
    }


    /// @notice Burns Stocks tokens from selected address. Only executed by factory
    /// @param account depositing stocks to DCLEX
    /// @param amount of stocks to burn
    function burnFrom(address account, uint256 amount) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _burn(account, amount);
    }


    /// @notice Overrides ERC-20 transfer by DID/SCID verification
    /// @param to which address perform transfer
    /// @param amount of stocks to transfer
    function transfer(address to, uint256 amount) public override(IERC20, ERC20Named) checkTransferActors(msg.sender, to) whenNotPaused returns (bool) {
        return super.transfer(to, amount);
    }


    /// @notice Overrides ERC-20 transfer by DID/SCID verification
    /// @param from which address perform a transfer
    /// @param to which address perform transfer
    /// @param amount of stocks to transfer
    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) public override(IERC20, ERC20Named) whenNotPaused checkTransferActors(from, to) returns (bool) {
        return super.transferFrom(from, to, amount);
    }

    /// @notice Security function to transfer from lost account. Only executed by factory
    /// @param from which address perform a transfer
    /// @param to which address perform transfer
    /// @param amount of stocks to transfer
    /// @dev we skip FROM checks since the account may be already invalidated
    function forceTransfer(address from, address to, uint256 amount) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (to.code.length == 0 && !DID().isValid(DID().getId(to))) revert InvalidDID();
        if (SCID().balanceOf(to) != 0) {
            if (!SCID().isValid(SCID().getId(to))) revert InvalidSmartcontract();
        }
        _transfer(from, to, amount);
    }


    /// @notice Security function in case of mistakenly transferred tokens to this address. Executed by admin
    /// @param token address
    /// @param to receiver
    /// @param amount of tokens to transfer
    function emergencyTokenWithdrawal(address token, address to, uint256 amount) external onlyRole(DEFAULT_ADMIN_ROLE) nonReentrant {
        if (token == address(0)) {
            to.call{value : amount}("");
        } else {
            IERC20(token).transfer(to, amount);
        }
    }


    /// @notice Security function in case of real stocks split. Executed by factory
    /// @param numerator for multiplication
    /// @param denominator for division
    function setMultiplier(uint256 numerator, uint256 denominator) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (numerator == 0) revert MultiplyByZero();
        if (denominator == 0) revert DivideByZero();
        mNumerator = numerator;
        mDenominator = denominator;
    }

    function changeNameSymbol(string calldata name, string calldata symbol_) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _name = name;
        _symbol = symbol_;
    }

    function multiplier() external view returns (uint256, uint256) {
        return (mNumerator, mDenominator);
    }

    function issuer() external pure returns (string memory) {
        return "dclex";
    }


    function symbol() public view override(ERC20Named, IStock) returns (string memory) {
        return super.symbol();
    }

    function DID() public view returns (IDID) {
        return factory.getDID();
    }

    function SCID() public view returns (IDID) {
        return factory.getSCID();
    }


    // @dev Modifiers
    modifier checkTransferActors(address from, address to) {
        if (!DID().isValid(DID().getId(from)) && (SCID().balanceOf(from) == 0 || !SCID().isValid(SCID().getId(from)))) revert InvalidDID();
        if (to.code.length == 0 && !DID().isValid(DID().getId(to))) revert InvalidDID();
        if (SCID().balanceOf(to) != 0) {
            if (!SCID().isValid(SCID().getId(to))) revert InvalidSmartcontract();
        }
        _;
    }
}
