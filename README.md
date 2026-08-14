# messenger

A messenger backend written in Go. Architecture inspired by MTProto: Noise IK at the transport layer,
FlatBuffers as the wire protocol. Phase 1 — server + iOS/macOS clients.

## Requirements

- **Go** 1.22+
- **flatc** (FlatBuffers compiler) — version used during development of this repository:

  ```
  flatc version 2.0.8
  ```

  Codegen may differ between major versions of `flatc`. If you install via
  `brew install flatbuffers` on macOS — you will likely get a newer version
  (24.x+). Before running `make gen` for the first time, **verify the output of `flatc --version`
  with the version above**. In case of a discrepancy — either pin the same version via an explicit install
  (`brew install flatbuffers@2` or building from source tag `v2.0.8`), or
  run `make gen` and verify that generated code does not break `go test ./...`
  before updating this version in README.
- If Linux CI is planned — ensure that the same `flatc` version is available there
  (Docker image or build from source) to prevent CI codegen from diverging from local builds.

## Code Generation

The only way to update generated Go code from `proto/schema.fbs`:

```bash
make gen
```

`internal/protocol/generated/` is a build artifact and is not committed (see
`.gitignore`). `make build` and `make run` depend on `make gen` automatically, so
schema and codegen desynchronization is prevented when using `make`.

### Known Environment Quirk: GOPROXY

If `go mod tidy` / `go get` fails with `403 Forbidden: proxy.golang.org` (e.g.
the network is restricted by an allowlist without Go module proxy access, but with access to `github.com`) —
use:

```bash
GOPROXY=direct GOSUMDB=off go mod tidy
```

This forces Go to fetch modules directly from the VCS (GitHub), bypassing
`proxy.golang.org`. `GOSUMDB=off` disables checksum validation via `sum.golang.org`,
which might also be inaccessible for the same reason. In a trusted network (regular
laptop/CI with full internet access), this is not needed — standard `go mod tidy`
works out of the box.

## union Body — Order Invariance Rule

FlatBuffers resolves union variants by numeric index, **not by name**.
Rules (duplicated from `proto/schema.fbs` for visibility without opening the schema):

1. Add new variants **only to the end** of the list.
2. Never reorder existing variants.
3. Never delete an existing variant — older clients may send
   a frame with this index. If a variant is no longer needed — leave the table
   as deprecated in a comment, do not remove it from the union.
4. One PR = one append.

Current locked order:

| Index | Variant | Phase | Purpose |
|---|---|---|---|
| 0 | `NONE` | — | Reserved by FlatBuffers |
| 1 | `Ping` | 5 (heartbeat) | Keepalive, pre-allocated |
| 2 | `Pong` | 5 (heartbeat) | Keepalive, pre-allocated |
| 3 | `NewSession` | 4 (session) | First connection from device after handshake |
| 4 | `ResumeSession` | 4 (session) | Session resumption after handshake |
| 5 | `RegisterAccount` | registration | Account registration request (email, firstName, lastName) |
| 6 | `RegisterAccountAck` | registration | Registration confirmation (account_id) |
| 7 | `ConfirmEmailCode` | registration | Email code confirmation (account_id, code) |
| 8 | `ConfirmEmailCodeAck` | registration | Confirmation result (session_id, device_id) |
| 9 | `Error` | general | Unified protocol error frame (code, message) |

`NewSession`/`ResumeSession` are application frames sent **after**
completing the Noise IK handshake (Phase 3), not part of the handshake payload itself.
This is a deliberate architectural decision: the transport/crypto layer must not be aware
of the existence of sessions — this is the responsibility of the usecase layer (Message Router,
Phase 6). The handshake proves device key ownership; `session_id` is then
used solely to look up existing context, not as a secret.

Violating order rules breaks wire compatibility with all clients
built prior to the change. `TestUnionBodyIndicesAreStable` in
`internal/protocol/smoke_test.go` locks current index values —
if this test fails after schema edits, the ordering was likely broken.

## Phase 1 — Transport Layer (`internal/transport`)

Raw TCP + length-prefix framing, without any encryption (Noise will appear
in Phase 3). Three files:

- **`framing.go`** — `ReadFrame`/`WriteFrame` on top of `io.Reader`/`io.Writer`.
  4-byte big-endian length prefix, `MaxFrameSize = 1 MiB`. The size
  is checked **before** allocating a body buffer (see `TestReadFrame_RejectsOversizedLengthPrefix_WithoutAllocating` —
  the test specifically verifies this behavior, not just declaring it in comments).
- **`connection.go`** — `Connection`, a thin wrapper over `net.Conn` with a
  **blocking** API: `ReadFrame() ([]byte, error)` / `WriteFrame([]byte) error`.
  Intentionally designed without an internal reader channel/goroutine — calling code
  determines its own concurrency model. Rationale: the Message Router (Phase 6)
  is planned to wrap reading in a goroutine+channel ("one goroutine per connection
  reads frames → pushes to channel → worker pool processes"); if `Connection`
  already contained a channel internally, it would result in a redundant double-async
  layer without clear benefits, plus tests would require `select{}`/timeouts instead
  of direct synchronous calls.
- **`listener.go`** — `Listener.ListenAndServe()`, accept loop, goroutine per
  connection. `Handler` is `func(conn *Connection)`, invoked in a
  dedicated goroutine per `Accept`, responsible for its own read loop and
  for calling `Close()`.

### Open Questions Left Intentionally Unresolved in this Phase

- **Graceful shutdown.** `ListenAndServe` currently blocks until an `Accept`
  error occurs (including closing the listener itself) and cannot stop via a
  signal/context. Intentionally left unimplemented for now — the API shape
  (`context.Context`? separate `Shutdown()` method?) should be determined by the
  actual caller, which will be introduced with the Connection ID registry
  (Phase 4) or heartbeat/connection manager (Phase 5), rather than guessed in advance.
- **Panics inside `Handler`.** `Listener` does not wrap `Handler` invocations in `recover()` —
  a panic in a connection handler will crash the entire process. This is also
  intentionally postponed: whether to silently swallow panics or handle them at the
  Message Router level (which has better domain context on error semantics) — will be decided in Phase 6.

## Server Static Keypair (`internal/identity`, `cmd/keygen`)

From the complete Phase 2 plan ("Identity and keys"), currently **only**
the part essential for initiating the Noise IK handshake (Phase 3) is implemented:
the static X25519 keypair for the server.

**Intentionally NOT implemented yet** (deferred to a dedicated user registration phase
after transport + crypto are stabilized):
- HTTP/gRPC device registration endpoint
- PostgreSQL schema for `accounts`/`devices`
- Device key → account/device ID mapping

Rationale: current focus is on the backend transport/crypto layer, without context switching
to client-side logic. User PKI is primarily about onboarding real users
(email/phone/OTP, etc.), which will be designed separately as a product feature
rather than an afterthought tacked onto the Noise handshake.

### Architecture Details

- **`internal/identity/serverkey.go`** — `GenerateServerKeyPair`,
  `SaveServerKeyPair`, `LoadServerKeyPair`. Uses `crypto/ecdh`
  (Go 1.20+ standard library, `ecdh.X25519()`) — without external crypto dependencies.
- File format — JSON with explicit `version` (file format version, not to be confused with
  the key's own version/rotation) and `key_id`. `key_id` is introduced from the beginning
  rather than deferred to a later migration — designed for future support
  of multiple pinned keys on the client.
- The private key is saved to disk with permissions **0600**; `SaveServerKeyPair`
  enforces them even over an existing file with broader permissions.
- `LoadServerKeyPair` recomputes the public key from the private key and validates it
  against the stored `public_key_hex` — detecting file corruption.

### Key Generation

```bash
go run ./cmd/keygen -key-id=v1 -out=server-key.json
```

`cmd/server` **does not generate the key automatically** if the file is missing — this is
a deliberate decision: generating the server private key must be an explicit operator
action, not a side effect of normal startup (otherwise there is a risk of accidentally
creating a new key upon misconfigured deployment paths, silently breaking pinning
for all existing clients). `keygen` refuses to overwrite existing files by default —
an explicit `-force` flag is required.

## Phase 3 — Noise IK Handshake (`internal/noiseik`)

`Noise_IK_25519_ChaChaPoly_SHA256` via `github.com/flynn/noise`. Two files:

- **`noiseik.go`** — `ClientHandshake`/`ServerHandshake`: perform the handshake
  over an established `transport.Connection` (raw handshake messages go through its
  `Read/WriteFrame`, reusing Phase 1 framing and size limits as-is without a separate
  mechanism). Both return `*Conn` on success.
- **`conn.go`** — `Conn`: the same blocking `ReadFrame`/`WriteFrame` API
  as `transport.Connection`, but transparently encrypts/decrypts each frame.
  Upper layers (currently Ping/Pong demo in `cmd/server`, later Message Router in Phase 6)
  interact with `Conn` in the exact same manner as with a raw `Connection`, agnostic to Noise.

`Conn.RemoteStaticKey()` — the peer's static public key authenticated by the
handshake (for the server, this is the client's device key). This is the foundation
for device registration: the server obtains the client's public key with proof of ownership
directly from the handshake, without a separate HTTP endpoint and without transmitting
raw public keys as a separate data packet — see email registration flow discussions
in project notes. **The server intentionally does not validate or restrict which static key
is presented** — this is a decision for the application layer (registration/session resumption)
on top of the established encrypted channel, not the crypto layer.

### Intentionally Deferred in this Phase

- **0-RTT / payload in handshake messages.** Both `WriteMessage` calls pass `payload=nil`.
  0-RTT data in Noise is not replay-protected without a dedicated mechanism — we avoid
  introducing this complexity until there is a specific need to transmit data prior to handshake completion.
- **Server key versioning/rotation inside the handshake itself.**
  Currently the client must know the exact pinned publicKey; selecting `key_id`
  when multiple keys are active is not transmitted in Noise messages. When key rotation
  is needed, a dedicated mechanism will be added (e.g. plaintext prefix before
  Noise messages containing `key_id`) — not resolved prematurely while there is only one key (v1).
- **Integration with Message Router / Session (Phase 4).** `Conn` is currently
  used only for the Ping/Pong demo in `cmd/server`; `NewSession`/`ResumeSession` frames
  (already reserved in `schema.fbs`) are not handled anywhere yet.

### Tests (`noiseik_test.go`)

- `TestHandshake_RoundTrip` — happy path: handshake on both ends, valid `RemoteStaticKey()`,
  encrypted bidirectional frame exchange.
- `TestHandshake_WrongPinnedServerKeyFails` — client pinned the wrong server public key
  (simulating MITM / invalid build pinning) — handshake must fail on both sides before
  any application frame is sent. This was an explicit requirement in Phase 3 plan.
- `TestSession_TamperedFrameFailsAuthentication` — single-byte ciphertext tampering is
  detected by the AEAD tag during decryption.

### Dependency

Added `github.com/flynn/noise` to `go.mod`. `go.sum` is not yet populated for it —
run `go mod tidy` locally (see the GOPROXY section above if the network is restricted by an
allowlist without `proxy.golang.org`) before `make build`/`make test` will work.

## Commands

```bash
make gen                 # generate Go code from proto/schema.fbs
make build               # gen + go build ./...
make test                # gen + go test ./...
make run                 # gen + run server (go run ./cmd/app serve)

# Running application CLI commands
go run ./cmd/app keygen --key-id=v1 --out=server-key.json
go run ./cmd/app serve --addr=:8080 --key=server-key.json
go run ./cmd/app migrate up --dsn="postgres://postgres:postgres@localhost:5432/messenger?sslmode=disable"
go run ./cmd/app migrate down --steps=1
```

## Configuration (.env)

The application supports loading environment variables via `.env` file or `ENV` variables (`github.com/joho/godotenv` + `github.com/kelseyhightower/envconfig`):

| Variable | Default | Description |
|---|---|---|
| `APP_ENV` | `development` | Application environment (`development`, `production`). In `production`, the logger outputs JSON. |
| `LOG_LEVEL` | `info` | Logging level (`debug`, `info`, `warn`, `error`). |
| `SERVER_ADDR` | `:8080` | Server TCP listening port/address. |
| `SERVER_KEY_PATH` | `server-key.json` | Path to server static X25519 key file. |
| `HEARTBEAT_TIMEOUT` | `60s` | Socket inactivity timeout for client connections. |
| `DB_DSN` | `postgres://postgres:postgres@localhost:5432/messenger?sslmode=disable` | PostgreSQL connection string. |
