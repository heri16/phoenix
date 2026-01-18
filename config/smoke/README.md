# Smoke Test Configurations

This directory contains smoke test configurations for validating market deployments on the Cork Protocol.

## File Naming Convention

Smoke test config files follow this pattern:
```
smoke-{id}-{collateral}-{reference}.toml
```

**Components:**
- `{id}`: Two-digit market identifier (00, 01, 02, etc.)
- `{collateral}`: Collateral Asset symbol (e.g., vbUSDC, USDC, ETH)
- `{reference}`: Reference Asset symbol (e.g., sUSDe, wstETH, cbBTC)


**Examples:**
- `smoke-00-vbUSDC-sUSDe.toml` - Dev smoke test for vbUSDC/sUSDe market
- `smoke-01-vbUSDC-sUSDe.toml` - Prod smoke test for vbUSDC/sUSDe market

## Configuration Structure

Each smoke test config file contains:

### 1. Required Fields

**Addresses:**
- `cork_pool_manager` - CorkPoolManager contract address
- `shares_factory` - SharesFactory contract address
- `default_cork_controller` - DefaultCorkController contract address
- `constraint_rate_adapter` - ConstraintRateAdapter contract address
- `oracle_address` - Rate oracle address for the market
- `whitelist_manager` - WhitelistManager contract address
- `pool_creator_address` - Address with pool creator role
- `expected_collateral_address` - Expected collateral token address
- `expected_reference_address` - Expected reference token address
- `expected_whitelisted_addresses` - Array of addresses expected to be whitelisted

**Market Specifics:**
- `fork_block_number` - Block number to fork at (use env var `${FORK_BLOCK_NUMBER}`)
- `acceptable_decimals_max` - Maximum acceptable token decimals (typically 18)
- `acceptable_decimals_min` - Minimum acceptable token decimals (typically 6)
- `expected_expiry_timestamp` - Expected market expiry timestamp
- `expected_rate_min_bound` - Expected minimum rate bound
- `expected_rate_max_bound` - Expected maximum rate bound
- `expected_rate_change_per_day_max` - Expected max daily rate change
- `expected_rate_change_capacity_max` - Expected max rate change capacity
- `expected_oracle_rate` - Expected oracle rate
- `expected_oracle_decimals` - Expected oracle decimals
- `expected_unwind_swap_fee_percentage` - Expected unwind swap fee
- `expected_swap_fee_percentage` - Expected swap fee
- Swap/Exercise/Unwind preview amounts and expected outputs
- `expected_whitelist_enabled` - Whether whitelist is expected to be enabled

### 3. Environment Variables

The config uses environment variables for dynamic values:
- `${FORK_URL}` - RPC URL for the fork
- `${FORK_BLOCK_NUMBER}` - Block number to fork at

## Running Smoke Tests

### Set Environment Variables
```bash
export FORK_URL="https://your-rpc-url"
export SMOKE_CONFIG_PATH=config/smoke/<file>
```

### Run Tests
```bash
forge test --match-path test/forge/smoke/MarketValidationTests.t.sol -vvv
```

## Creating a New Smoke Test Config

1. Copy `TEMPLATE-smoke-test.toml` to your new config file
2. Follow the naming convention
3. Fill in all required fields for your market
4. Change all the [chain-id] section to the actual testnet chain-id
5. Run smoke tests with your config: `SMOKE_CONFIG_PATH=config/smoke/your-config.toml forge test --match-path "test/forge/smoke/*"`

## Template

See `TEMPLATE-smoke-test.toml` for a complete template with default values.
