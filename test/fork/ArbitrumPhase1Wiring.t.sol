// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {Contract, Networks} from "@rheo-fm/script/Networks.sol";

import {CollectionsManager} from "@rheo-fm/src/collections/CollectionsManager.sol";
import {Rheo} from "@rheo-fm/src/market/Rheo.sol";
import {NonTransferrableRebasingTokenVault} from "@rheo-fm/src/market/token/NonTransferrableRebasingTokenVault.sol";

import {ISizeFactory} from "@rheo-solidity/src/factory/interfaces/ISizeFactory.sol";
import {SizeFactory} from "@rheo-solidity/src/factory/SizeFactory.sol";

import {Test} from "forge-std/Test.sol";

/// @title ArbitrumPhase1WiringForkTest
/// @notice Dry run for Phase 1.2 against the **live** Arbitrum SizeFactory.
/// @dev    Forks Arbitrum mainnet (latest block), reads the factory from `Networks.sol`,
///         then performs the exact deploy + Safe-wiring sequence that the two scripts will run:
///           1. script/DeployRheoArbitrumImplementations.s.sol — deploys 4 contracts
///           2. script/ProposeSafeTxWireRheoArbitrumFactory.s.sol — Safe proposes 3 setters
///         Verifies the factory ends up correctly wired and ready for Phase 2.
///         Run: FOUNDRY_PROFILE=fork forge test --mc ArbitrumPhase1WiringForkTest -vvv
contract ArbitrumPhase1WiringForkTest is Test, Networks {
    /// Same Safe used everywhere on Mainnet/Base/Arbitrum
    address private constant SAFE = 0x462B545e8BBb6f9E5860928748Bfe9eCC712c3a7;

    SizeFactory private sizeFactory;
    Rheo private rheoImplementation;
    NonTransferrableRebasingTokenVault private vaultImplementation;
    CollectionsManager private collectionsManagerImplementation;
    CollectionsManager private collectionsManagerProxy;

    function setUp() public {
        try vm.envString("API_KEY_ALCHEMY") returns (string memory) {
            vm.createSelectFork("arbitrum-production");
        } catch {
            vm.createSelectFork("arbitrum_archive");
        }

        sizeFactory = SizeFactory(payable(contracts[ARBITRUM_MAINNET][Contract.RHEO_FACTORY]));
        require(address(sizeFactory).code.length > 0, "live SizeFactory not deployed at registered address");

        // Mirror script/DeployRheoArbitrumImplementations.s.sol — broadcast as deployer (no role needed)
        rheoImplementation = new Rheo();
        vaultImplementation = new NonTransferrableRebasingTokenVault();
        collectionsManagerImplementation = new CollectionsManager();
        collectionsManagerProxy = CollectionsManager(
            address(
                new ERC1967Proxy(
                    address(collectionsManagerImplementation),
                    abi.encodeCall(CollectionsManager.initialize, (ISizeFactory(address(sizeFactory))))
                )
            )
        );

        // Mirror script/ProposeSafeTxWireRheoArbitrumFactory.s.sol — three calls from the Safe
        vm.startPrank(SAFE);
        sizeFactory.setRheoImplementation(address(rheoImplementation));
        sizeFactory.setNonTransferrableRebasingTokenVaultImplementation(address(vaultImplementation));
        sizeFactory.setCollectionsManager(collectionsManagerProxy);
        vm.stopPrank();
    }

    function testFork_ArbitrumPhase1_factoryOwnedBySafe() public view {
        assertTrue(sizeFactory.hasRole(0x00, SAFE), "Safe should hold DEFAULT_ADMIN_ROLE on the live factory");
    }

    function testFork_ArbitrumPhase1_rheoImplementationWired() public view {
        assertEq(sizeFactory.rheoImplementation(), address(rheoImplementation));
    }

    function testFork_ArbitrumPhase1_vaultImplementationWired() public view {
        assertEq(sizeFactory.nonTransferrableTokenVaultImplementation(), address(vaultImplementation));
    }

    function testFork_ArbitrumPhase1_collectionsManagerWired() public view {
        assertEq(address(sizeFactory.collectionsManager()), address(collectionsManagerProxy));
    }
}
