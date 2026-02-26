---
name: autonity
description: >-
  Autonity L1 blockchain protocol knowledge — Tendermint BFT consensus,
  dual-token model (NTN/Auton), protocol contracts, aut_* RPC, EVM
  compatibility. Use when working with Autonity node interaction, contract
  calls, or chain queries.
---

# Autonity Protocol Skill

## Architecture

- **go-ethereum fork** with Tendermint BFT consensus engine replacing Ethash/PoS
- Dual P2P networks: execution layer (eth/snap protocols) + consensus layer (ACN — Autonity Consensus Network)
- 1-second block time with **instant finality** — no reorgs, no confirmation counting
- Maximum 30 validators in the active committee, selected per epoch
- 30-minute epoch period (1800 blocks at 1s cadence)
- EVM-compatible — standard Solidity contracts, standard tx types (Legacy, EIP-2930, EIP-1559)

## Dual Token Model

- **NTN (Newton)**: ERC-20 governance and staking token — bond to validators, earn rewards
- **Auton (ATN)**: Stablecoin pegged to ACU (basket of 7 fiat currencies) — minted via CDPs
- Both are native protocol tokens managed by genesis-deployed contracts

## Protocol Contracts

12 contracts deployed at genesis (not user-deployed — addresses fixed at chain start):

| Contract | Purpose |
|----------|---------|
| **Autonity.sol** | Main protocol: ERC-20 NTN, staking, epochs, committee, governance |
| **Oracle.sol** | Commit-reveal price feeds (9 symbols), validator voting |
| **Accountability.sol** | Byzantine fault detection and slashing |
| **OmissionAccountability.sol** | Inactivity/omission tracking and slashing |
| **Slasher.sol** | Slash execution logic (stake reduction, jailing) |
| **Stabilization.sol** | CDP operations: deposit, borrow, repay, withdraw |
| **Auctioneer.sol** | Liquidation and interest auctions for CDPs |
| **ACU.sol** | Currency basket (7 fiat) defining the Auton peg target |
| **SupplyControl.sol** | Auton mint/burn supply management |
| **InflationController.sol** | NTN inflation (transition + permanent regimes) |
| **UpgradeManager.sol** | Hot contract upgrades (operator-only bytecode swap) |
| **Liquid Newton (LNTN)** | Per-validator ERC-20 representing delegated stake |

- Get addresses dynamically: `aut_getContractAddress()`
- Get ABIs dynamically: `aut_getContractABI()`
- LNTN address: from `getValidator(addr).liquidContract`

## RPC Namespaces

### Standard (inherited from go-ethereum)

| Namespace | Access | Purpose |
|-----------|--------|---------|
| `eth_*` | Public | EVM state, transactions, blocks, logs, gas |
| `net_*` | Public | Network status, peer count |
| `web3_*` | Public | Client version, SHA3 hashing |
| `debug_*` | Private | Chain/state debugging, tracing |
| `admin_*` | Private (IPC) | Peer management, node admin |
| `personal_*` | Private (IPC) | Account/wallet management |
| `miner_*` | Private | Block production control (Tendermint, not PoW) |

### Autonity-specific (`aut_*`)

- `aut_getCommittee(blockNumber)` — Current validator committee members
- `aut_getCommitteeAtHash(hash)` — Committee at specific block hash
- `aut_getContractAddress()` — Autonity protocol contract address
- `aut_getContractABI()` — Protocol contract ABI (enables dynamic binding)
- `aut_getCommitteeEnodes()` — Committee P2P endpoint URIs
- `aut_getCoreState()` — Tendermint BFT state machine state
- `aut_config()` — Full protocol configuration
- `aut_acnPeers()` — Consensus network peer info

### GraphQL

Same data surface as `eth_*` with typed queries: blocks, transactions, accounts, logs, gas pricing. Single mutation: `sendRawTransaction`.

### WebSocket Subscriptions

- `newHeads` — New block headers (fires every ~1s)
- `logs` — Contract event logs (with topic filters)
- `pendingTransactions` — Mempool transactions
- `syncing` — Sync state changes
- `peerEvents` — Peer connect/disconnect (admin-only)

## EVM Compatibility

Autonity is EVM-compatible with these differences from Ethereum mainnet:

- **No reorgs** — Tendermint BFT provides instant finality at block inclusion
- **No uncle/ommer blocks** — always empty (BFT consensus has no forks)
- **Block difficulty** fixed at 1 (not a PoW chain)
- **`block.coinbase`** = block proposer address (rotates per block)
- **1-second blocks** vs Ethereum's ~12 seconds — 12x higher event throughput
- **Max 30 validators** vs Ethereum's thousands — small, permissioned set
- Standard transaction types supported: Legacy, EIP-2930 (access list), EIP-1559 (dynamic fee)

## Key Parameters (Piccadilly Testnet Defaults)

| Parameter | Value |
|-----------|-------|
| Block period | 1 second |
| Epoch period | 30 minutes (1800 blocks) |
| Max committee size | 30 |
| Block gas limit | 20,000,000 |
| Min base fee | 500,000,000 wei |
| Unbonding period | 6 hours |
| Treasury fee | 0.01 NTN |
| Delegation rate | 10% |
| Proposer reward rate | 10% |
| Oracle reward rate | 10% |
| Oracle vote period | 30 blocks |
| Oracle symbols | 9 (6 forex + 3 crypto) |
| Outlier detection | 10% threshold |
| Base slashing (low/mid/high) | 0.5% / 1% / 2% |
| Jail duration | 48 epochs (~24h) |
| Innocence proof window | 120 blocks |

## Anti-Patterns to Flag

- **Assuming reorgs** — no confirmation counting needed; transaction is final at inclusion
- **Querying uncle/ommer data** — always empty on BFT consensus
- **Hardcoding contract addresses** — use `aut_getContractAddress()` (addresses are genesis-fixed but vary per network)
- **Assuming large validator sets** — max 30 committee members, not thousands
- **Using PoW mining APIs** for block production — Tendermint BFT, not Ethash
- **Assuming 12-second block times** — Autonity is 1 second; polling/subscription logic must account for this
- **Hardcoding ABIs** — protocol contracts are upgradeable via UpgradeManager; fetch dynamically with `aut_getContractABI()`
