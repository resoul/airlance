# AGENTS.md — Airlance (monorepo root)

This file is the entry point for AI agents (Claude Code, Codex, Gemini CLI/Antigravity).
Keep it lean: details belong in the AGENTS.md files of subprojects. If you are editing code inside
`workspace/api/` or `workspace/macOS-swift/` — first read the AGENTS.md of **that**
subfolder, as it takes precedence.

## Project Overview

A messenger from scratch: custom TCP protocol + Noise IK (mutual authentication +
E2E transport encryption) + FlatBuffers (compact binary wire format).
Architecture inspired by MTProto (Telegram). The wire schema is the single source of
truth, shared across server and clients: `proto/schema.fbs`.

## Monorepo Structure

```
airlance/
├── proto/schema.fbs              ← FlatBuffers schema, SHARED between Go server and Swift client
├── workspace/
│   ├── api/                      ← Go backend. See workspace/api/AGENTS.md
│   └── macOS-swift/              ← macOS client (Swift, Bazel). See workspace/macOS-swift/AGENTS.md
├── scripts/gen-fbs.sh            ← FlatBuffers -> Go code generation (see workspace/api/AGENTS.md)
├── docker-compose.yml            ← Postgres + Redis for local development
└── Makefile                      ← root commands (delegates to workspace/api)
```

## Invariants Common to ALL Subprojects

1. **`proto/schema.fbs` is the shared contract.** Any change here breaks compatibility
   and requires synchronized code regeneration on both sides (Go: `make gen`, Swift: `flatc`
   manually — see subproject AGENTS.md).
2. **`union Body` in the schema is strictly append-only.** Variant indices = order in the file.
   Never reorder, delete, or insert in the middle — only append to the end.
   Violating this breaks wire compatibility with all previously built clients.
   Details and current index table: `workspace/api/AGENTS.md` and `README.md`.
3. **Noise IK handshake is mirrored 1:1 between Go and Swift.** Any change in
   `internal/noiseik/` (Go) must be reflected in
   `workspace/macOS-swift/submodules/AirlanceClient/Sources/AirlanceClient/Noise/` (Swift),
   and vice versa. Divergence = AEAD verification failure on the client without clear diagnostics.

## Where to Find What

| Need | See |
|---|---|
| Go backend: layers, use cases, infrastructure, DB | `workspace/api/AGENTS.md` |
| Swift client: concurrency model, Noise, Auth flow | `workspace/macOS-swift/AGENTS.md` |
| Wire protocol, union Body indices, design decision history | `README.md` (root) |
| Active tasks for client concurrency refactoring | `workspace/macOS-swift/TASK_concurrency.md` |

## Agent Tools

- **Claude Code** — reads `CLAUDE.md` (references this file).
- **Codex** — reads this file (`AGENTS.md`) natively.
- **Gemini CLI / Antigravity** — reads `GEMINI.md` (references this file) and/or `AGENTS.md`
  directly if added to `.gemini/settings.json` → `context.fileName`.

All three tools support hierarchy: when inside `workspace/api/`, the agent
should also pick up `workspace/api/AGENTS.md` as more specific context.