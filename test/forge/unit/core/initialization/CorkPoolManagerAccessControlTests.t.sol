// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {CorkPoolManager} from "contracts/core/CorkPoolManager.sol";
import {Market, MarketId} from "contracts/interfaces/IPoolManager.sol";
import {BaseTest} from "test/forge/BaseTest.sol";
import {DummyERC20} from "test/forge/mocks/DummyERC20.sol";

contract CorkPoolManagerAccessControlTests is BaseTest {
    address internal unauthorizedUser = makeAddr("unauthorized");

    function test_authorizeUpgrade_onlyDefaultAdminRole() public {
        address newImplementation = address(new CorkPoolManager());

        overridePrank(unauthorizedUser);
        vm.expectRevert();
        corkPoolManager.upgradeToAndCall(newImplementation, "");

        overridePrank(alice);
        vm.expectRevert();
        corkPoolManager.upgradeToAndCall(newImplementation, "");

        overridePrank(bravo);
        corkPoolManager.upgradeToAndCall(newImplementation, "");
    }

    function test_initialize_zeroAddressValidation() public {
        CorkPoolManager implementation = new CorkPoolManager();

        vm.expectRevert(bytes4(keccak256("InvalidParams()")));
        new ERC1967Proxy(
            address(implementation),
            abi.encodeWithSignature(
                "initialize(address,address,address,address,address)",
                address(0), // ensOwner
                bravo,
                address(constraintRateAdapter),
                CORK_PROTOCOL_TREASURY,
                address(whitelistManager)
            )
        );

        vm.expectRevert(bytes4(keccak256("InvalidParams()")));
        new ERC1967Proxy(
            address(implementation),
            abi.encodeWithSignature(
                "initialize(address,address,address,address,address)",
                ensOwner,
                address(0), // admin
                address(constraintRateAdapter),
                CORK_PROTOCOL_TREASURY,
                address(whitelistManager)
            )
        );

        vm.expectRevert(bytes4(keccak256("InvalidParams()")));
        new ERC1967Proxy(
            address(implementation),
            abi.encodeWithSignature(
                "initialize(address,address,address,address,address)",
                ensOwner,
                bravo,
                address(0), // constraintRateAdapter
                CORK_PROTOCOL_TREASURY,
                address(whitelistManager)
            )
        );

        vm.expectRevert(bytes4(keccak256("InvalidParams()")));
        new ERC1967Proxy(
            address(implementation),
            abi.encodeWithSignature(
                "initialize(address,address,address,address,address)",
                ensOwner,
                bravo,
                address(constraintRateAdapter),
                address(0), // treasury
                address(whitelistManager)
            )
        );

        vm.expectRevert(bytes4(keccak256("InvalidParams()")));
        new ERC1967Proxy(
            address(implementation),
            abi.encodeWithSignature(
                "initialize(address,address,address,address,address)",
                ensOwner,
                bravo,
                address(constraintRateAdapter),
                CORK_PROTOCOL_TREASURY,
                address(0) // whitelistManager
            )
        );
    }

    function test_createNewPool_invalidExpiry() public {
        overridePrank(address(defaultCorkController));
        Market memory invalidMarket = Market({
            collateralAsset: address(collateralAsset),
            referenceAsset: address(referenceAsset),
            expiryTimestamp: block.timestamp - 1, // expired
            rateMin: DEFAULT_RATE_MIN,
            rateMax: DEFAULT_RATE_MAX,
            rateChangePerDayMax: DEFAULT_RATE_CHANGE_PER_DAY_MAX,
            rateChangeCapacityMax: DEFAULT_RATE_CHANGE_CAPACITY_MAX,
            rateOracle: address(testOracle)
        });

        vm.expectRevert(bytes4(keccak256("InvalidExpiry()")));
        corkPoolManager.createNewPool(invalidMarket);
    }

    function test_createNewPool_zeroReferenceAsset() public {
        overridePrank(address(defaultCorkController));
        Market memory invalidMarket = Market({
            collateralAsset: address(collateralAsset),
            referenceAsset: address(0),
            expiryTimestamp: block.timestamp + 1 days,
            rateMin: DEFAULT_RATE_MIN,
            rateMax: DEFAULT_RATE_MAX,
            rateChangePerDayMax: DEFAULT_RATE_CHANGE_PER_DAY_MAX,
            rateChangeCapacityMax: DEFAULT_RATE_CHANGE_CAPACITY_MAX,
            rateOracle: address(testOracle)
        });

        vm.expectRevert();
        corkPoolManager.createNewPool(invalidMarket);
    }

    function test_createNewPool_zeroCollateralAsset() public {
        overridePrank(address(defaultCorkController));
        Market memory invalidMarket = Market({
            collateralAsset: address(0),
            referenceAsset: address(referenceAsset),
            expiryTimestamp: block.timestamp + 1 days,
            rateMin: DEFAULT_RATE_MIN,
            rateMax: DEFAULT_RATE_MAX,
            rateChangePerDayMax: DEFAULT_RATE_CHANGE_PER_DAY_MAX,
            rateChangeCapacityMax: DEFAULT_RATE_CHANGE_CAPACITY_MAX,
            rateOracle: address(testOracle)
        });

        vm.expectRevert();
        corkPoolManager.createNewPool(invalidMarket);
    }

    function test_createNewPool_sameAssets() public {
        overridePrank(address(defaultCorkController));
        Market memory invalidMarket = Market({
            collateralAsset: address(collateralAsset),
            referenceAsset: address(collateralAsset), // same as collateral
            expiryTimestamp: block.timestamp + 1 days,
            rateMin: DEFAULT_RATE_MIN,
            rateMax: DEFAULT_RATE_MAX,
            rateChangePerDayMax: DEFAULT_RATE_CHANGE_PER_DAY_MAX,
            rateChangeCapacityMax: DEFAULT_RATE_CHANGE_CAPACITY_MAX,
            rateOracle: address(testOracle)
        });

        vm.expectRevert(bytes4(keccak256("InvalidAddress()")));
        corkPoolManager.createNewPool(invalidMarket);
    }

    function test_createNewPool_zeroRateOracle() public {
        overridePrank(address(defaultCorkController));
        Market memory invalidMarket = Market({
            collateralAsset: address(collateralAsset),
            referenceAsset: address(referenceAsset),
            expiryTimestamp: block.timestamp + 1 days,
            rateMin: DEFAULT_RATE_MIN,
            rateMax: DEFAULT_RATE_MAX,
            rateChangePerDayMax: DEFAULT_RATE_CHANGE_PER_DAY_MAX,
            rateChangeCapacityMax: DEFAULT_RATE_CHANGE_CAPACITY_MAX,
            rateOracle: address(0)
        });

        vm.expectRevert(bytes4(keccak256("ZeroAddress()")));
        corkPoolManager.createNewPool(invalidMarket);
    }

    function test_createNewPool_invalidCollateralDecimals() public {
        overridePrank(address(defaultCorkController));
        DummyERC20 invalidCollateral = new DummyERC20("Invalid", "INV", 19);

        Market memory invalidMarket = Market({
            collateralAsset: address(invalidCollateral),
            referenceAsset: address(referenceAsset),
            expiryTimestamp: block.timestamp + 1 days,
            rateMin: DEFAULT_RATE_MIN,
            rateMax: DEFAULT_RATE_MAX,
            rateChangePerDayMax: DEFAULT_RATE_CHANGE_PER_DAY_MAX,
            rateChangeCapacityMax: DEFAULT_RATE_CHANGE_CAPACITY_MAX,
            rateOracle: address(testOracle)
        });

        vm.expectRevert(bytes4(keccak256("InvalidParams()")));
        corkPoolManager.createNewPool(invalidMarket);
    }

    function test_createNewPool_invalidReferenceDecimals() public {
        overridePrank(address(defaultCorkController));
        DummyERC20 invalidReference = new DummyERC20("Invalid", "INV", 19);

        Market memory invalidMarket = Market({
            collateralAsset: address(collateralAsset),
            referenceAsset: address(invalidReference),
            expiryTimestamp: block.timestamp + 1 days,
            rateMin: DEFAULT_RATE_MIN,
            rateMax: DEFAULT_RATE_MAX,
            rateChangePerDayMax: DEFAULT_RATE_CHANGE_PER_DAY_MAX,
            rateChangeCapacityMax: DEFAULT_RATE_CHANGE_CAPACITY_MAX,
            rateOracle: address(testOracle)
        });

        vm.expectRevert(bytes4(keccak256("InvalidParams()")));
        corkPoolManager.createNewPool(invalidMarket);
    }

    function test_createNewPool_invalidRateRange() public {
        overridePrank(address(defaultCorkController));
        Market memory invalidMarket = Market({
            collateralAsset: address(collateralAsset),
            referenceAsset: address(referenceAsset),
            expiryTimestamp: block.timestamp + 1 days,
            rateMin: DEFAULT_RATE_MAX, // min > max
            rateMax: DEFAULT_RATE_MIN,
            rateChangePerDayMax: DEFAULT_RATE_CHANGE_PER_DAY_MAX,
            rateChangeCapacityMax: DEFAULT_RATE_CHANGE_CAPACITY_MAX,
            rateOracle: address(testOracle)
        });

        vm.expectRevert(bytes4(keccak256("InvalidParams()")));
        corkPoolManager.createNewPool(invalidMarket);
    }
}
