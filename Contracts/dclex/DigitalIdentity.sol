// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "./Security.sol";
import "../libs/Events.sol";
import "../libs/Model.sol";
import "../interfaces/ISignatureUtils.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "./ERC20Named.sol";

/// @title Digital Identity NFT for EOAs
/// @notice Allows stocks to be transferred
contract DigitalIdentity is Security, ERC721 {

    /// @notice token id iterator
    using Counters for Counters.Counter;

    /// @notice token id iterator
    Counters.Counter private _counter;

    ISignatureUtils immutable private utils;

    /// @notice mapping user -> token id (to reuse ids)
    mapping(address => uint256) private ids;

    /// @notice random numbers in signed structs to prevent double spending
    mapping(uint256 => uint256) private nonces;

    /// @notice token id -> TokenDetails: valid, pro, data
    mapping(uint256 => DIDTokenData) private tokens;

    /// @notice uri of valid token
    string private validURI;

    /// @notice uri of invalid token
    string private invalidURI;


    constructor(string memory _name, string memory _symbol, address _utils)
    ERC721(_name, _symbol) {
        require(_utils != address(0));
        utils = ISignatureUtils(_utils);
    }


    /// @notice Mints DID token to selected EOA. Only executed by admin
    /// @param account receiving DID token
    function mintAdmin(address account, uint256 isPro, bytes32 data) external whenNotPaused onlyRole(DEFAULT_ADMIN_ROLE) {
        if (balanceOf(account) != 0) revert AlreadyHasDID();
        __mint(account, isPro, data);
    }

    /// @notice Mints DID token to selected EOA. Only receiving address can execute
    /// @param mintStruct created on DCLEX
    /// @param signature from backend
    function mint(MintDID calldata mintStruct, bytes calldata signature) external whenNotPaused {
        if (mintStruct.account != msg.sender) revert InvalidSender();
        if (balanceOf(mintStruct.account) != 0) revert AlreadyHasDID();
        if (nonces[mintStruct.nonce] == TRUE) revert InvalidNonce();

        address creator = utils.recoverMintDID(mintStruct, signature);
        if (!hasRole(DEFAULT_ADMIN_ROLE, creator)) revert WrongSignature();

        nonces[mintStruct.nonce] = TRUE;
        __mint(mintStruct.account, mintStruct.isPro, mintStruct.data);
    }

    /// @notice Gets NFT id by account
    /// @param owner address of DID holder
    /// @return token ID of given owner address
    function getId(address owner) external view returns (uint256) {
        return ids[owner];
    }

    /// @notice Validate/invalidate DIDs
    /// @param _ids of tokens to perform operations on
    /// @param isValids set/unset valid bools
    function setValids(uint256[] calldata _ids, uint256[] calldata isValids) external onlyRole(DEFAULT_ADMIN_ROLE) {
        uint256 len = _ids.length;
        if (len != isValids.length) revert WrongArrayLengths();
        for (uint i = 0; i < len;) {
            tokens[_ids[i]].valid = isValids[i] == TRUE ? TRUE : FALSE;
            emit Events.ChangeValid(_ids[i], isValids[i] == TRUE);
        unchecked {++i;}
        }
    }

    /// @notice Check if DID is valid
    /// @param id token id
    /// @return bool valid/invalid
    function isValid(uint256 id) public view whenNotPaused returns (bool) {
        return tokens[id].valid == TRUE;
    }


    /// @notice Make DID a pro/non-pro token
    /// @param _ids of tokens to perform operations on
    /// @param isPros set/unset pro bools
    function setPros(uint256[] calldata _ids, uint256[] calldata isPros) external onlyRole(DEFAULT_ADMIN_ROLE) {
        uint256 len = _ids.length;
        if (len != isPros.length) revert WrongArrayLengths();
        for (uint i = 0; i < len;) {
            tokens[_ids[i]].pro = isPros[i] == TRUE ? TRUE : FALSE;
            emit Events.ChangePro(_ids[i], isPros[i] == TRUE);
        unchecked {++i;}
        }
    }

    /// @notice Check if DID is Pro
    /// @param id token id
    /// @return bool true if pro
    function isPro(uint256 id) external view returns (bool) {
        return tokens[id].pro == TRUE;
    }


    /// @notice Get the DID additional data
    /// @param id token id
    /// @return bytes32 token data
    function getData(uint256 id) external view returns (bytes32) {
        return tokens[id].data;
    }


    /// @notice Set additional DID data
    /// @param id of token to perform operations on
    /// @param data to be set on the token
    function setData(uint256 id, bytes32 data) external onlyRole(DEFAULT_ADMIN_ROLE) {
        tokens[id].data = data;
    }

    /// @notice Do not allow burning
    function _burn(uint256 tokenId) internal override(ERC721) {
        revert NotAllowed();
    }

    /// @notice Mint procedure, sets DID valid by default and checks of potential reuse of token ID
    /// @param account receiver
    function __mint(address account, uint256 isPro, bytes32 data) private {
        if (account.code.length != 0) revert MintToContract();
        uint256 tokenId = ids[account];
        if (tokenId == 0) {
            _counter.increment();
            tokenId = _counter.current();
            ids[account] = tokenId;
        }
        _mint(account, tokenId);

        tokens[tokenId].valid = TRUE;
        tokens[tokenId].pro = isPro;
        tokens[tokenId].data = data;

        emit Events.MintDID(account, tokenId);
    }

    /// @notice Do not allow for regular transfers
    function _transfer(
        address from,
        address to,
        uint256 tokenId
    ) internal override(ERC721) {
        revert NotAllowed();
    }

    /// @notice Security function to transfer tokens of lost access to account
    /// @param transfer did struct
    /// @param signature from backend
    function forceTransfer(TransferDID calldata transfer, bytes calldata signature) external whenNotPaused {
        if (nonces[transfer.nonce] == TRUE) revert InvalidNonce();
        if (ownerOf(transfer.id) != transfer.account) revert InvalidSender();

        address creator = utils.recoverTransferDID(transfer, signature);

        if (!hasRole(DEFAULT_ADMIN_ROLE, creator)) revert WrongSignature();

        nonces[transfer.nonce] = TRUE;
        ids[transfer.account] = 0;
        ids[transfer.to] = transfer.id;

        super._transfer(transfer.account, transfer.to, transfer.id);
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
