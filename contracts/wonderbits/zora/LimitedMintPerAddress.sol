// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {ILimitedMintPerAddress} from "./ILimitedMintPerAddress.sol";

contract LimitedMintPerAddress is ILimitedMintPerAddress {
    /// @notice Storage for slot to check user mints
    /// @notice target contract -> tokenId -> minter user -> numberMinted
    /// @dev No gap or stroage interface since this is used within non-upgradeable contracts
    mapping(address => mapping(uint256 => mapping(address => uint256))) internal mintedPerAddress;

    function getMintedPerWallet(address tokenContract, uint256 tokenId, address wallet) external view returns (uint256) {
        return mintedPerAddress[tokenContract][tokenId][wallet];
    }

    function _requireMintNotOverLimitAndUpdate(uint256 limit, uint256 numRequestedMint, address tokenContract, uint256 tokenId, address wallet) internal {
        mintedPerAddress[tokenContract][tokenId][wallet] += numRequestedMint;
        if (mintedPerAddress[tokenContract][tokenId][wallet] > limit) {
            revert UserExceedsMintLimit(wallet, limit, mintedPerAddress[tokenContract][tokenId][wallet]);
        }
    }

    function supportsInterface(bytes4 interfaceId) public pure virtual override returns (bool) {
        return interfaceId == type(ILimitedMintPerAddress).interfaceId;
    }
}
