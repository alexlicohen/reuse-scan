# reuse-scan

[![check](https://github.com/alexlicohen/reuse-scan/actions/workflows/check.yml/badge.svg)](https://github.com/alexlicohen/reuse-scan/actions/workflows/check.yml)

A [Claude Code](https://claude.com/claude-code) skill: a fast local capability index over
Alex's own scripts/tools/skills, so that before writing any new script/tool/helper he (or
Claude Code acting for him) can check whether something equivalent already exists instead
of re-deriving it.

This operationalizes an existing rule in his global `CLAUDE.md` ("reuse before you
rebuild... scan the project, its docs, and MEMORY for existing functionality") by turning
the check into a fast lookup instead of a manual multi-repo grep.

## Query (the main use)

```sh
bash reuse_scan.sh <keyword>
# or:
bash reuse_scan.sh --query <keyword>
```

Case-insensitive substring match against each indexed entry's name, purpose, and path.
Prints `<path> — <purpose>` per match. No matches = no output, exit 0. If the index
doesn't exist yet, prints a soft nudge to stderr suggesting `--build`, then exits 0.

## Build the index

```sh
bash reuse_scan.sh --build
```

With no args, scans the default roots:

- every top-level `scripts/`, `bin/`, `tools/` dir directly under each `~/projects/*/`
- `~/.claude/scripts/`
- `~/.claude/skills/*/scripts/`
- `~/.claude/skills/*/SKILL.md` (each file is its own entry, not walked as a directory)

For each top-level file in a scripts/bin/tools root (non-recursive), the "purpose" is the
first header comment line after the shebang, or `(no header comment found)`. For each
skill, the "purpose" is the frontmatter `description:` field (folded YAML block scalars
joined into one line).

Writes a JSON array of `{"path","kind","name","purpose"}` objects to `$REUSE_INDEX_FILE`
if set, else `~/.claude/reuse-index.json`. Also flags likely overlap — any normalized
purpose shared by 2+ entries from different paths prints a `POSSIBLE DUPLICATE:` line —
then ends with a one-line summary.

Pass explicit root paths to scan something other than the defaults:

```sh
bash reuse_scan.sh --build ~/some-project/scripts ~/some-project/SKILL.md
```

## Install

```sh
git clone https://github.com/alexlicohen/reuse-scan.git ~/.claude/skills/reuse-scan
```

Claude Code discovers it automatically on the next session.

## Notes / limits

- **Snapshot, not a live index** — rebuild after adding new scripts/skills.
- **Purpose extraction is a header-comment heuristic**, not static analysis.
- **Duplicate detection is exact-match on a normalized purpose string** — it will miss
  semantically similar tools worded differently, and doesn't decide which to keep; treat
  it as a prompt to go read both.
- **Non-recursive by design** — only top-level files in a scanned root are indexed.
- Index writing needs no `jq`; querying prefers `jq` when present (falls back to a
  `sed`-regex field extraction otherwise) — dependency-light like `usage-guard`.

## Tests

`test/run.sh` builds a `mktemp -d` fixture tree (fake projects with scripts, a duplicate
purpose pair, a no-header script, and a fake skill) and drives `--build` / query through
the `REUSE_INDEX_FILE` seam — deterministic, no dependency on the real filesystem. CI runs
`shellcheck` + the suite.

## License

[MIT](LICENSE) © 2026 Alexander Li Cohen
