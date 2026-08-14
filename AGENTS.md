# AGENTS.md — Airlance (корень монорепы)

Этот файл — точка входа для AI-агентов (Claude Code, Codex, Gemini CLI/Antigravity).
Держи его тонким: детали — в AGENTS.md подпроектов. Если редактируешь код внутри
`workspace/api/` или `workspace/macOS-swift/` — сначала прочитай AGENTS.md **этой**
подпапки, он приоритетнее.

## Что это за проект

Мессенджер с нуля: кастомный протокол TCP + Noise IK (взаимная аутентификация +
E2E-шифрование транспорта) + FlatBuffers (компактный бинарный wire-формат).
Архитектура вдохновлена MTProto (Telegram). Wire-схема — единственный источник
истины, общий для сервера и клиентов: `proto/schema.fbs`.

## Структура монорепы

```
airlance/
├── proto/schema.fbs              ← FlatBuffers схема, ОБЩАЯ для Go-сервера и Swift-клиента
├── workspace/
│   ├── api/                      ← Go backend. См. workspace/api/AGENTS.md
│   └── macOS-swift/              ← macOS клиент (Swift, Bazel). См. workspace/macOS-swift/AGENTS.md
├── scripts/gen-fbs.sh            ← кодген FlatBuffers -> Go (см. workspace/api/AGENTS.md)
├── docker-compose.yml            ← Postgres + Redis для локальной разработки
└── Makefile                      ← корневые команды (делегируют в workspace/api)
```

## Инварианты, общие для ВСЕХ подпроектов

1. **`proto/schema.fbs` — общий контракт.** Любое изменение здесь ломает совместимость
   и требует синхронной регенерации кода на обеих сторонах (Go: `make gen`, Swift: `flatc`
   вручную — см. подпроектный AGENTS.md).
2. **`union Body` в схеме — строго append-only.** Индексы вариантов = порядок в файле.
   Никогда не переставлять, не удалять, не вставлять в середину — только добавлять в конец.
   Нарушение ломает wire-совместимость со всеми уже собранными клиентами.
   Подробности и текущая таблица индексов: `workspace/api/AGENTS.md` и `README.md`.
3. **Noise IK handshake зеркалируется 1:1 между Go и Swift.** Любое изменение в
   `internal/noiseik/` (Go) обязано быть отражено в
   `workspace/macOS-swift/submodules/AirlanceClient/Sources/AirlanceClient/Noise/` (Swift),
   и наоборот. Расхождение = AEAD verification failure на клиенте без внятной диагностики.

## Где что искать

| Нужно | Смотри |
|---|---|
| Go backend: слои, usecase, инфраструктура, БД | `workspace/api/AGENTS.md` |
| Swift-клиент: concurrency-модель, Noise, Auth flow | `workspace/macOS-swift/AGENTS.md` |
| Wire-протокол, union Body индексы, история решений | `README.md` (корень) |
| Активные задачи по concurrency-рефакторингу клиента | `workspace/macOS-swift/TASK_concurrency.md` |

## Инструменты агентов

- **Claude Code** — читает `CLAUDE.md` (ссылается сюда).
- **Codex** — читает этот файл (`AGENTS.md`) нативно.
- **Gemini CLI / Antigravity** — читает `GEMINI.md` (ссылается сюда) и/или `AGENTS.md`
  напрямую, если добавлен в `.gemini/settings.json` → `context.fileName`.

Все три инструмента поддерживают иерархию: находясь внутри `workspace/api/`, агент
должен также подхватывать `workspace/api/AGENTS.md` как более специфичный контекст.