# GEMINI.md

See [AGENTS.md](./AGENTS.md) for project context, architecture map, and cross-project
invariants. Read the AGENTS.md of the specific subproject you're working in
(`workspace/api/AGENTS.md` or `workspace/macOS-swift/AGENTS.md`) before making changes.

Gemini CLI / Antigravity specific notes:
- If AGENTS.md is not picked up automatically, add it to `.gemini/settings.json`:
  `{ "context": { "fileName": ["AGENTS.md", "GEMINI.md"] } }`
- No project-specific custom commands configured yet.