---
name: reuse-scan
description: A fast local capability index over Alex's own scripts/tools/skills, so that before writing any new script/tool/helper he (or Claude Code acting for him) can check whether something equivalent already exists instead of re-deriving it. Operationalizes the "reuse before you rebuild" rule in his global CLAUDE.md by making the check a fast lookup instead of a manual multi-repo grep. Use when launching or supervising a task that is about to add a new helper/script/tool. Triggers: "check reuse-scan", "does something like this exist", "before I build a new script", "scan for existing tools", or any time you (Claude Code) are about to write a new helper/script — check first.
---

# reuse-scan

Alex's global CLAUDE.md already says: "Reuse before you rebuild... scan the project,
its docs, and MEMORY for existing functionality." That's a manual, multi-repo grep every
time. This skill builds a flat index of his scripts/tools/skills once, so the check
becomes a one-line keyword lookup.

## Query (the main use — do this before writing a new script)

```bash
bash ~/.claude/skills/reuse-scan/reuse_scan.sh <keyword>
# or explicitly:
bash ~/.claude/skills/reuse-scan/reuse_scan.sh --query <keyword>
```

Case-insensitive substring match against each indexed entry's name, purpose, and path.
Prints `<path> — <purpose>` per match, one per line. No matches = no output, exit 0.
If no index exists yet, it prints a soft nudge to stderr suggesting `--build` and still
exits 0 — never a hard failure, this is a lookup aid, not a safety gate.

## Build / rebuild the index

```bash
bash ~/.claude/skills/reuse-scan/reuse_scan.sh --build
```

Scans, with no args, the DEFAULT roots:
- every top-level `scripts/`, `bin/`, `tools/` dir directly under each `~/projects/*/`
- `~/.claude/scripts/`
- `~/.claude/skills/*/scripts/`
- `~/.claude/skills/*/SKILL.md` — each file is its own entry (a skill), not walked as a
  directory

For each top-level script file found in a scripts/bin/tools root (non-recursive), the
"purpose" is the first header comment line after the shebang (fallback:
`(no header comment found)`). For each skill, the "purpose" is the frontmatter
`description:` field (folded YAML block scalars are joined into one line).

Writes the index as a JSON array of `{"path","kind","name","purpose"}` objects to
`$REUSE_INDEX_FILE` if set, else `~/.claude/reuse-index.json`. Also flags likely overlap:
any normalized purpose shared by 2+ entries from different paths prints
`POSSIBLE DUPLICATE: <purpose> -> <path1>, <path2>` — informational, on top of the index
write, not a separate mode. Ends with a one-line summary:
`Indexed N entries (M scripts, K skills) -> <index file path>`.

Rebuild whenever a project gains new scripts/skills you'd want surfaced — there's no
freshness check; it's a snapshot, not a live watch.

## When to reach for this

- **Before writing any new script/helper/tool** — query first, build only if the index
  looks stale or missing.
- When told to "scan for existing tools" or asked "does something like this exist".
- As part of the standing CLAUDE.md reuse rule, whenever a task would add a new code path
  that might already be covered.

## Install

```sh
git clone https://github.com/alexlicohen/reuse-scan.git ~/.claude/skills/reuse-scan
```

## Notes / limits

- **It's a snapshot, not a live index.** Rebuild (`--build`) after adding new
  scripts/skills — nothing watches the filesystem for you.
- **Purpose extraction is a header-comment heuristic**, not static analysis. A script
  with no leading comment indexes as `(no header comment found)` — still useful for
  duplicate-name matching, just not for purpose matching.
- **Duplicate detection is purpose-string equality after normalization** (lowercase,
  whitespace-collapsed) — it will miss semantically-similar tools with differently
  worded headers, and can't tell you which of a flagged pair to keep. Treat
  `POSSIBLE DUPLICATE` as a prompt to go read both, not a verdict.
- **Non-recursive by design.** Only top-level files in a scripts/bin/tools root are
  indexed — nested helper subdirectories are not walked.
- **Index writing has no `jq` dependency** — hand-rolled JSON string-building with
  proper escaping. **Querying prefers `jq`** when present (correct even on purposes
  containing an escaped quote/backslash) and falls back to a `sed`-regex field
  extraction if `jq` is unavailable, which can mis-parse those same edge cases. Fine
  for personal use over your own scripts either way.
