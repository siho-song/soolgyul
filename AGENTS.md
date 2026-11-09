# Project: soolgyul

Project rules for the coding agent (Claude Code). Rules tagged `CRITICAL` outrank ordinary guidance. The git and secret rules are enforced by the hooks in `tools/hooks/`; everything else is followed as written.

## Stack

- Flutter and Dart for mobile app and web
- Supabase Postgres, Auth, Storage, and Edge Functions
- Python, pytest, Deno, and Flutter test for verification

## Architecture

- Product docs, Flutter code, tests, and product Supabase assets belong in this repository.

> Product goals and exclusions: [`docs/PRD.md`](./docs/PRD.md).
> Product decisions: [`docs/ADR.md`](./docs/ADR.md).
> Structure and data flow: [`docs/ARCHITECTURE.md`](./docs/ARCHITECTURE.md).
> Database ownership and migration rules: [`docs/DATABASE.md`](./docs/DATABASE.md).

## Development Process

- CRITICAL: `main` and `dev` take no direct commits or pushes. Work happens on a feature branch cut from `dev` and lands in `dev` by PR (`gh pr create --base dev`). `dev` → `main` is a release PR that the user opens and merges; the agent never opens, merges or pushes to `main`, and `dev` is never deleted. (`tools/hooks/git_guard.sh`)
- CRITICAL: Never commit `.env` files, credentials, signing keys, or service-role secrets. (`tools/hooks/secret_guard.sh`)
- CRITICAL: Remote Supabase (database writes, Storage, Edge Function deploys, live migrations) is touched only when the user asks for it in the current conversation. Catalog, migration and function work ends locally with verification; applying it live is a separate request, never the next step of the local workflow. Remote reads are fine. The user opens remote writes for one turn by writing `#live` in the prompt; the next prompt without it closes them again. (`tools/hooks/live_guard.sh`)
- Use conventional commits (`feat:`, `fix:`, `docs:`, `refactor:`, `test:`, `chore:`). Keep commits atomic by responsibility and change type. Commit and push only when the user asks.
- Prefer the simplest implementation that meets the approved requirements. Use descriptive names; avoid unnecessary abstractions, layers, and speculative extensibility.
- Split code into small, cohesive functions and modules by responsibility. Do not fragment straightforward logic into one-use wrappers.

## Data Work

- The local catalog DB `manual-import/fill-work/rows.sqlite3` is the working copy and wins over live. Read catalog data there first.
- Never estimate a value that can be collected (ABV, sensory levels, prices). A product whose fact or photo cannot be found stays empty.
- LLM batch work over many rows (classification, text generation, review) runs in subagents, never through an API script.

## Subagents

- Read-only exploration, file search and counting always run on the smallest model. For every other task the agent chooses the model.
- Code-writing subagents get disjoint write ownership and preserve unrelated changes.
- CRITICAL: Subagents must not commit, push, deploy, apply live database migrations, or perform external writes.
- CRITICAL: Nested subagents are prohibited.
- Parallel sessions on this repository work in separate git worktrees, never in the same checkout.

## Documentation Scope

- Keep documentation minimal for this pre-launch MVP. Database safety gates remain unchanged.
- Ordinary implementation, bug fixes, and wording changes need code and relevant tests, not new documents. Report progress, verification, and completion in conversation; do not create plan, review, evidence, or completion reports unless the user explicitly requests those files.
- Update an owner document only for a concrete mismatch, and only the affected text. Do not duplicate code definitions, generated values, counts, or test logs across documents.
- ADR entries live in one file, `docs/ADR.md`: one decision per entry, under ten lines (decision, why, date). When a decision changes, rewrite its entry and date; when it stops being true, delete it. No supersede chains; history is git.
- An entry qualifies only when all three hold: there were real alternatives, reversing it later is costly or constrains future work, and the code or data alone cannot explain why. UI layout, wording, contracts, storage layouts, refactoring, enums, status, and counts never qualify.
- When such a decision is made in conversation, the agent asks "ADR로 기록할까요?" and writes only on a yes. Never write an ADR unasked.
- Git history preserves deleted files; delete obsolete docs, tests, and data instead of archiving them in the tree.
- One fact lives in one place. Table and column facts live only in migrations and the table list of `docs/DATABASE.md`; the PRD and specs describe what the product stores, never column lists. The reason for a schema change goes in a short comment at the top of its migration, not in an ADR.
- `docs/ARCHITECTURE.md` and `docs/DATABASE.md` describe the current structure only: parts, data flow, boundaries, table roles. No dates, no applied/deployed status, no approval history, no ADR numbers, no process gates. Schema history is the migrations folder; whether a migration is live is answered by the Supabase migration list, not by a document. A sentence that carries a date is history and is deleted.
- `docs/PRD.md` says for whom the product is, what it does and refuses to do, and what the user sees and can do at each step. Every PRD sentence must be checkable by a non-engineer using the app. Tables, columns, key names, option tables, score weights, screen field lists, checklists and "current status" or "undecided" notes never go in it: mechanics go to `docs/specs/`, tables to `docs/DATABASE.md`, reasons to `docs/ADR.md`. A PRD sentence changes only when the decision changes, by rewriting it, not by adding a note.

## Working Files (manual-import/fill-work)

- Collected data and the basis of every filled value are kept; they cannot be collected again.
- Back up the local DB only through `tools/catalog/backup_local_db.sh "note"`. It keeps the newest 7 backups plus one `--pin` (the state right before the last live sync) and deletes the rest. Never copy `rows.sqlite3` by hand.
- One job, one folder under `manual-import/fill-work/collect/`, named `YYYY-MM-DD_slug`. Inside: `brief.md`, inputs, `out_N.jsonl`, the apply script and its log. No loose files at the `fill-work` root besides `rows.sqlite3`, `merge-map.csv`.

## Replies

- Reply in natural spoken Korean. Use a table for comparisons and lists of facts.

## Commands

```bash
flutter analyze
flutter test
pytest -q
deno test --allow-read --allow-env supabase/functions/_tests
```
