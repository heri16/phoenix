// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.30;

import {IRateOracle} from "contracts/interfaces/IRateOracle.sol";
import {WrapperRateConsumer} from "contracts/periphery/WrapperRateConsumer.sol";
import {Test} from "forge-std/Test.sol";
import {MorphoOracleMock} from "test/forge/mocks/MorphoOracleMock.sol";

contract WrapperRateConsumerTests is Test {
    MorphoOracleMock public morphoOracle;
    WrapperRateConsumer public wrapper;

    function setUp() public {
        morphoOracle = new MorphoOracleMock();

        // arbitrary price first so that it doesn't fail on creation
        morphoOracle.setPrice(1 ether);
    }

    // ============ Constructor Tests ============

    function testConstructorRevertsOnZeroAddress() public {
        vm.expectRevert(IRateOracle.ZeroAddress.selector);
        new WrapperRateConsumer(address(0), 18, 18);
    }

    function testConstructorRevertsOnZeroPrice() public {
        morphoOracle.setPrice(0);

        vm.expectRevert(IRateOracle.InvalidRate.selector);
        new WrapperRateConsumer(address(morphoOracle), 18, 18);
    }

    function testConstructorRevertsOnPrecisionLoss() public {
        // since it scales up to 36, this would round down to 0
        morphoOracle.setPrice(1e17);

        vm.expectRevert(IRateOracle.InvalidRate.selector);
        new WrapperRateConsumer(address(morphoOracle), 18, 18);
    }

    function testConstructorSetsCorrectOracle() public {
        wrapper = new WrapperRateConsumer(address(morphoOracle), 18, 6);
        assertEq(address(wrapper.MORPHO_ORACLE()), address(morphoOracle));
    }

    function testConstructorUsesTokenDecimalsWhenNoVaults() public {
        // No vaults set (defaults to address(0))
        wrapper = new WrapperRateConsumer(address(morphoOracle), 18, 6);
        // Should use provided token decimals
        assertEq(wrapper.BASE_DECIMALS(), 18);
        assertEq(wrapper.QUOTE_DECIMALS(), 6);
    }

    // ============ Decimals Tests ============

    function testDecimalsWhenBaseGreaterThanQuote() public {
        wrapper = new WrapperRateConsumer(address(morphoOracle), 18, 6);
        assertEq(wrapper.BASE_DECIMALS(), 18);
        assertEq(wrapper.QUOTE_DECIMALS(), 6);
    }

    function testDecimalsWhenQuoteGreaterThanBase() public {
        morphoOracle.setPrice(1e30);

        wrapper = new WrapperRateConsumer(address(morphoOracle), 6, 18);
        assertEq(wrapper.BASE_DECIMALS(), 6);
        assertEq(wrapper.QUOTE_DECIMALS(), 18);
    }

    function testDecimalsWhenEqual() public {
        wrapper = new WrapperRateConsumer(address(morphoOracle), 18, 18);
        assertEq(wrapper.BASE_DECIMALS(), 18);
        assertEq(wrapper.QUOTE_DECIMALS(), 18);
    }

    // ============ Rate Function Tests ============

    function testRateWithBaseGreaterThanQuote() public {
        // ETH (18 decimals) / USDC (6 decimals)
        // BASE_DECIMALS=18, QUOTE_DECIMALS=6
        wrapper = new WrapperRateConsumer(address(morphoOracle), 18, 6);

        uint256 morphoPrice = 1e24;
        morphoOracle.setPrice(morphoPrice);

        uint256 expectedRate = 1e18;
        assertEq(wrapper.rate(), expectedRate);
    }

    function testRateWithQuoteGreaterThanBase() public {
        uint256 morphoPrice = 1e48;
        morphoOracle.setPrice(morphoPrice);

        // USDC (6 decimals) / ETH (18 decimals)
        // BASE_DECIMALS=6, QUOTE_DECIMALS=18
        wrapper = new WrapperRateConsumer(address(morphoOracle), 6, 18);

        uint256 expectedRate = 1e18;
        assertEq(wrapper.rate(), expectedRate);
    }

    function testRateWithEqualDecimals() public {
        // Same decimals (18/18)
        wrapper = new WrapperRateConsumer(address(morphoOracle), 18, 18);

        // Morpho price for 1 stETH = 1 ETH would be:
        // 1 * 10^(36 + 18 - 18) = 1 * 10^36
        uint256 morphoPrice = 1 * 10 ** 36;
        morphoOracle.setPrice(morphoPrice);

        // After normalization: morphoPrice (no change, equal decimals)
        // After /1e18: 1 * 10^36 / 10^18 = 1 * 10^18
        uint256 expectedRate = 1 * 10 ** 18;
        assertEq(wrapper.rate(), expectedRate);
    }

    // ============ Edge Case Tests ============

    function testZeroPrice() public {
        wrapper = new WrapperRateConsumer(address(morphoOracle), 18, 18);
        morphoOracle.setPrice(0);

        assertEq(wrapper.rate(), 0);
    }

    function testVeryLargePrice() public {
        wrapper = new WrapperRateConsumer(address(morphoOracle), 18, 18);
        // Large but reasonable price
        uint256 morphoPrice = type(uint128).max;
        morphoOracle.setPrice(morphoPrice);
        assertEq(wrapper.rate(), morphoPrice / 1 ether);
    }

    // ============ Fuzz Tests ============

    function testFuzzRateWithBaseGreaterThanQuote(uint8 baseDec, uint8 quoteDec) public {
        baseDec = uint8(bound(baseDec, 2, 18)); // Start from 2 to ensure we can have quoteDec < baseDec
        quoteDec = uint8(bound(quoteDec, 1, baseDec - 1));

        vm.assume(baseDec > quoteDec);

        wrapper = new WrapperRateConsumer(address(morphoOracle), baseDec, quoteDec);

        // Calculate Morpho price format
        uint256 morphoPrice = 1 * 10 ** (36 + quoteDec - baseDec);
        morphoOracle.setPrice(morphoPrice);

        uint256 expectedRate = 1e18;

        assertEq(wrapper.rate(), expectedRate);
    }

    function testFuzzRateWithQuoteGreaterThanBase(uint8 baseDec, uint8 quoteDec) public {
        quoteDec = uint8(bound(quoteDec, 2, 18));
        baseDec = uint8(bound(baseDec, 1, quoteDec - 1));

        vm.assume(quoteDec > baseDec);

        // Calculate Morpho price format
        uint256 morphoPrice = 1 * 10 ** (36 + quoteDec - baseDec);
        morphoOracle.setPrice(morphoPrice);

        wrapper = new WrapperRateConsumer(address(morphoOracle), baseDec, quoteDec);

        uint256 expectedRate = 1e18;

        assertEq(wrapper.rate(), expectedRate);
    }
}
