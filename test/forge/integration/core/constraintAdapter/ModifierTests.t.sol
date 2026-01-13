// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.30;

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {ConstraintRateAdapter} from "contracts/core/ConstraintRateAdapter.sol";
import {CorkPoolManager} from "contracts/core/CorkPoolManager.sol";
import {IErrors} from "contracts/interfaces/IErrors.sol";
import {MarketId} from "contracts/interfaces/IPoolManager.sol";
import {TransferHelper} from "contracts/libraries/TransferHelper.sol";
import {Test} from "forge-std/Test.sol";

contract ModifierTests is Test {
    ConstraintRateAdapter constraintRateAdapter;
    CorkPoolManager corkPoolManager;

    address alice;
    address defaultAdmin;
    address ensOwner;

    function setUp() public {
        defaultAdmin = makeAddr("defaultAdmin");
        ensOwner = makeAddr("ensOwner");
        alice = makeAddr("alice");

        // ==================== Deploy ConstraintRateAdapter ====================
        address constraintRateAdapterImpl = address(new ConstraintRateAdapter());
        ERC1967Proxy constraintRateAdapterProxy = new ERC1967Proxy(constraintRateAdapterImpl, bytes(""));
        constraintRateAdapter = ConstraintRateAdapter(address(constraintRateAdapterProxy));

        // ==================== Deploy CorkPoolManager ====================
        address corkPoolManagerImpl = address(new CorkPoolManager());
        ERC1967Proxy corkPoolManagerProxy = new ERC1967Proxy(corkPoolManagerImpl, bytes(""));
        corkPoolManager = CorkPoolManager(address(corkPoolManagerProxy));

        constraintRateAdapter.initialize(ensOwner, defaultAdmin);

        vm.startPrank(defaultAdmin);
        constraintRateAdapter.setOnceCorkPoolManager(address(corkPoolManager));
    }

    // ================================ Modifier Tests ================================ //

    function test_onlyCorkPoolManager_ShouldRevert_WhenCalledByNonCorkPoolManager() external {
        vm.startPrank(alice);
        vm.expectRevert(IErrors.NotCorkPoolManager.selector);
        constraintRateAdapter.bootstrap(MarketId.wrap(bytes32("0")));
    }
}
