---
name: matrix
description: >-
  Matrix protocol, mautrix-go bot patterns (Go), Tuwunel homeserver operations,
  and E2EE lifecycle management. Use when working with Matrix protocol concepts,
  mautrix-go bots, Tuwunel configuration, or E2EE bootstrap ceremonies.
---

# Matrix Skill

## Matrix Protocol

- Matrix is a decentralised, real-time communication protocol. All data lives in **rooms** replicated across participating homeservers.
- Event types: `m.room.message` (subtypes `m.text`, `m.notice`, `m.audio`), `m.room.member`, `m.room.encrypted`. Custom namespaced events use reverse-DNS notation: `dev.klazomenai.crew_member`.
- **Homeserver URL**: base URL for Matrix CS API requests (e.g. `https://matrix.example.com`). Separate from the server name used in MXIDs (`@user:example.com`).
- **E2EE fundamentals**:
  - **olm**: 1:1 Double Ratchet key exchange (Signal-style). Used for to-device messages, including megolm session key distribution.
  - **megolm**: group ratchet for room sessions. One outbound session per sender; inbound sessions received via olm to-device messages.
  - **Device verification**: ensures a device's Ed25519 identity key is trusted. Bots use `self_sign` (auto-verify own device) — interactive QR/emoji verification is not supported for bots.

## mautrix-go

Primary library for production Matrix bots and bridges in Go. All active mautrix development targets Go; Python bridge module is officially deprecated.

Build with **`-tags goolm`** — pure Go olm implementation, no CGo, no `libolm` dependency. Required for static Kubernetes binaries, distroless images, and multi-arch cross-compilation.

### Client and Crypto Setup

```go
package main

import (
    "context"
    "os"

    "github.com/rs/zerolog/log"
    "maunium.net/go/mautrix"
    "maunium.net/go/mautrix/crypto/cryptohelper"
    "maunium.net/go/mautrix/event"
    "maunium.net/go/mautrix/id"
)

func main() {
    ctx := context.Background()

    // pickleKey encrypts olm account and session blobs at rest.
    // Store in a Kubernetes Secret — losing it requires full E2EE state reset.
    pickleKey := []byte(os.Getenv("MATRIX_PICKLE_KEY"))

    cli, err := mautrix.NewClient("https://matrix.example.com", "@bot:example.com", "")
    if err != nil {
        log.Fatal().Err(err).Msg("matrix client init failed")
    }

    // Pass Postgres DSN or SQLite file path — both supported natively
    helper, err := cryptohelper.NewCryptoHelper(cli, pickleKey, "postgres://user:pass@host/botdb")
    if err != nil {
        log.Fatal().Err(err).Msg("crypto helper init failed")
    }

    helper.LoginAs = &mautrix.ReqLogin{
        Type:             mautrix.AuthTypePassword,
        Identifier:       mautrix.UserIdentifier{Type: mautrix.IdentifierTypeUser, User: "bot"},
        Password:         os.Getenv("MATRIX_PASSWORD"),
        StoreCredentials: true,
    }

    // Init: upgrades DB schema, shares OLM keys, registers sync handlers automatically
    if err := helper.Init(ctx); err != nil {
        log.Fatal().Err(err).Msg("crypto init failed")
    }
    cli.Crypto = helper  // enables auto-encrypt on send, auto-decrypt on receive

    // ... continued in Event Handling and Sync Loop below
}
```

### Event Handling and Sync Loop

Continues inside `func main()` after the crypto setup above.

```go
    syncer, ok := cli.Syncer.(*mautrix.DefaultSyncer)
    if !ok {
        log.Fatal().Msg("unexpected syncer type — ensure no custom Syncer is installed before this call")
    }

    // Server-side self-filter (preferred — reduces sync payload size)
    syncer.FilterJSON = &mautrix.Filter{
        Room: mautrix.RoomFilter{
            Timeline: mautrix.FilterPart{
                NotSenders: []id.UserID{cli.UserID},
            },
        },
    }

    // Handler receives already-decrypted events transparently when cli.Crypto is set
    syncer.OnEventType(event.EventMessage, func(ctx context.Context, evt *event.Event) {
        content := evt.Content.AsMessage()
        log.Info().Str("room", evt.RoomID.String()).Str("text", content.Body).Msg("received")
    })

    // Decryption failure hook — log and optionally notify room
    helper.DecryptErrorCallback = func(evt *event.Event, err error) {
        log.Warn().Err(err).Str("event_id", evt.ID.String()).Msg("decryption failed")
    }

    // Start sync loop in a goroutine — runs indefinitely with exponential backoff, cancel via ctx
    go func() {
        if err := cli.SyncWithContext(ctx); err != nil && err != context.Canceled {
            log.Error().Err(err).Msg("sync loop exited")
        }
    }()

    // Send message (auto-encrypts if room is encrypted and cli.Crypto is set)
    // roomID is obtained from an invite event, Join response, or hardcoded for known rooms
    roomID := id.RoomID("!example:example.com") // placeholder — replace with real room ID
    if _, err := cli.SendText(ctx, roomID, "Hello from voice bot"); err != nil {
        log.Error().Err(err).Msg("send failed")
    }
}
```

### SQLCryptoStore Persistence

- **PostgreSQL** (recommended for production): pass a Postgres DSN or `*dbutil.Database` to `NewCryptoHelper`. Tables prefixed `crypto_` are created automatically.
- **SQLite** (single-pod / dev): pass a file path string — uses WAL mode automatically. One pod only.
- Schema is versioned with 19 migrations; auto-applied on `Init()`.
- **Never share the bot database** with another program. Each bot instance must own its own `crypto_*` tables.

### self_sign — Required from April 2026

- Bots cannot perform interactive verification (QR/emoji). `self_sign: true` generates and self-signs cross-signing keys automatically on first `Init()`.
- Without it, well-configured clients will stop encrypting to the bot's device after April 2026 (MSC4350 client enforcement).
- Must be configured **before** the first room join — there is no documented path to retrofit encryption into existing rooms.

## Tuwunel Operations

Tuwunel is a Conduit-family homeserver (Rust). Conduit-family servers are explicitly named as supported by mautrix. Go bots/bridges require **no manual bot account registration** on Conduit-family homeservers (unlike Python bridges, which do).

### TOML Configuration

Config file: `tuwunel.toml` (or `tuwunel-example.toml` for reference). All keys live under `[global]`.

```toml
[global]
server_name = "example.com"         # REQUIRED — cannot be changed after DB creation
database_path = "/var/lib/tuwunel"  # data + media directory
address = ["0.0.0.0"]               # listening address (string or array)
port = 8008                          # listening port (int or array)
allow_registration = false           # disable open registration by default
registration_token = "secure_token"  # static registration token
log = "info"                         # tracing-subscriber syntax: "info,tuwunel_core=debug"
allow_encryption = true              # E2EE enabled (default: true)
allow_federation = true              # federation enabled (default: true)
```

### Environment Variable Overrides

- Prefix: `TUWUNEL_` (also accepts legacy `CONDUWUIT_`, `CONDUIT_`)
- Nested config keys use `__` (double underscore) separator

```bash
TUWUNEL_SERVER_NAME=example.com
TUWUNEL_DATABASE_PATH=/var/lib/tuwunel
TUWUNEL_PORT=8008
TUWUNEL_ALLOW_REGISTRATION=false
TUWUNEL_REGISTRATION_TOKEN=secure_token
TUWUNEL_LOG=info
# Nested: [global.tls]
TUWUNEL_TLS__CERTIFICATE_PATH=/etc/tuwunel/cert.pem
```

### Admin Room Commands

All admin commands are sent as messages in the `#admins:example.com` room.

| Command | Purpose |
|---------|---------|
| `create_user <username> [password]` | Create local user; auto-generates password if omitted |
| `make_user_admin <@user:example.com>` | Grant admin privileges |
| `reset_password <username> [password]` | Reset user password |
| `appservice_register` | Register appservice — paste YAML in a code block |
| `appservice_list` | List all registered appservices |
| `appservice_unregister <id>` | Remove appservice registration |
| `token issue [--max-uses N] [--max-age "1d"] [--once]` | Create registration token |
| `token revoke <token>` | Revoke registration token |
| `token list` | List all registration tokens |
| `force_join_room <@user:example.com> <#room:example.com>` | Force a local user to join a room (admin only) |
| `show_config` | Display current running config |
| `reload_config [path]` | Reload config without restart |

### Appservice Registration

Send `appservice_register` in the admin room, followed immediately by a YAML code block:

````
appservice_register
```yaml
id: "voice-bot"
url: "http://voice-bot.default.svc.cluster.local:8080"
as_token: "<homeserver-to-appservice-token>"
hs_token: "<appservice-to-homeserver-token>"
sender_localpart: "voicebot"
namespaces:
  users:
    - exclusive: true
      regex: "@voicebot_.*:example.com"
  aliases: []
  rooms: []
```
````

Verify with `appservice_list`.

### Health Check Endpoints

- `GET /_matrix/client/versions` — standard Matrix spec version list
- `GET /_tuwunel/server_version` — Tuwunel-specific: `{"name": "...", "version": "..."}`

## E2EE Bootstrap Ceremony

1. **Register appservice** — admin room `appservice_register` command with YAML
2. **Bot starts** → `helper.Init(ctx)` creates or loads `OlmAccount` from `crypto_account` table, applies DB migrations
3. **`self_sign`** — bot generates and self-signs cross-signing keys on first `Init()` if configured
4. **Sync begins** → bot receives inbound megolm session keys via olm to-device messages
5. **Join room** → bot accepts invite or is force-joined via `force_join_room` admin command
6. **Verify decryption** — send an encrypted message from a client; confirm bot receives plaintext via `EventMessage` handler

**`pickle_key` persistence in Kubernetes:**
- Store in a K8s Secret; inject via env var (e.g. `MATRIX_PICKLE_KEY`)
- Use `--no-update` flag to prevent the bot from overwriting `config.yaml` on restart
- With `--no-update`, `pickle_key` must be pre-populated — never leave as a `generate` placeholder
- Lost `pickle_key` → reset all `crypto_*` tables and re-establish sessions from scratch

**MSC2409 / appservice E2EE mode:** requires Synapse 1.141+ experimental features. Do **not** enable `encryption: appservice: true` on Tuwunel — use the default `/sync`-based E2EE.

## Anti-patterns

- **`MemoryStore` for crypto** — olm keys lost on every pod restart; all E2EE sessions broken on reconnect.
- **Multiple concurrent bot instances** — extremely unsupported; corrupts E2EE state irreparably. Use `StatefulSet` with `replicas: 1`.
- **`encryption: appservice: true` on Tuwunel** — Synapse-only MSC feature; breaks silently on Conduit-family servers. Use standard `/sync`-based E2EE.
- **Sharing crypto DB between programs** — never point the bot at another process's database; `crypto_*` table ownership must be exclusive.
- **`generate` value for `pickle_key` with `--no-update`** — auto-generates a new random key on every pod restart, corrupting all persisted olm sessions.
- **Skipping `self_sign`** — bots stop receiving encrypted messages from well-configured clients after April 2026 (MSC4350 enforcement).
- **Enabling E2EE after rooms are created** — no documented retrofit path; plan the crypto config before the first room join.
- **Client-side self-filter only** — `if evt.Sender == cli.UserID { return }` works but sends unnecessary events over the wire; use `FilterPart.NotSenders` (server-side) for production bots.
