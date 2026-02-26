---
name: autonity-sdk
description: >-
  Multi-language SDK patterns for Autonity — TypeScript (ethers.js/viem),
  Go (ethclient), Python (web3.py). Higher-level API middleware wrapping
  consensus, economic, and stabilization layers. Use when building SDKs,
  APIs, or developer tooling for Autonity.
---

# Autonity SDK Patterns Skill

## TypeScript / ethers.js Patterns

### Connection

```typescript
import { ethers } from "ethers";
const provider = new ethers.JsonRpcProvider(rpcUrl);    // HTTP
const wsProvider = new ethers.WebSocketProvider(wsUrl);  // WebSocket (recommended for subscriptions)
```

### Dynamic ABI & Address Loading

```typescript
// Fetch ABI dynamically — protocol contracts are upgradeable
const abi = await provider.send("aut_getContractABI", []);
const address = await provider.send("aut_getContractAddress", []);
const autonity = new ethers.Contract(address, abi, signer);
```

- **Never hardcode ABIs** — `UpgradeManager` can hot-swap contract bytecode
- **Never hardcode addresses** — they vary per network (devnet/testnet/mainnet)

### LNTN Contract Access

```typescript
const validator = await autonity.getValidator(validatorAddr);
const lntnAddr = validator.liquidContract;
const lntn = new ethers.Contract(lntnAddr, lntnAbi, signer);
```

### Event Filtering

```typescript
const filter = autonity.filters.Transfer(fromAddr, null);
const events = await autonity.queryFilter(filter, fromBlock, toBlock);
```

### Block Subscriptions

```typescript
// 1-second cadence — handler must be fast or use a queue
wsProvider.on("block", async (blockNumber) => { /* ... */ });
```

## Go / ethclient Patterns

### Connection

```go
client, err := ethclient.Dial(wsUrl)        // WebSocket
client, err := ethclient.DialContext(ctx, httpUrl) // HTTP with context
```

### Generated Bindings

All 12 protocol contracts have **typed Go wrappers** in the `bindings` package:

```go
import "github.com/autonity/autonity/bindings"
import "github.com/autonity/autonity/params"

autonity, err := bindings.NewAutonity(params.AutonityContractAddress, client)
oracle, err := bindings.NewOracle(oracleAddr, client)
```

### Transaction Signing

```go
auth, err := bind.NewKeyedTransactorWithChainID(privateKey, chainID)
tx, err := autonity.Bond(auth, validatorAddr, amount)
```

### Block Subscriptions

```go
headers := make(chan *types.Header)
sub, err := client.SubscribeNewHead(ctx, headers)
for header := range headers { /* 1-second cadence */ }
```

## Python / web3.py Patterns

### Connection

```python
from web3 import Web3
w3 = Web3(Web3.HTTPProvider(rpc_url))
w3 = Web3(Web3.WebSocketProvider(ws_url))
```

### Contract Interaction

```python
contract = w3.eth.contract(address=addr, abi=abi)
result = contract.functions.getValidator(validator_addr).call()
```

### Raw RPC for `aut_*` Methods

```python
committee = w3.provider.make_request("aut_getCommittee", [block_number])
core_state = w3.provider.make_request("aut_getCoreState", [])
abi = w3.provider.make_request("aut_getContractABI", [])
```

### Event Logs

```python
events = contract.events.Transfer.get_logs(fromBlock=n, toBlock="latest")
```

## Higher-Level API Middleware Design

Wrap raw contract calls into domain-specific modules with typed returns:

```
autonity.staking.bond(validator, amount)
autonity.staking.unbond(validator, amount)
autonity.staking.getValidators()
autonity.staking.getValidator(addr)
autonity.oracle.getPrice("NTN-USD")
autonity.oracle.getAllPrices()
autonity.oracle.getRoundData(round, symbol)
autonity.asm.openCDP(collateral, borrowAmount)
autonity.asm.getHealth(account)           // collateralization ratio
autonity.asm.listAuctions()
autonity.consensus.getCommittee()
autonity.consensus.getEpochInfo()
autonity.consensus.getCoreState()
autonity.governance.getConfig()
```

### Design Principles

- **Abstract ABI loading** — fetch once via `aut_getContractABI()`, cache in memory
- **Abstract address resolution** — `aut_getContractAddress()`, never hardcoded
- **Domain namespaces**: `staking`, `oracle`, `asm`, `consensus`, `governance`
- **Return typed objects** — parse Solidity structs client-side, not raw hex
- **Chain ID validation** on connect — testnet and mainnet have different IDs
- **Error wrapping** — translate revert reasons into domain-specific errors

## Testing Patterns

### Local Network

- `gengen` tool generates genesis configuration for N validators
- Configurable: committee size, epoch period, staking amounts, oracle symbols
- Outputs genesis.json suitable for `geth init`

### Go End-to-End

- `NewNetwork(t, N, config)` spins up an in-memory N-validator network
- Full consensus, oracle voting, epoch transitions — real protocol behaviour
- Tests in `e2e_test/` cover staking, accountability, oracle, ASM flows

### Docker Chaos Testing

- `docker_e2e_test/` — partition/latency injection against containerised networks
- Tests Byzantine behaviour, network splits, validator omission

### Contract Testing

- Deploy test contracts via Hardhat or Foundry against a local Autonity node
- Mock oracle: test contracts available in `solidity/contracts/test-contract/`
- Use `gengen` genesis with short epoch periods for faster test cycles

### Python RPC Testing

- Lightweight `requests`-based JSON-RPC client in `rpc_tests/lib/`
- Useful for integration testing without heavy SDK dependencies

## Event Indexing Patterns

### Key Events to Index

- `Transfer` — NTN and Auton token movements
- `BondingRequest` / `UnbondingRequest` — Delegation state changes
- `CommitteeUpdate` — Validator committee rotations (epoch boundary)
- `EpochFinalized` — Epoch completion with rewards
- `SlashingEvent` — Validator penalties
- `OracleVote` — Price feed submissions
- CDP events: `Deposit`, `Borrow`, `Repay`, `Withdraw`, `Liquidate`

### Indexing Strategy

- **`eth_getLogs`** with topic filters + block range pagination for historical data
- **WebSocket `eth_subscribe("logs")`** for real-time streaming
- 1-second blocks = **high event throughput** — batch processing is essential
- Paginate in 1000-block ranges to avoid RPC response size limits
- No native subgraph support — build custom indexers

### High-Throughput Considerations

- 86,400 blocks per day (vs Ethereum's ~7,200) — 12x more data
- Index only the events you need — full-chain indexing is expensive
- Use WebSocket subscriptions over HTTP polling — polling at 1s cadence creates excessive load
- Implement backpressure — if processing falls behind, queue blocks rather than dropping

## Anti-Patterns to Flag

- **Hardcoding ABIs** — protocol contracts are upgradeable; fetch dynamically
- **Assuming 12-second block times** — Autonity is 1 second; timers, retries, and timeouts need adjustment
- **Aggressive per-block polling** — at 1s cadence, HTTP polling creates excessive RPC load; use WebSocket subscriptions
- **Skipping chain ID validation** — testnet and mainnet have different chain IDs; always verify on connect
- **Using uncle-related APIs** — always empty on BFT consensus
- **Oracle consumers without staleness checks** — always verify round timestamp and status
- **Assuming Ethereum mainnet gas patterns** — Autonity has a fixed min base fee and different fee dynamics
- **Synchronous block processing** — 1s blocks require async/queued processing to avoid falling behind
