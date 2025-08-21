// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";

import {ICompositeRateOracle} from "contracts/interfaces/ICompositeRateOracle.sol";
import {CompositeRateOracle, Math} from "contracts/periphery/CompositeRateOracle.sol";

import {CompositeRateOracleHelper as Helper, MinimalAggregatorV3Interface} from "test/helpers/CompositeRateOracle.sol";
import {btcEthFeed, btcUsdFeed, daiEthFeed, ethUsdFeed, feedZero, sDaiVault, sfrxEthVault, stEthEthFeed, usdcEthFeed, usdcUsdFeed, vaultZero, wBtcBtcFeed} from "test/helpers/Constants.sol";
import {ChainlinkAggregatorMock} from "test/mocks/ChainlinkAggregatorMock.sol";

contract CompositeRateOracleTest is Test {
    using Math for uint256;

    function setUp() public {
        string memory forkUrl = vm.envOr("FORK_URL", string(""));
        if (bytes(forkUrl).length == 0) vm.skip(true, "FORK_URL not set");
        vm.createSelectFork(forkUrl);
        // require(block.chainid == 1, "chain isn't Ethereum");
    }

    function testOracleWbtcUsdc() public {
        require(block.chainid == 1, "test only runs on Ethereum mainnet");

        CompositeRateOracle oracle = new CompositeRateOracle(Helper.makeSourceParamsArr(vaultZero, 1, wBtcBtcFeed, btcUsdFeed, 8, vaultZero, 1, usdcUsdFeed, feedZero, 6));
        (, int256 firstBaseAnswer,,,) = wBtcBtcFeed.latestRoundData();
        (, int256 secondBaseAnswer,,,) = btcUsdFeed.latestRoundData();
        (, int256 quoteAnswer,,,) = usdcUsdFeed.latestRoundData();
        assertEq(oracle.price(), (uint256(firstBaseAnswer) * uint256(secondBaseAnswer) * 10 ** (36 + 8 + 6 - 8 - 8 - 8)) / uint256(quoteAnswer));
    }

    function testOracleUsdcWbtc() public {
        require(block.chainid == 1, "test only runs on Ethereum mainnet");

        CompositeRateOracle oracle = new CompositeRateOracle(Helper.makeSourceParamsArr(vaultZero, 1, usdcUsdFeed, feedZero, 6, vaultZero, 1, wBtcBtcFeed, btcUsdFeed, 8));
        (, int256 baseAnswer,,,) = usdcUsdFeed.latestRoundData();
        (, int256 firstQuoteAnswer,,,) = wBtcBtcFeed.latestRoundData();
        (, int256 secondQuoteAnswer,,,) = btcUsdFeed.latestRoundData();
        assertEq(oracle.price(), (uint256(baseAnswer) * 10 ** (36 + 8 + 8 + 8 - 6 - 8)) / (uint256(firstQuoteAnswer) * uint256(secondQuoteAnswer)));
    }

    function testOracleWbtcEth() public {
        require(block.chainid == 1, "test only runs on Ethereum mainnet");

        CompositeRateOracle oracle = new CompositeRateOracle(Helper.makeSourceParamsArr(vaultZero, 1, wBtcBtcFeed, btcEthFeed, 8, vaultZero, 1, feedZero, feedZero, 18));
        (, int256 firstBaseAnswer,,,) = wBtcBtcFeed.latestRoundData();
        (, int256 secondBaseAnswer,,,) = btcEthFeed.latestRoundData();
        assertEq(oracle.price(), (uint256(firstBaseAnswer) * uint256(secondBaseAnswer) * 10 ** (36 + 18 - 8 - 8 - 18)));
    }

    function testOracleStEthUsdc() public {
        require(block.chainid == 1, "test only runs on Ethereum mainnet");

        CompositeRateOracle oracle = new CompositeRateOracle(Helper.makeSourceParamsArr(vaultZero, 1, stEthEthFeed, feedZero, 18, vaultZero, 1, usdcEthFeed, feedZero, 6));
        (, int256 baseAnswer,,,) = stEthEthFeed.latestRoundData();
        (, int256 quoteAnswer,,,) = usdcEthFeed.latestRoundData();
        assertEq(oracle.price(), uint256(baseAnswer) * 10 ** (36 + 18 + 6 - 18 - 18) / uint256(quoteAnswer));
    }

    function testOracleEthUsd() public {
        require(block.chainid == 1, "test only runs on Ethereum mainnet");

        CompositeRateOracle oracle = new CompositeRateOracle(Helper.makeSourceParamsArr(vaultZero, 1, ethUsdFeed, feedZero, 18, vaultZero, 1, feedZero, feedZero, 0));
        (, int256 expectedPrice,,,) = ethUsdFeed.latestRoundData();
        assertEq(oracle.price(), uint256(expectedPrice) * 10 ** (36 - 18 - 8));
    }

    function testOracleStEthEth() public {
        require(block.chainid == 1, "test only runs on Ethereum mainnet");

        CompositeRateOracle oracle = new CompositeRateOracle(Helper.makeSourceParamsArr(vaultZero, 1, stEthEthFeed, feedZero, 18, vaultZero, 1, feedZero, feedZero, 18));
        (, int256 expectedPrice,,,) = stEthEthFeed.latestRoundData();
        assertEq(oracle.price(), uint256(expectedPrice) * 10 ** (36 + 18 - 18 - 18));
        assertApproxEqRel(oracle.price(), 1e36, 0.01 ether);
    }

    function testOracleEthStEth() public {
        require(block.chainid == 1, "test only runs on Ethereum mainnet");

        CompositeRateOracle oracle = new CompositeRateOracle(Helper.makeSourceParamsArr(vaultZero, 1, feedZero, feedZero, 18, vaultZero, 1, stEthEthFeed, feedZero, 18));
        (, int256 expectedPrice,,,) = stEthEthFeed.latestRoundData();
        assertEq(oracle.price(), 10 ** (36 + 18 + 18 - 18) / uint256(expectedPrice));
        assertApproxEqRel(oracle.price(), 1e36, 0.01 ether);
    }

    function testOracleUsdcUsd() public {
        require(block.chainid == 1, "test only runs on Ethereum mainnet");

        CompositeRateOracle oracle = new CompositeRateOracle(Helper.makeSourceParamsArr(vaultZero, 1, usdcUsdFeed, feedZero, 6, vaultZero, 1, feedZero, feedZero, 0));
        assertApproxEqRel(oracle.price(), 1e36 / 1e6, 0.01 ether);
    }

    function testNegativeAnswer(int256 price) public {
        require(block.chainid == 1, "test only runs on Ethereum mainnet");

        price = bound(price, type(int256).min, -1);
        ChainlinkAggregatorMock aggregator = new ChainlinkAggregatorMock();
        CompositeRateOracle oracle = new CompositeRateOracle(Helper.makeSourceParamsArr(vaultZero, 1, MinimalAggregatorV3Interface(address(aggregator)), feedZero, 18, vaultZero, 1, feedZero, feedZero, 0));
        aggregator.setAnwser(price);
        vm.expectRevert(bytes("negative answer"));
        oracle.price();
    }

    function testSDaiEthOracle() public {
        require(block.chainid == 1, "test only runs on Ethereum mainnet");

        CompositeRateOracle oracle = new CompositeRateOracle(Helper.makeSourceParamsArr(sDaiVault, 1e18, daiEthFeed, feedZero, 18, vaultZero, 1, feedZero, feedZero, 18));
        (, int256 expectedPrice,,,) = daiEthFeed.latestRoundData();
        assertEq(oracle.price(), sDaiVault.convertToAssets(1e18) * uint256(expectedPrice) * 10 ** (36 + 18 + 0 - 18 - 18 - 18));
    }

    function testSDaiUsdcOracle() public {
        require(block.chainid == 1, "test only runs on Ethereum mainnet");

        CompositeRateOracle oracle = new CompositeRateOracle(Helper.makeSourceParamsArr(sDaiVault, 1e18, daiEthFeed, feedZero, 18, vaultZero, 1, usdcEthFeed, feedZero, 6));
        (, int256 baseAnswer,,,) = daiEthFeed.latestRoundData();
        (, int256 quoteAnswer,,,) = usdcEthFeed.latestRoundData();
        assertEq(oracle.price(), sDaiVault.convertToAssets(1e18) * uint256(baseAnswer) * 10 ** (36 + 6 + 18 - 18 - 18 - 18) / uint256(quoteAnswer));
        // DAI has 12 more decimals than USDC.
        uint256 expectedPrice = 10 ** (36 - 12);
        // Admit a 50% interest gain before breaking this test.
        uint256 deviation = 0.5 ether;
        assertApproxEqRel(oracle.price(), expectedPrice, deviation);
    }

    function testEthSDaiOracle() public {
        require(block.chainid == 1, "test only runs on Ethereum mainnet");

        CompositeRateOracle oracle = new CompositeRateOracle(Helper.makeSourceParamsArr(vaultZero, 1, feedZero, feedZero, 18, sDaiVault, 1e18, daiEthFeed, feedZero, 18));
        (, int256 quoteAnswer,,,) = daiEthFeed.latestRoundData();
        assertEq(
            oracle.price(),
            // 1e(36 + dQ1 + fpQ1 + fpQ2 - dB1 - fpB1 - fpB2) * qCS / bCS
            10 ** (36 + 18 + 18 + 0 - 18 - 0 - 0) * 1e18 / (sDaiVault.convertToAssets(1e18) * uint256(quoteAnswer))
        );
    }

    function testUsdcSDaiOracle() public {
        require(block.chainid == 1, "test only runs on Ethereum mainnet");

        CompositeRateOracle oracle = new CompositeRateOracle(Helper.makeSourceParamsArr(vaultZero, 1, usdcEthFeed, feedZero, 6, sDaiVault, 1e18, daiEthFeed, feedZero, 18));
        (, int256 baseAnswer,,,) = usdcEthFeed.latestRoundData();
        (, int256 quoteAnswer,,,) = daiEthFeed.latestRoundData();
        // 1e(36 + dQ1 + fpQ1 + fpQ2 - dB1 - fpB1 - fpB2) * qCS / bCS
        uint256 scaleFactor = 10 ** (36 + 18 + 18 + 0 - 6 - 18 - 0) * 1e18;
        assertEq(oracle.price(), scaleFactor.mulDiv(uint256(baseAnswer), (sDaiVault.convertToAssets(1e18) * uint256(quoteAnswer))));
        // DAI has 12 more decimals than USDC.
        uint256 expectedPrice = 10 ** (36 + 12);
        // Admit a 50% interest gain before breaking this test.
        uint256 deviation = 0.33 ether;
        assertApproxEqRel(oracle.price(), expectedPrice, deviation);
    }

    function testSfrxEthSDaiOracle() public {
        require(block.chainid == 1, "test only runs on Ethereum mainnet");

        CompositeRateOracle oracle = new CompositeRateOracle(Helper.makeSourceParamsArr(sfrxEthVault, 1e18, feedZero, feedZero, 18, sDaiVault, 1e18, daiEthFeed, feedZero, 18));
        (, int256 quoteAnswer,,,) = daiEthFeed.latestRoundData();
        // 1e(36 + dQ1 + fpQ1 + fpQ2 - dB1 - fpB1 - fpB2) * qCS / bCS
        uint256 scaleFactor = 10 ** (36 + 18 + 18 + 0 - 18 - 0 - 0) * 1e18 / 1e18;
        assertEq(oracle.price(), scaleFactor.mulDiv(sfrxEthVault.convertToAssets(1e18), (sDaiVault.convertToAssets(1e18) * uint256(quoteAnswer))));
    }

    function testConstructorZeroVaultConversionSample() public {
        require(block.chainid == 1, "test only runs on Ethereum mainnet");

        vm.expectRevert(ICompositeRateOracle.VaultConversionSampleIsZero.selector);
        new CompositeRateOracle(Helper.makeSourceParamsArr(sDaiVault, 0, daiEthFeed, feedZero, 18, vaultZero, 1, usdcEthFeed, feedZero, 6));
        vm.expectRevert(ICompositeRateOracle.VaultConversionSampleIsZero.selector);
        new CompositeRateOracle(Helper.makeSourceParamsArr(vaultZero, 1, daiEthFeed, feedZero, 18, sDaiVault, 0, usdcEthFeed, feedZero, 6));
    }

    function testConstructorVaultZeroNotOneSample(uint256 vaultConversionSample) public {
        require(block.chainid == 1, "test only runs on Ethereum mainnet");

        vaultConversionSample = bound(vaultConversionSample, 2, type(uint256).max);

        vm.expectRevert(ICompositeRateOracle.VaultConversionSampleIsNotOne.selector);
        new CompositeRateOracle(Helper.makeSourceParamsArr(vaultZero, 0, daiEthFeed, feedZero, 18, vaultZero, 1, usdcEthFeed, feedZero, 6));
        vm.expectRevert(ICompositeRateOracle.VaultConversionSampleIsNotOne.selector);
        new CompositeRateOracle(Helper.makeSourceParamsArr(vaultZero, 1, daiEthFeed, feedZero, 18, vaultZero, 0, usdcEthFeed, feedZero, 6));
    }
}
