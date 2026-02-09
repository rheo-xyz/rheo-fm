// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {CryticAsserts} from "@chimera/CryticAsserts.sol";
import {FixedMaturityLimitOrderHelper} from "@rheo-fm/test/helpers/libraries/FixedMaturityLimitOrderHelper.sol";
import {SetupLocal} from "@rheo-fm/test/invariants/SetupLocal.sol";
import {TargetFunctions} from "@rheo-fm/test/invariants/TargetFunctions.sol";

// echidna test/invariants/crytic/CryticTester.sol --contract CryticTester --config echidna.yaml
// medusa fuzz
contract CryticTester is TargetFunctions, SetupLocal, CryticAsserts {
    constructor() {
        setup();
        // Keep helper library in the compilation set for echidna predeploys.
        FixedMaturityLimitOrderHelper.normalOffer();
    }
}
