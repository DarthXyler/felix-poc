// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {DeployFelix} from "./TestContracts/DeployFelix.sol";

import {IBorrowerOperations} from "../src/Interfaces/IBorrowerOperations.sol";
import {ITroveManager} from "../src/Interfaces/ITroveManager.sol";
import {IAddressesRegistry} from "../src/Interfaces/IAddressesRegistry.sol";
import {IPriceFeed} from "../src/Interfaces/IPriceFeed.sol";
import {TroveManager} from "../src/TroveManager.sol";

/// @dev Minimal fake L1 oracle that always reverts.
///      We overwrite the SYSTEM_CONTRACT address with this code to simulate oracle failure.
contract OracleReverter {
    // Same signature HLPriceFeed expects on L1Read
    function oraclePx(uint16 /* index */) external pure returns (uint64) {
        revert("oracle failure");
    }
}

contract ShutdownOracleFailureBypassTest is Test {
    DeployFelix public deployFelix;

    IBorrowerOperations public borrowerOperations;
    ITroveManager public troveManager;
    IAddressesRegistry public addressesRegistry;
    IPriceFeed public priceFeed;

    /// @dev Override the Hypeliquid L1Read SYSTEM_CONTRACT with our reverting oracle.
    function _forceOracleFailure() internal {
        // address constant SYSTEM_CONTRACT = 0x44AFB4F9134c21E3ee69c785073FE2550607CA2a;
        OracleReverter reverter = new OracleReverter();
        vm.etch(
            0x44AFB4F9134c21E3ee69c785073FE2550607CA2a,
            address(reverter).code
        );
    }

    function setUp() public {
        deployFelix = new DeployFelix();
        deployFelix.run();

        borrowerOperations = IBorrowerOperations(
            deployFelix.branchContractAddresses(
                DeployFelix.Collaterals.WHYPE,
                DeployFelix.ContractTypes.BORROWER_OPERATIONS
            )
        );

        troveManager = ITroveManager(
            deployFelix.branchContractAddresses(
                DeployFelix.Collaterals.WHYPE,
                DeployFelix.ContractTypes.TROVE_MANAGER
            )
        );

        addressesRegistry = IAddressesRegistry(
            deployFelix.branchContractAddresses(
                DeployFelix.Collaterals.WHYPE,
                DeployFelix.ContractTypes.ADDRESSES_REGISTRY
            )
        );

        priceFeed = IPriceFeed(addressesRegistry.priceFeed());
    }

    /// @notice Oracle failure triggers HLPriceFeed shutdown path and sets BorrowerOperations temporary shutdown.
    function test_oracleFailure_setsTemporaryShutdown() public {
        // Pre-condition: branch is healthy, no shutdown
        assertEq(
            borrowerOperations.isTemporaryShutdown(),
            false,
            "should start with no temporary shutdown"
        );
        assertEq(
            borrowerOperations.hasBeenShutDown(),
            false,
            "permanent shutdown should be false initially"
        );

        // 1. Force oracle failure via fake L1Read
        _forceOracleFailure();

        // 2. This fetch goes through HLPriceFeed._getL1ReadResponse catch path
        //    and returns INVALID_PRICE, which triggers _disableFeedAndShutDown(...)
        (, bool newOracleFailureDetected) = priceFeed.fetchPrice();

        // HLPriceFeed should set priceFeedDisabled = true and call
        // borrowerOperations.shutdownFromOracleFailure(...)
        assertEq(newOracleFailureDetected, true, "oracle failure flag should be true");

        // BorrowerOperations should move into temporary shutdown mode
        assertEq(
            borrowerOperations.isTemporaryShutdown(),
            true,
            "BorrowerOperations should be temporarily shut down after oracle failure"
        );

        // It should NOT flip hasBeenShutDown (that is reserved for full shutdown)
        assertEq(
            borrowerOperations.hasBeenShutDown(),
            false,
            "hasBeenShutDown should remain false after oracle failure shutdown"
        );

        // Also important: priceFeed can still be queried again and returns lastGoodPrice
        (uint256 priceFinal, bool failureFlagFinal) = priceFeed.fetchPrice();
        assertEq(
            failureFlagFinal,
            false,
            "subsequent fetch should not report a NEW oracle failure once disabled"
        );
        assertGt(priceFinal, 0, "lastGoodPrice should remain > 0");
    }

    /// @notice After oracle failure, BorrowerOperations is shut down but TroveManager remains callable.
    function test_shutdownOracleFailure_branchPartiallyActive() public {
        // 1. Pre-condition: system is healthy
        assertEq(
            borrowerOperations.isTemporaryShutdown(),
            false,
            "pre: temporary shutdown must be false"
        );
        assertEq(
            borrowerOperations.hasBeenShutDown(),
            false,
            "pre: permanent shutdown must be false"
        );

        // 2. Force oracle failure via our fake L1Read implementation
        _forceOracleFailure();

        // This will trigger HLPriceFeed shutting down via shutdownFromOracleFailure(...)
        (, bool newOracleFailureDetected) = priceFeed.fetchPrice();
        assertEq(newOracleFailureDetected, true, "oracle failure must be detected");

        // 3. Verify BorrowerOperations is now in temporary shutdown mode
        assertEq(
            borrowerOperations.isTemporaryShutdown(),
            true,
            "BorrowerOperations should be temporarily shutdown after oracle failure"
        );
        assertEq(
            borrowerOperations.hasBeenShutDown(),
            false,
            "hasBeenShutDown stays false: not a full market shutdown"
        );

        // 4. Call TroveManager.batchLiquidateTroves with an EMPTY array.
        //    This proves TroveManager is still callable and reaches its own validation.
        uint256[] memory emptyArray;

        vm.expectRevert(TroveManager.EmptyData.selector);
        troveManager.batchLiquidateTroves(emptyArray);

        // This shows:
        // - Oracle failure "shuts down" the branch only for BorrowerOperations (temporary),
        // - but TroveManager logic remains callable and still relies on the (now disabled)
        //   price feed, instead of being consistently blocked under oracle failure.
    }

    /// @notice Oracle failure freezes lastGoodPrice and subsequent fetchPrice() calls keep returning it.
    function test_oracleFailure_freezesPriceAndKeepsReturningIt() public {
        // 1. Baseline: oracle is healthy
        (uint256 priceBefore, bool failBefore) = priceFeed.fetchPrice();
        assertEq(failBefore, false, "pre: no oracle failure initially");

        uint256 lastGoodBefore = priceFeed.lastGoodPrice();
        assertEq(priceBefore, lastGoodBefore, "pre: price matches lastGoodPrice");

        // 2. Force oracle failure via fake L1Read
        _forceOracleFailure();

        // First fetch after failure, HLPriceFeed should:
        // - call borrowerOperations.shutdownFromOracleFailure(...)
        // - set priceFeedDisabled = true
        // - return lastGoodPrice and flag the failure
        (uint256 priceOnFailure, bool failFlag) = priceFeed.fetchPrice();
        assertEq(failFlag, true, "oracle failure must be detected");
        assertEq(
            priceOnFailure,
            lastGoodBefore,
            "failure path returns frozen lastGoodPrice"
        );

        // BorrowerOperations is now in temporary shutdown
        assertEq(
            borrowerOperations.isTemporaryShutdown(),
            true,
            "BorrowerOperations should be temporarily shutdown after oracle failure"
        );
        assertEq(
            borrowerOperations.hasBeenShutDown(),
            false,
            "hasBeenShutDown is still false"
        );

        // 3. Subsequent callers (e.g. TroveManager) see:
        // - priceFeedDisabled == true
        // - fetchPrice() returns lastGoodPrice
        // - and does NOT surface a new failure
        (uint256 priceAfter, bool failAfter) = priceFeed.fetchPrice();
        assertEq(
            failAfter,
            false,
            "after disable, fetchPrice no longer flags failure"
        );
        assertEq(
            priceAfter,
            lastGoodBefore,
            "after disable, fetchPrice keeps returning frozen lastGoodPrice"
        );
    }
}
