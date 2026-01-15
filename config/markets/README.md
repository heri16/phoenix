# Market Oracle Configurations

This directory contains market-specific oracle configurations for the Cork Protocol.

## Directory Structure

```
config/markets/
├── dev/                    # Development environment configs
│   ├── vbUSDC-sUSDe-00.toml
│   └── vbUSDC-sUSDe-01.toml
├── prod/                   # Production environment configs
│   ├── vbUSDC-sUSDe-00.toml
│   └── wstETH-wETH-01.toml
├── README.md
└── TEMPLATE-market-config.toml
```

## File Naming Convention

Market config files follow this pattern:
```
{raToken}-{caToken}-{id}.toml
```

**Components:**
- `{raToken}`: Reference Asset symbol (e.g., vbUSDC, wstETH, cbBTC)
- `{caToken}`: Collateral Asset symbol (e.g., sUSDe, wETH, BTC)
- `{id}`: Two-digit market identifier (00, 01, 02, etc.)

**Examples:**
- `vbUSDC-sUSDe-00.toml` - First vbUSDC/sUSDe market
- `wstETH-wETH-01.toml` - Second wstETH/wETH market
- `cbBTC-BTC-00.toml` - First cbBTC/BTC market

## Configuration Structure

Each market config file contains:

### 1. Network Sections
Separate sections for each chain (e.g., `[sepolia]`, `[mainnet]`, or by chain ID)

### 2. Required Fields

**Address Section:**
- `create2_deployer` - CREATE2 deployer address (typically Safe Singleton Factory)
- `base_vault` - Base token vault address (or 0x0 if none)
- `base_feed_1` - Base token price feed #1
- `base_feed_2` - Base token price feed #2 (or 0x0 if none)
- `quote_vault` - Quote token vault address (or 0x0 if none)
- `quote_feed_1` - Quote token price feed #1
- `quote_feed_2` - Quote token price feed #2 (or 0x0 if none)
- `morpho_oracle_factory` - Morpho oracle factory address

**Bytes32 Section:**
- `morpho_oracle_salt` - Salt for Morpho oracle deployment
- `wrapper_rate_consumer_salt` - Salt for WrapperRateConsumer deployment

**Uint Section:**
- `base_vault_conversion_sample` - Conversion rate sample for base vault
- `base_token_decimals` - Base token decimals
- `quote_vault_conversion_sample` - Conversion rate sample for quote vault
- `quote_token_decimals` - Quote token decimals

For morpho oracle details, see[https://github.com/morpho-org/morpho-blue-oracles/blob/main/README.md](https://github.com/morpho-org/morpho-blue-oracles/blob/main/README.md) and [https://docs.morpho.org/curate/tutorials-market-v1/deploying-oracle#find-the-factory-contract](https://docs.morpho.org/curate/tutorials-market-v1/deploying-oracle#find-the-factory-contract).

### 3. Optional Fields

**Expected Addresses (for production verification):**
- `expected_morpho_oracle` - Expected MorphoChainlinkOracleV2 address
- `expected_wrapper_rate_consumer` - Expected WrapperRateConsumer address

**Deployed Addresses (auto-populated by script):**
- `deployed_morpho_oracle` - Deployed MorphoChainlinkOracleV2 address
- `deployed_wrapper_rate_consumer` - Deployed WrapperRateConsumer address

**Deployment Tracking (auto-populated by script):**
- `deployment_block` - Block number of rate oracle deployment

### 4. Multi-Network Support

You can configure the same market for multiple networks in one file:
```toml
[sepolia]
[sepolia.address]
# ... sepolia config ...

[mainnet]
[mainnet.address]
# ... mainnet config ...
```

## Deployment Usage

Deploy and verify oracles using mise tasks (recommended) or raw forge commands.

### Using mise (Recommended)

```bash
# Deploy oracle (dev environment - default)
mise deploy-oracle sepolia vbUSDC-sUSDe-00.toml

# Deploy oracle (production with verification)
mise deploy-oracle mainnet vbUSDC-sUSDe-00.toml --env prod --verify

# Deploy with Ledger hardware wallet
mise deploy-oracle mainnet vbUSDC-sUSDe-00.toml --env prod --verify --ledger 0xYourAddress

# Verify oracle deployment
mise verify-oracle sepolia vbUSDC-sUSDe-00.toml
mise verify-oracle mainnet vbUSDC-sUSDe-00.toml --env prod
```

### Using forge directly (not recommended)

```bash
# Development deployment
DEPLOY_ENV=dev forge script script/foundry-scripts/oracles/00.DeployRateOracle.s.sol \
  "vbUSDC-sUSDe-00.toml" \
  --rpc-url sepolia \
  --broadcast

# Production deployment with verification
DEPLOY_ENV=prod forge script script/foundry-scripts/oracles/00.DeployRateOracle.s.sol \
  "vbUSDC-sUSDe-00.toml" \
  --rpc-url mainnet \
  --broadcast --verify

# Verify deployment
DEPLOY_ENV=dev forge script script/foundry-scripts/oracles/01.ConfirmRateOracleDeployment.s.sol \
  "vbUSDC-sUSDe-00.toml" \
  --rpc-url sepolia
```

## Creating a New Market Config

1. Copy `TEMPLATE-market-config.toml` to the appropriate environment folder (`dev/` or `prod/`)
2. Rename following the naming convention: `{raToken}-{caToken}-{id}.toml`
3. Fill in all required fields for your market
4. For production: Pre-calculate oracle addresses using precalculation script
5. Deploy using the deployment command above

## Template

See `TEMPLATE-market-config.toml` for a complete template with comments.
