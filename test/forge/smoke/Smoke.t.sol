pragma solidity ^0.8.30;

import {ERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {CorkConfig} from "contracts/core/CorkConfig.sol";
import {CorkPool} from "contracts/core/CorkPool.sol";
import {MarketId} from "contracts/libraries/Market.sol";
import {TransferHelper} from "contracts/libraries/TransferHelper.sol";
import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {EnvGetters, Helper} from "test/forge/Helper.sol";

struct MarketObj {
    address collateralAsset;
    address referenceAsset;
    uint256 expiryTimestamp;
    uint256 arp;
    uint256 exchangeRate;
    uint256 redemptionFee;
    uint256 unwindSwapFee;
    uint256 ammBaseFee;
    address caller;
    address paHolder;
}

contract SimulateScript is Test {
    using SafeERC20 for IERC20;

    CorkConfig public config = CorkConfig(0xF0DA8927Df8D759d5BA6d3d714B1452135D99cFC);
    CorkPool public corkPool = CorkPool(0xCCd90F6435dd78C4ECCED1FA4db0D7242548a2a9);
    address public exchangeProvider = 0x7b285955DdcbAa597155968f9c4e901bb4c99263;

    address constant weth = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address constant wstETH = 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0;
    address constant weETH = 0xCd5fE23C85820F7B72D0926FC9b05b43E359b7ee;
    address constant sUSDS = 0xa3931d71877C0E7a3148CB7Eb4463524FEc27fbD;
    address constant USDe = 0x4c9EDD5852cd905f086C759E8383e09bff1E68B3;
    address constant sUSDe = 0x9D39A5DE30e57443BfF2A8307A4256c8797A3497;
    address constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;

    uint256 constant weth_wstETH_Expiry = 90 days;
    uint256 constant wstETH_weETH_Expiry = 90 days;
    uint256 constant sUSDS_USDe_Expiry = 90 days;
    uint256 constant sUSDe_USDT_Expiry = 90 days;

    uint256 constant weth_wstETH_ARP = 0.3698630135 ether;
    uint256 constant wstETH_weETH_ARP = 0.4931506847 ether;
    uint256 constant sUSDS_USDe_ARP = 0.9863013697 ether;
    uint256 constant sUSDe_USDT_ARP = 0.4931506847 ether;

    uint256 constant weth_wstETH_ExchangeRate = 1.192057609 ether;
    uint256 constant wstETH_weETH_ExchangeRate = 0.8881993472 ether;
    uint256 constant sUSDS_USDe_ExchangeRate = 0.9689922481 ether;
    uint256 constant sUSDe_USDT_ExchangeRate = 0.8680142355 ether;

    uint256 constant weth_wstETH_RedemptionFee = 0.2 ether;
    uint256 constant wstETH_weETH_RedemptionFee = 0.2 ether;
    uint256 constant sUSDS_USDe_RedemptionFee = 0.2 ether;
    uint256 constant sUSDe_USDT_RedemptionFee = 0.2 ether;

    uint256 constant weth_wstETH_unwindSwapFee = 0.23 ether;
    uint256 constant wstETH_weETH_unwindSwapFee = 0.3 ether;
    uint256 constant sUSDS_USDe_unwindSwapFee = 0.61 ether;
    uint256 constant sUSDe_USDT_unwindSwapFee = 0.3 ether;

    uint256 constant weth_wstETH_AmmBaseFee = 0.018 ether;
    uint256 constant wstETH_weETH_AmmBaseFee = 0.025 ether;
    uint256 constant sUSDS_USDe_AmmBaseFee = 0.049 ether;
    uint256 constant sUSDe_USDT_AmmBaseFee = 0.025 ether;

    MarketObj weth_wstETH_market = MarketObj(weth, wstETH, weth_wstETH_Expiry, weth_wstETH_ARP, weth_wstETH_ExchangeRate, weth_wstETH_RedemptionFee, weth_wstETH_unwindSwapFee, weth_wstETH_AmmBaseFee, 0xF04a5cC80B1E94C69B48f5ee68a08CD2F09A7c3E, 0x12B54025C112Aa61fAce2CDB7118740875A566E9);
    MarketObj wstETH_weETH_market = MarketObj(wstETH, weETH, wstETH_weETH_Expiry, wstETH_weETH_ARP, wstETH_weETH_ExchangeRate, wstETH_weETH_RedemptionFee, wstETH_weETH_unwindSwapFee, wstETH_weETH_AmmBaseFee, 0x12B54025C112Aa61fAce2CDB7118740875A566E9, 0xBdfa7b7893081B35Fb54027489e2Bc7A38275129);
    MarketObj sUSDS_USDe_market = MarketObj(sUSDS, USDe, sUSDS_USDe_Expiry, sUSDS_USDe_ARP, sUSDS_USDe_ExchangeRate, sUSDS_USDe_RedemptionFee, sUSDS_USDe_unwindSwapFee, sUSDS_USDe_AmmBaseFee, 0x2d4d2A025b10C09BDbd794B4FCe4F7ea8C7d7bB4, 0x9D39A5DE30e57443BfF2A8307A4256c8797A3497);
    MarketObj sUSDe_USDT_market = MarketObj(sUSDe, USDT, sUSDe_USDT_Expiry, sUSDe_USDT_ARP, sUSDe_USDT_ExchangeRate, sUSDe_USDT_RedemptionFee, sUSDe_USDT_unwindSwapFee, sUSDe_USDT_AmmBaseFee, 0x3Ee118EFC826d30A29645eAf3b2EaaC9E8320185, 0xF977814e90dA44bFA03b6295A0616a897441aceC);

    EnvGetters internal env = new EnvGetters();

    function setUp() public {
        string memory forkUrl = envStringNoRevert("FORK_URL");
        uint256 forkBlock = envUintNoRevert("FORK_BLOCK");

        if (forkBlock == 0 || keccak256(abi.encodePacked(forkUrl)) == keccak256("")) vm.skip(true, "no fork url and block was found");

        vm.createSelectFork(forkUrl, forkBlock);
    }

    function envStringNoRevert(string memory key) internal view returns (string memory) {
        try env.envString(key) returns (string memory value) {
            return value;
        } catch {
            return "";
        }
    }

    function envUintNoRevert(string memory key) internal view returns (uint256) {
        try env.envUint(key) returns (uint256 value) {
            return value;
        } catch {
            return 0;
        }
    }

    function test_allMarket() public {
        address impl = address(new CorkPool());
        bytes memory implCode = impl.code;

        // vm.etch(address(corkPool), implCode);

        vm.pauseGasMetering();

        string[4] memory marketName = ["weth_wstETH", "wstETH_weETH", "sUSDS_USDe", "sUSDe_USDT"];
        MarketObj[4] memory marketDetails = [weth_wstETH_market, wstETH_weETH_market, sUSDS_USDe_market, sUSDe_USDT_market];
        // Market[1] memory markets = [weth_wstETH_market];

        for (uint256 i = 0; i < marketDetails.length; i++) {
            console.log("-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-");
            console.log("Market: ", marketName[i]);

            MarketObj memory market = marketDetails[i];

            if (market.referenceAsset == USDT) {
                // skip usdt check since foundry is throwing invalid opcode for it
                console.log("Skipping USDT market, Foundry is throwing invalid opcode for it");
                continue;
            } else {
                vm.startPrank(market.paHolder);
                SafeERC20.safeTransfer(IERC20(market.referenceAsset), market.caller, 0.2 ether);

                vm.startPrank(market.caller);
            }

            MarketId marketId = corkPool.getId(market.referenceAsset, market.collateralAsset, market.expiryTimestamp, exchangeProvider);

            (address principalToken, address swapToken) = corkPool.shares(marketId);

            uint256 corkPoolDepositAmt = 0.1 ether;
            console.log("Depositing %s Collateral Asset", corkPoolDepositAmt);
            deposit(market, marketId, corkPoolDepositAmt);

            uint256 swapAmt = 0.001 ether;
            console.log("swaping %s Collateral Asset with Swap Token", swapAmt);
            swap(market, marketId, swapAmt, swapToken);

            console.log("Returning %s Collateral Asset with Principal Token and Swap Token", swapAmt);
            unwindDeposit(market, marketId, swapAmt, swapToken, principalToken);

            console.log("-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-");
        }
    }

    function deposit(MarketObj memory market, MarketId marketId, uint256 depositAmt) public {
        depositAmt = convertToDecimals(market.collateralAsset, depositAmt);
        ERC20(market.collateralAsset).approve(address(corkPool), depositAmt);
        (, address currentCaller,) = vm.readCallers();
        corkPool.deposit(marketId, depositAmt, currentCaller);
    }

    function swap(MarketObj memory market, MarketId marketId, uint256 swapAmt, address swapToken) public {
        swapAmt = convertToDecimals(market.referenceAsset, swapAmt);
        IERC20(market.referenceAsset).safeIncreaseAllowance(address(corkPool), swapAmt);

        uint256 decimals = ERC20(swapToken).decimals();
        ERC20(swapToken).approve(address(corkPool), swapAmt * 10 ** decimals);

        corkPool.exercise(marketId, 0, swapAmt, market.caller, 0, type(uint256).max);
    }

    function unwindDeposit(MarketObj memory market, MarketId marketId, uint256 swapAmt, address swapToken, address principalToken) public {
        swapAmt = convertToDecimals(swapToken, swapAmt);
        ERC20(swapToken).approve(address(corkPool), swapAmt);
        ERC20(principalToken).approve(address(corkPool), swapAmt);
        corkPool.unwindDeposit(marketId, swapAmt);
    }

    function convertToDecimals(address token, uint256 value) public view returns (uint256) {
        return TransferHelper.fixedToTokenNativeDecimals(value, token);
    }
}

interface Issue {
    function issue(uint256 _amount) external;
}
