// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";

import {IRheo} from "@rheo-fm/src/market/interfaces/IRheo.sol";
import {Errors} from "@rheo-fm/src/market/libraries/Errors.sol";
import {ISizeFactory} from "@rheo-solidity/src/factory/interfaces/ISizeFactory.sol";

/// @title PauseAll
/// @custom:security-contact security@rheo.xyz
/// @notice Single-call kill-switch that pauses every market registered on the SizeFactory.
/// @dev    Owner-gated (Ownable2Step). Two natural deployments:
///           - Owner = the governance Safe — manual emergency pause via Safe ceremony.
///           - Owner = an autonomous monitor signer (e.g. Hypernative bot) — fast autonomous
///             pause when an off-chain alert fires. Ownership can be transferred from Safe → bot
///             post-deploy via Ownable2Step's two-step accept flow.
///         For PauseAll to actually pause markets, the SizeFactory must grant it `PAUSER_ROLE`
///         (or each market must grant it `PAUSER_ROLE` individually). Without the role,
///         `markets[i].pause()` reverts and the whole `pauseAll()` call rolls back.
contract PauseAll is Ownable2Step {
    /// @notice The SizeFactory whose markets this contract can pause.
    ISizeFactory public immutable sizeFactory;

    /// @notice Emitted on construction with the SizeFactory address.
    event SizeFactorySet(ISizeFactory indexed sizeFactory);

    constructor(ISizeFactory _sizeFactory, address _owner) Ownable(_owner) {
        if (address(_sizeFactory) == address(0)) {
            revert Errors.NULL_ADDRESS();
        }
        sizeFactory = _sizeFactory;
        emit SizeFactorySet(_sizeFactory);
    }

    /// @notice Pause every unpaused market the SizeFactory knows about.
    /// @dev    Skips already-paused markets so a repeated call is a no-op rather than reverting.
    ///         If the caller doesn't have `PAUSER_ROLE` on the factory, the first `pause()` call
    ///         reverts and the whole tx rolls back — by design (no partial state).
    function pauseAll() external onlyOwner {
        address[] memory markets = sizeFactory.getMarkets();
        for (uint256 i = 0; i < markets.length; i++) {
            if (!PausableUpgradeable(markets[i]).paused()) {
                IRheo(markets[i]).pause();
            }
        }
    }
}
