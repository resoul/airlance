# CLAUDE.md

See [AGENTS.md](./AGENTS.md) for project context, architecture map, and cross-project
invariants. Read the AGENTS.md of the specific subproject you're working in
(`workspace/api/AGENTS.md` or `workspace/macOS-swift/AGENTS.md`) before making changes.

Claude Code specific notes:
- Prefer running `make gen` (Go) before `go build`/`go test` when `proto/schema.fbs`
  might have changed — see `workspace/api/AGENTS.md` for why generated code isn't committed.
- No project-specific slash commands or hooks configured yet.