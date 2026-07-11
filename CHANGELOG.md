# Changelog

## 1.0.0 — 2026-07-11

Initial release of the `reuse-scan` Claude Code skill.

- **`reuse_scan.sh --build`**: indexes top-level files in every `scripts/`, `bin/`,
  `tools/` dir under `~/projects/*/`, plus `~/.claude/scripts/`,
  `~/.claude/skills/*/scripts/`, and each `~/.claude/skills/*/SKILL.md` as its own
  entry. Extracts a one-line "purpose" per entry (header comment for scripts,
  frontmatter `description:` for skills, including folded YAML block scalars) and
  writes a dependency-light JSON index (no `jq` required).
- **Duplicate flagging**: after building, groups entries by normalized purpose and
  prints `POSSIBLE DUPLICATE: <purpose> -> <path1>, <path2>` for any purpose shared
  by 2+ entries from different paths — informational signal, not a verdict.
- **`reuse_scan.sh <keyword>` / `--query`**: case-insensitive substring match against
  name+purpose+path, one `<path> — <purpose>` line per match. Missing index or no
  matches are both quiet, non-error outcomes — this is a lookup aid, not a safety
  gate (unlike `usage-guard`, it has no fail-loud requirement).
- **`REUSE_INDEX_FILE`** test seam plus explicit root arguments to `--build` let
  `test/run.sh` exercise the whole build/query/duplicate-detection path against a
  `mktemp -d` fixture tree, deterministically, with no dependency on the real
  `~/projects` or `~/.claude` contents.
- **Hardened before first push, via an adversarial code review** (13 confirmed
  findings, 4 of them real shipping-blockers): the index is now written atomically
  (temp file + `mv`) and refuses to follow a symlink at the index path; a zero-root
  `--build` no longer crashes under macOS's stock bash 3.2 (`set -u` + an empty
  array's `${arr[@]}` expansion is an unbound-variable error pre-4.4, not an empty
  expansion — verified live against bash 3.2.57); `json_escape` now strips stray C0
  control bytes (a raw `\r` from a CRLF-authored comment previously produced invalid
  JSON that then made every future query silently look like "no matches" forever);
  the jq query path no longer swallows a corrupt-index parse failure; purpose
  strings are capped at 300 chars and passed through a common secret-token redactor
  (`AKIA…`, `sk-…`, `ghp_…`, etc.) before indexing, since a script's own header
  comment is untrusted, LLM-facing text; unreadable files are labeled distinctly
  from "no header comment"; the duplicate-detection delimiter moved from `|||` to a
  control byte (a legal filename containing `|||` previously corrupted the report).
  `test/run.sh` grew from 19 to 33 assertions covering all of the above, including a
  fix to a vacuous duplicate-detection assertion that fault injection proved would
  pass even against a broken implementation.
- MIT licensed. CI (`.github/workflows/check.yml`) runs `shellcheck` + the suite.
