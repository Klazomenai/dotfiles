---
name: autonity-defi
description: >-
  Autonity DeFi primitives — staking/delegation, Liquid Newton (LNTN),
  oracle price feeds, Auton Stabilization Mechanism (CDPs, liquidations,
  auctions). Use when building DeFi applications, staking interfaces,
  or price feed consumers on Autonity.
---

# Autonity DeFi Primitives Skill

## Staking & Delegation

### Bond / Unbond Lifecycle

- `bond(validator, amount)` — Delegate NTN to a validator; mints LNTN receipt tokens
- `unbond(validator, amount)` — Begin undelegation; **6-hour unbonding period** (funds locked, not instant)
- Unbonding is queued — check `getUnbondingPeriod()` for current duration
- Commission rates set by validators via `changeCommissionRate(validator, rate)`, capped by protocol

### Delegation Approvals

- `approveBonding(caller, amount)` — Approve third-party to bond on your behalf
- `bondingAllowance(owner, caller)` — Check approved delegation amount
- Enables delegation vaults and automated staking strategies

### Validator State

- **Always check `getValidator(addr)` before bonding** — validators can be:
  - `active` — accepting delegations, in committee rotation
  - `paused` — temporarily inactive (operator choice)
  - `jailed` — slashed, cannot receive delegations until jail expires
- `getValidators()` — List all registered validators
- `getCommittee()` — Current active committee (max 30 members)

## Liquid Newton (LNTN)

Each validator has a **unique LNTN ERC-20 contract** representing delegated stake:

- Address: `getValidator(addr).liquidContract`
- Standard ERC-20: `transfer`, `approve`, `balanceOf`, `totalSupply`
- **Composable in DeFi**: transfer, use as collateral, build derivative products

### Rewards

- `claimRewards()` — Must call explicitly; rewards are **not** auto-distributed
- `unclaimedRewards(account)` — Check pending rewards before claiming
- Rewards accrue per-epoch based on delegation share minus validator commission

### Balance Types

- `lockedBalanceOf(delegator)` — Tokens in unbonding (locked, not transferable)
- `unlockedBalanceOf(delegator)` — Freely transferable tokens
- `balanceOf()` returns total (locked + unlocked)

### Third-Party Unbonding

- `approveUnbonding(caller, amount)` — Allow another address to unbond your delegation
- `unbondingAllowance(owner, caller)` — Check approved unbonding amount
- Enables automated portfolio rebalancing and delegation managers

## Oracle Price Feeds

### Available Symbols (9 total)

- Forex: AUD-USD, CAD-USD, EUR-USD, GBP-USD, JPY-USD, SEK-USD
- Crypto: ATN-USD, NTN-USD, NTN-ATN

### Reading Prices

- `latestRoundData(symbol)` — Returns RoundData struct: price, timestamp, status
- `getRoundData(round, symbol)` — Historical price by round number
- `getDecimals()` — Precision for price values (**never hardcode — always query**)
- `getSymbols()` — List all available price feed symbols

### Oracle Mechanics

- **Commit-reveal voting**: validators submit encrypted prices, then reveal
- **30-block vote cycles** (30 seconds at 1s blocks)
- **Outlier detection**: 10% threshold — outlier votes are penalised
- **Non-reveal threshold**: 3 consecutive missed reveals triggers penalty
- Prices are **protocol-native** — no Chainlink dependency, updated by validator consensus

### Freshness

- Always check round timestamp against current block — stale prices are dangerous
- `latestRoundData()` includes status field — verify it indicates a successful round
- Oracle updates lag by one vote period — account for this in time-sensitive applications

## Auton Stabilization Mechanism (ASM)

### CDP Lifecycle

1. `deposit(account, amount)` — Post NTN as collateral
2. `borrow(account, amount)` — Mint Auton stablecoin against collateral
3. `repay(account, amount)` — Return Auton to reduce debt
4. `withdraw(account, amount)` — Reclaim NTN collateral (must maintain ratio)

### Collateralization

- Collateral: NTN tokens | Borrowed: Auton stablecoin
- Peg target: ACU (basket of 7 fiat currencies: AUD, CAD, EUR, GBP, JPY, SEK, USD)
- `collateralPrice()` — Current NTN/ACU ratio used for collateral valuation
- Min collateralization ratio + liquidation ratio — **monitor both continuously**
- `cdps(owner)` — Query CDP state (principal, interest, collateral amounts)

### Interest

- `debtAmountAtTime(account, timestamp)` — Project future debt including accrued interest
- Interest accrues **continuously** — debt grows over time even without borrowing more
- Interest rate set by protocol governance — check before building CDP dashboards

## Liquidation Auctions

### Debt Liquidation

- Undercollateralized CDPs become liquidatable when below liquidation ratio
- `bidDebt(debtor, round, ntnAmount)` — Bid to liquidate (send Auton, receive NTN collateral)
- `maxLiquidationReturn(debtor, round)` — Max NTN receivable (**always check before bidding**)
- `openAuctions()` — List all active liquidation auctions

### Interest Auctions

- `bidInterest(auction, ntnAmount)` — Buy accrued protocol interest (pay NTN, receive Auton)
- `minInterestPayment()` — Minimum bid threshold
- Auction duration configurable by protocol operator

## Reward Economics

| Source | Rate | Distribution |
|--------|------|-------------|
| Proposer rewards | 10% of block rewards | To block proposer |
| Oracle rewards | 10% of block rewards | To oracle voters (pro-rata accuracy) |
| Delegation rewards | Remaining | Pro-rata to delegators minus validator commission |
| Treasury fee | Protocol-set | To protocol treasury account |
| Inflation | Transition + permanent | From inflation reserve via InflationController |

- Rewards are **per-epoch**, not per-block — calculated and distributed at epoch boundaries
- Validator commission is deducted before delegation rewards are allocated

## Anti-Patterns to Flag

- **Assuming instant unbonding** — always 6-hour delay; design UX around pending state
- **Bonding to jailed validators** — always check `getValidator()` state first
- **Hardcoding oracle decimals** — use `getDecimals()`; precision may change across networks
- **Treating CDP interest as static** — it accrues continuously; show real-time debt projections
- **Liquidating without checking `maxLiquidationReturn()`** — bid may exceed available collateral
- **Building on stale oracle prices** — always verify round freshness and status
- **Ignoring locked vs unlocked LNTN** — `balanceOf()` includes unbonding tokens that cannot be transferred
