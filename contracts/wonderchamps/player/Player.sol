// SPDX-License-Identifier: MIT

pragma solidity ^0.8.26;

import "./IPlayer.sol";
import "./IPlayerErrors.sol";
import "../items/Item.sol";

import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "../utils/EventSignatures.sol";

// Contract for player-related operations.
abstract contract Player is IPlayer, IPlayerErrors, Item, AccessControl, EventSignatures {
    using ECDSA for bytes32;
    using MessageHashUtils for bytes32;

    // maps from the player's address to a boolean value indicating whether they've created an account.
    mapping (address => bool) internal hasAccount;
    // maps from the player's address to the amount of IGC they own.
    //
    // BIT POSITIONS:
    // [0 - 127] - gold (premium currency)
    // [128 - 255] - marble (common currency)
    mapping (address => uint256) internal ownedIGC;
    // maps from the player's address to an item ID to the item instance.
    // if {OwnedItem.owned} is true, then the player owns the item.
    mapping (address => mapping (uint256 => OwnedItem)) internal ownedItems;
    // maps from the player's address to an item fragment ID to the item fragment instance.
    // if {OwnedItemFragment.owned} is true, then the player owns the item fragment.
    mapping (address => mapping (uint256 => OwnedItemFragment)) internal ownedItemFragments;
    // maps from the player's address to their drawing stats.
    //
    // BIT POSITIONS:
    // [0 - 127] - currentDrawPerMatchLevel (i.e. how many wheels can be drawn per match)
    // [128 - 255] - currentDrawLengthLevel (i.e. how long a wheel can be drawn)
    mapping (address => uint256) internal drawingStats;
    // maps from the player's address to the league season to their league data within that season.
    mapping (address => mapping (uint256 => LeagueData)) internal leagueData;

    /**
     * @dev Modifier that checks if the caller is the player itself or an admin (i.e. has the DEFAULT_ADMIN_ROLE).
     */
    modifier onlyPlayerOrAdmin(address player) {
        _checkPlayerOrAdmin(player);
        _;
    }

    /**
     * @dev Modifier that checks if the player is new (i.e. doesn't exist in the players mapping).
     */
    modifier onlyNewPlayer(address player) {
        _checkPlayerExists(player);
        _;
    }

    /**
     * @dev Gets a player's data.
     *
     * NOTE: Because mappings can't iterate over all elements, the function takes in the IDs of the 
     * items, fragments, and league seasons that the player owns and played in respectively.
     */
    function getPlayer(
        address player,
        uint256[] calldata itemIDs,
        uint256[] calldata fragmentIDs,
        uint256[] calldata leagueSeasons
    ) onlyPlayerOrAdmin(player) external view returns (
        uint256 _ownedIGC,
        OwnedItem[] memory items,
        OwnedItemFragment[] memory fragments,
        uint256 _drawingStats,
        LeagueData[] memory _leagueData
    ) {
        items = new OwnedItem[](itemIDs.length);
        fragments = new OwnedItemFragment[](fragmentIDs.length);
        _leagueData = new LeagueData[](leagueSeasons.length);

        for (uint256 i = 0; i < itemIDs.length;) {
            items[i] = ownedItems[player][itemIDs[i]];

            unchecked {
                ++i;
            }
        }

        for (uint256 i = 0; i < fragmentIDs.length;) {
            fragments[i] = ownedItemFragments[player][fragmentIDs[i]];

            unchecked {
                ++i;
            }
        }

        for (uint256 i = 0; i < leagueSeasons.length;) {
            _leagueData[i] = leagueData[player][leagueSeasons[i]];

            unchecked {
                ++i;
            }
        }

        return (
            ownedIGC[player],
            items,
            fragments,
            drawingStats[player],
            _leagueData
        );
    }

    /**
     * @dev Creates a new player instance.
     *
     * Requires the admin's signature.
     */
    function createPlayer(
        address player,
        bytes32 salt,
        uint256 timestamp,
        bytes calldata adminSig
    ) external onlyNewPlayer(player) {
        // ensure that the signature is valid (i.e. the recovered address is the admin's address)
        address recoveredAddress = ECDSA.recover(
            MessageHashUtils.toEthSignedMessageHash(
                playerDataHash(player, salt, timestamp)
            ),
            adminSig
        );

        if (!hasRole(DEFAULT_ADMIN_ROLE, recoveredAddress)) {
            revert InvalidAdminSignature();
        }

        // create the player instance by setting the player's {hasAccount} mapping to true.
        // NOTE: 
        // {ownedIGC} does NOT need to be set to 0 because it's already set to 0 by default.
        // {ownedItems}, {ownedItemFragments} and {leagueData} do NOT need to be set to empty mappings because they're already empty by default.
        // {drawingStats} does NOT need to be set to 0 because it's already set to 0 by default.
        hasAccount[player] = true;

        assembly {
            // emit the PlayerCreated event.
            log2(
                0, // 0 offset because no additional data is appended
                0, // 0 size because no additional data is appended
                _PLAYER_CREATED_EVENT_SIGNATURE,
                player
            )
        }
    }

    /**
     * @dev Deletes a player's data.
     *
     * NOTE: Requires the ownedItemIDs, ownedItemFragmentIDs and leagueSeasons to be manually inputted, which will all be deleted.
     *
     * NOTE: Requires both the admin and the player's signatures to ensure that the player is the one who wishes to delete their account.
     *
     * sigs[0] - the admin's signature
     * sigs[1] - the player's signature
     */
    function deletePlayer(
        address player, 
        uint256[] calldata ownedItemIDs,
        uint256[] calldata ownedItemFragmentIDs,
        uint256[] calldata leagueSeasons,
        bytes32 salt, 
        uint256 timestamp,
        bytes[2] calldata sigs
    ) external {
        address recoveredAdmin = ECDSA.recover(
            MessageHashUtils.toEthSignedMessageHash(
                playerDataHash(player, salt, timestamp)
            ),
            sigs[0]
        );

        address recoveredPlayer = ECDSA.recover(
            MessageHashUtils.toEthSignedMessageHash(
                playerDataHash(player, salt, timestamp)
            ),
            sigs[1]
        );

        if (!hasRole(DEFAULT_ADMIN_ROLE, recoveredAdmin)) {
            revert InvalidAdminSignature();
        }

        if (recoveredPlayer != player) {
            revert InvalidPlayerSignature();
        }

        // delete the player instance.
        hasAccount[player] = false;
        ownedIGC[player] = 0;
        drawingStats[player] = 0;

        for (uint256 i = 0; i < ownedItemIDs.length;) {
            delete ownedItems[player][ownedItemIDs[i]];

            unchecked {
                ++i;
            }
        }

        for (uint256 i = 0; i < ownedItemFragmentIDs.length;) {
            delete ownedItemFragments[player][ownedItemFragmentIDs[i]];

            unchecked {
                ++i;
            }
        }

        for (uint256 i = 0; i < leagueSeasons.length;) {
            delete leagueData[player][leagueSeasons[i]];

            unchecked {
                ++i;
            }
        }

        // emit the PlayerDeleted event.
        assembly {
            log2(
                0, // 0 offset because no additional data is appended
                0, // 0 size because no additional data is appended
                _PLAYER_DELETED_EVENT_SIGNATURE,
                player
            )
        }
    }

    /**
     * @dev Checks whether a player exists.
     */
    function playerExists(address player) public view override returns (bool) {
        return hasAccount[player];
    }

    /**
     * @dev Gets the hash of a player creation or deletion request.
     */
    function playerDataHash(
        address player,
        bytes32 salt,
        uint256 timestamp
    ) public pure returns (bytes32) {
        return keccak256(abi.encodePacked(player, salt, timestamp));
    }

    /**
     * @dev Checks whether the caller is the player itself or an admin.
     */
    function _checkPlayerOrAdmin(address player) private view {
        if (_msgSender() != player && !hasRole(DEFAULT_ADMIN_ROLE, _msgSender())) {
            revert NotSelfOrAdmin();
        }
    }

    /**
     * @dev Checks whether a player exists.
     */
    function _checkPlayerExists(address player) private view {
        if (!playerExists(player)) {
            revert PlayerAlreadyExists();
        }
    }
}