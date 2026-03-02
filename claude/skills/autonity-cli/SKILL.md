---
name: autonity-cli
description: >-
  Autonity CLI (`aut`) tool — configuration, transaction pipelines, account and
  key management, staking operations, contract interaction, and scripting patterns.
  Use when writing shell scripts, runbooks, or automation that invokes the `aut`
  command.
---

# Autonity CLI (`aut`) Skill

## Configuration & Environment

`.autrc` is an INI-style config file. Search order: current directory → parent directories → `~/.config/aut/autrc`. Note: the global config filename is `autrc` (no leading dot) — this is intentional XDG convention; only the local/project file uses `.autrc`.

Key config fields:

| Key | Purpose |
|-----|---------|
| `rpc_endpoint` | HTTP/IPC RPC URL |
| `keyfile` | Path to encrypted keyfile |
| `keystore` | Keystore directory path |
| `validator` | Default validator address |
| `contract_address` | Default contract address |
| `contract_abi` | Path to contract ABI file |

Environment variable overrides: `WEB3_ENDPOINT`, `KEYFILE`, `KEYFILEDIR`, `KEYFILEPWD`, `CONTRACT_ADDRESS`, `CONTRACT_ABI`.

Priority: CLI flag > env var > config file > default. Default keystore: `~/.autonity/keystore/`. Always set an explicit `keystore` in production `.autrc` — do not rely on the default path.

## Transaction Pipeline

The canonical pipeline is `make → sign → send → wait`:

```sh
HASH=$(aut tx make <subcommand> ... | aut tx sign - | aut tx send -)
aut tx wait "$HASH"
```

- `aut tx make` auto-fetches nonce, gas estimate, and chain ID — override only when you have a specific reason
- `aut tx send -` returns the transaction hash on stdout; non-zero exit code on broadcast failure
- `aut tx wait HASH` — exits 0 on success, non-zero on revert or timeout; always check exit code in scripts
- `--timeout SECONDS` on `aut tx wait` — default is 30s; increase for congested networks

Save to files for debugging or audit trails:

```sh
aut tx make ... > tx.json
aut tx sign tx.json > tx.signed.json
TX_HASH="$(aut tx send tx.signed.json)"
aut tx wait "$TX_HASH"
```

Set `KEYFILEPWD` for non-interactive signing in CI:

```sh
export KEYFILEPWD="$(secret-manager get autonity-key-password)"
HASH=$(aut tx make ... | aut tx sign - | aut tx send -)
aut tx wait "$HASH"
```

## Account & Key Management

```sh
# Create a new encrypted keyfile
aut account new --keyfile PATH

# List all keyfiles in the configured keystore
aut account list

# Check balance (ATN by default)
aut account balance ADDRESS
aut account balance ADDRESS --ntn             # Newton (NTN)
aut account balance ADDRESS --token ADDR      # Any ERC-20

# Import a private key — reads from file or stdin; never pass key as shell arg
aut account import-private-key < keyfile.txt
```

`aut account reveal-private-key` requires an explicit "yes" confirmation. Never call it in scripts or sessions with audit logging — the key appears in stdout and in terminal scrollback.

## Validator & Staking Operations

State-changing staking commands produce unsigned transactions; pipe to `sign | send`. For scripts, capture the hash and call `aut tx wait` — see Scripting section.

```sh
# Bond NTN to a validator
aut validator bond --validator ADDR AMOUNT | aut tx sign - | aut tx send -

# Unbond — subject to unbonding period (~6 hours / 21600 blocks)
aut validator unbond --validator ADDR AMOUNT | aut tx sign - | aut tx send -

# Set LNTN allowance before delegating on behalf of another account
aut validator approve-bonding --validator ADDR AMOUNT | aut tx sign - | aut tx send -
aut validator bond-from --from DELEGATOR --validator ADDR AMOUNT | aut tx sign - | aut tx send -

# Check unclaimed rewards before claiming
aut validator unclaimed-rewards --validator ADDR ACCOUNT
aut validator claim-rewards --validator ADDR | aut tx sign - | aut tx send -

# Set commission rate (decimal, not percentage integer)
aut validator change-commission-rate --validator ADDR 0.03  # = 3%

# Inspect validator state before bonding
aut validator info ADDR
```

Check `bondedStake`, `selfBondedStake`, and `state` fields in `aut validator info` output before committing stake.

## Contract Interaction

```sh
# Read-only call — no transaction, no signing
aut contract call --abi ABI_FILE --address ADDR METHOD [PARAMS]

# State-changing call — produces unsigned tx for signing
TX_HASH=$(aut contract tx --abi ABI_FILE --address ADDR METHOD [PARAMS] | aut tx sign - | aut tx send -)
aut tx wait "$TX_HASH"

# Fetch protocol ABI dynamically (contracts are upgradeable)
aut protocol contract-abi > autonity.abi

# Fetch protocol contract address dynamically
AUTONITY_ADDR=$(aut protocol contract-address)

# Deploy a contract (JSON must contain both "abi" and "bytecode" keys)
aut contract deploy --contract BUILD.json [CONSTRUCTOR_PARAMS]
```

Complex parameter encoding:

- Arrays: JSON string `'["addr1","addr2"]'`
- Structs/tuples: ordered JSON arrays `'["0xAddr", 123, true]'`
- Integers: plain numbers or hex strings

## Protocol Queries (Read-Only)

```sh
aut protocol config                      # Full protocol parameters as JSON
aut protocol epoch-id                    # Current epoch number
aut protocol last-epoch-time             # Timestamp of last epoch transition
aut protocol epoch-total-bonded-stake    # Aggregate stake across all validators
aut protocol validators                  # Full validator list with state

aut block get latest                     # Latest block header
aut block get NUMBER                     # Block by height
aut block get HASH                       # Block by hash
aut block height                         # Current chain height

aut node info                            # RPC node state; admin_* fields require IPC or admin API
```

## Value Denominations

ATN (Auton) formats: `1aut`, `0.5aut`, `1000gwei`, or raw wei integer `1000000000000000000`.

NTN (Newton) formats: `1ntn`, `100newton`, or raw wei integer.

Outputs from `aut tx make` and contract calls are in raw wei. Convert for display:

```sh
python3 -c "print(1500000000000000000 / 1e18)"  # -> 1.5
```

Use `aut account balance` for human-readable formatted output.

Commission rates: `0.03` = 3%. The `change-commission-rate` command expects a decimal fraction, not an integer percentage.

## Scripting & Automation Patterns

Source configuration from `.autrc` or environment — never hardcode RPC endpoints:

```sh
# .autrc
[aut]
rpc_endpoint = https://rpc.example.com
keyfile = ~/.autonity/keys/validator.json
```

Handle `aut tx wait` failure explicitly:

```sh
HASH=$(aut tx make ... | aut tx sign - | aut tx send -)
aut tx wait --timeout 60 "$HASH" || { echo "tx failed or timed out: $HASH"; exit 1; }
```

Use `KEYFILEPWD` for CI — store in your secret manager, never in `.autrc`, shell rc files, or version control:

```sh
export KEYFILEPWD="$(vault kv get -field=password secret/autonity/keyfile)"
```

Prefer pipes for one-shot operations; save to files when you need to debug intermediate state or keep an audit trail of signed transactions.

## Anti-Patterns to Flag

- **Private key or password as a CLI argument** — leaks to shell history and process listings; use `KEYFILEPWD` env var or file input
- **`--gas-price` with `--max-fee-per-gas`** — legacy and EIP-1559 fee flags are mutually exclusive; mixing them produces an error
- **Hardcoding RPC endpoint in scripts** — use `.autrc` `rpc_endpoint` or `WEB3_ENDPOINT` env var for portability
- **`aut contract call` for state-changing methods** — `call` is read-only; state changes require `aut contract tx` piped through sign/send
- **Omitting `aut tx wait` after send** — `send` succeeds when the transaction is broadcast, not when it is included; the tx may still revert
- **Commission rate as integer percentage** — `change-commission-rate 3` sets 300% (overflow/error), not 3%; use `0.03`
- **`bond-from` without prior `approve-bonding`** — `bond-from` transfers LNTN on behalf of another account and requires an allowance first
- **Complex contract params as plain strings** — arrays must be JSON: `'["a","b"]'`; plain comma-separated strings are parsed as a single argument
- **Missing explicit `KEYFILE`/`-k` in scripts** — `aut tx sign` defaults to the configured keyfile, which may differ across environments; be explicit
- **`aut account reveal-private-key` in automation** — the private key appears in stdout; never call this in scripts, CI, or sessions with terminal logging
- **WebSocket RPC URL with `aut`** — `aut` uses web3.py which has known WebSocket issues in Python 3.10+; use HTTP (`https://`) or IPC (`$GETH_IPC`)
- **Hardcoded ABI files** — protocol contracts are upgradeable via `UpgradeManager`; always fetch fresh with `aut protocol contract-abi`
- **Ignoring `aut tx wait` exit code** — a non-zero exit means the transaction reverted or timed out; scripts that ignore it silently proceed on failure
