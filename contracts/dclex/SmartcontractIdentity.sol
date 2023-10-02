// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "./Security.sol";
import "../libs/Events.sol";
import "../libs/Model.sol";
import "../interfaces/ISignatureUtils.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "../interfaces/IFactory.sol";

/// @title Digital Identity NFT for smartcontracts
/// @notice Allows stocks to be transferred
contract SmartcontractIdentity is Security, ERC721 {
    /// @notice token id iterator
    using Counters for Counters.Counter;

    /// @notice token id iterator
    Counters.Counter private _counter;

    ISignatureUtils immutable private utils;
    IFactory immutable private factory;

    /// @notice mapping smartcontract -> token id (to reuse ids)
    mapping(address => uint256) private ids;

    /// @notice token id -> Valid and proposer struct
    mapping(uint256 => ScIDTokenData) tokenDetails;

    /// @notice random numbers in signed structs to prevent double spending
    mapping(uint256 => uint256) private nonces;

    /// @notice uri of valid token
    string private validURI;

    /// @notice uri of invalid token
    string private invalidURI;



    constructor(string memory _name, string memory _symbol, address _utils, address _factory)
    ERC721(_name, _symbol) {
        require(_utils != address(0));
        require(_factory != address(0));
        utils = ISignatureUtils(_utils);
        factory = IFactory(_factory);
    }


    /// @notice Mints SCID token to selected smartcontract. Only executed by admin
    /// @param account receiving SCID token
    function mintAdmin(address account) external whenNotPaused onlyRole(DEFAULT_ADMIN_ROLE) {
        if (account.code.length == 0) revert MintNotToContract();
        __mint(msg.sender, account);
    }


    /// @notice Mints SCID token to selected smartcontract. Executed by a proposer
    /// @param mintStruct create on DCLEX
    /// @param signature from backend
    function mint(MintScID calldata mintStruct, bytes calldata signature) external whenNotPaused {
        if (nonces[mintStruct.nonce] == TRUE) revert InvalidNonce();
        if (mintStruct.account.code.length == 0) revert MintNotToContract();
        if (balanceOf(mintStruct.account) != 0) revert AlreadyHasDID();

        address creator = utils.recoverMintScID(mintStruct, signature);
        if (!hasRole(DEFAULT_ADMIN_ROLE, creator)) revert WrongSignature();

        nonces[mintStruct.nonce] = TRUE;
        __mint(msg.sender, mintStruct.account);
    }


    /// @notice Gets NFT id by account
    /// @param owner address of SCID holder
    /// @return token ID of given owner address
    function getId(address owner) external view returns (uint256) {
        return ids[owner];
    }


    /// @notice Validate/invalidate SCIDs
    /// @param _ids of tokens to perform operations on
    /// @param isValids set/unset valid bools
    function setValids(uint256[] calldata _ids, uint256[] calldata isValids) external onlyRole(DEFAULT_ADMIN_ROLE) {
        uint256 len = _ids.length;
        if (len != isValids.length) revert WrongArrayLengths();
        for (uint i = 0; i < _ids.length;) {
            tokenDetails[_ids[i]].valid = isValids[i] == TRUE ? TRUE : FALSE;
            emit Events.ChangeValid(_ids[i], isValids[i] == TRUE);
        unchecked {++i;}
        }
    }


    /// @notice Check if SCID is valid
    /// @param id SCID token id
    /// @return bool valid/invalid
    function isValid(uint256 id) public view whenNotPaused returns (bool) {
        return tokenDetails[id].valid == TRUE;
    }


    /// @notice Security function to invalidate signatures
    /// @param _nonces nonces for invalidation
    function useNonces(uint256[] calldata _nonces) external whenNotPaused onlyRole(DEFAULT_ADMIN_ROLE) {
        uint256 len = _nonces.length;
        for (uint256 i = 0; i < len;) {
            nonces[_nonces[i]] = TRUE;
        unchecked {++i;}
        }
    }


    /// @notice Do not allow burning
    function _burn(uint256 tokenId) internal override(ERC721) {
        revert NotAllowed();
    }


    /// @notice Mint procedure, sets DID valid by default and checks of potential reuse of token ID
    /// @param account receiver
    function __mint(address creator, address account) private {
        require(factory.getDID().isValid(factory.getDID().getId(msg.sender)), "DCLEX: Proposer needs valid DID");
        uint256 tokenId = ids[account];
        if (tokenId == 0) {
            _counter.increment();
            tokenId = _counter.current();
            ids[account] = tokenId;
        }
        _mint(account, tokenId);
        tokenDetails[tokenId].proposer = msg.sender;
        tokenDetails[tokenId].valid = TRUE;
        emit Events.MintSCID(creator, account, tokenId);
    }

    /// @notice Do not allow for regular transfers
    function _transfer(
        address from,
        address to,
        uint256 tokenId
    ) internal override(ERC721) {
        revert NotAllowed();
    }

    /// @notice Function returning URI of token. There are two types of URIs. Additionally, it checks if token exists.
    /// @param tokenId ID of token
    /// @return token URI
    function tokenURI(uint256 tokenId) public view override(ERC721) returns (string memory) {
        _requireMinted(tokenId);

        if(isValid(tokenId))
            return validURI;
        else return invalidURI;
    }

    /// @notice Sets token URI
    /// @param valid for which token type URI is set
    /// @param _tokenURI token URI
    function setTokenURI(uint256 valid, string memory _tokenURI) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if(valid == TRUE)
            validURI = _tokenURI;
        else
            invalidURI = _tokenURI;
    }


    function supportsInterface(bytes4 interfaceId) public view override(ERC721, AccessControl) returns (bool){
        return super.supportsInterface(interfaceId);
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


    function issuer() external pure returns (string memory) {
        return "dclex";
    }

    /// @notice check if nonce was used
    /// @param nonce nonce to check
    /// @return 0, 1, 2...
    function getNonce(uint256 nonce) external returns(uint256) {
        return nonces[nonce];
    }
}
