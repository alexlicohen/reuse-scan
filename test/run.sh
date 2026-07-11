#!/bin/bash
# Deterministic tests for reuse_scan.sh — no dependency on the real ~/projects or
# ~/.claude contents. Builds a mktemp -d fixture tree and drives --build / query
# through the REUSE_INDEX_FILE test seam.
set -u
DIR=$(cd "$(dirname "$0")/.." && pwd)
G="$DIR/reuse_scan.sh"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
pass=0
fail=0
ok()  { pass=$((pass + 1)); echo "  ok   - $1"; }
bad() { fail=$((fail + 1)); echo "  FAIL - $1"; }
eq()  { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (got '$2' want '$3')"; fi; }
ec()  { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (exit $2 want $3)"; fi; }
has() { case "$2" in *"$3"*) ok "$1" ;; *) bad "$1 (missing '$3')" ;; esac; }
hasnot() { case "$2" in *"$3"*) bad "$1 (unexpectedly has '$3')" ;; *) ok "$1" ;; esac; }

# --- fixture tree ---
mkdir -p "$tmp/proj1/scripts" "$tmp/proj2/scripts" "$tmp/skills/my-skill"

cat > "$tmp/proj1/scripts/backup.sh" <<'EOF'
#!/bin/bash
# Nightly backup of the database to S3.
echo hi
EOF

# same purpose (after normalization) as backup.sh, different path -> duplicate pair
cat > "$tmp/proj2/scripts/nightly-backup.sh" <<'EOF'
#!/bin/bash
#   Nightly backup of the database to S3.
echo hi
EOF

cat > "$tmp/proj1/scripts/noheader.sh" <<'EOF'
#!/bin/bash
echo "no comment here at all"
echo "still nothing"
EOF

cat > "$tmp/proj2/scripts/unique-tool.sh" <<'EOF'
#!/bin/bash
# Converts widgets to gadgets.
echo hi
EOF

cat > "$tmp/skills/my-skill/SKILL.md" <<'EOF'
---
name: my-skill
description: >
  Does a very specific thing for testing purposes, spanning
  multiple lines in the frontmatter block.
---

# my-skill
Body content, not indexed.
EOF

INDEX="$tmp/index.json"

echo "build:"
out=$(REUSE_INDEX_FILE="$INDEX" bash "$G" --build "$tmp/proj1/scripts" "$tmp/proj2/scripts" "$tmp/skills/my-skill/SKILL.md" 2>&1)
c=$?
ec "--build exits 0" "$c" 0
has "summary line printed" "$out" "Indexed 5 entries (4 scripts, 1 skills)"

json=$(cat "$INDEX")
has "index contains backup.sh entry" "$json" "backup.sh"
has "index contains nightly-backup.sh entry" "$json" "nightly-backup.sh"
has "index contains unique-tool.sh entry" "$json" "Converts widgets to gadgets"
has "index contains noheader.sh fallback purpose" "$json" "(no header comment found)"
has "index contains skill entry with joined description" "$json" "Does a very specific thing for testing purposes, spanning multiple lines in the frontmatter block."

echo "duplicate detection:"
has "flags the backup.sh / nightly-backup.sh duplicate pair" "$out" "POSSIBLE DUPLICATE:"
has "duplicate line names backup.sh" "$out" "backup.sh"
has "duplicate line names nightly-backup.sh" "$out" "nightly-backup.sh"
# Structural check (not a substring guess): exactly one duplicate GROUP is reported,
# and that group's own line does not name unique-tool.sh. A prior version of this
# assertion checked for the literal substring "unique-tool.sh ->", which can never
# appear in the real output format and would still pass against a broken
# implementation that flagged every script as a duplicate.
dup_lines_out=$(printf '%s\n' "$out" | grep "^POSSIBLE DUPLICATE:")
dup_count=$(printf '%s\n' "$dup_lines_out" | grep -c "^POSSIBLE DUPLICATE:")
eq "exactly one duplicate group detected" "$dup_count" "1"
hasnot "unique-tool.sh does not appear on the duplicate-group line" "$dup_lines_out" "unique-tool.sh"

echo "query:"
out=$(REUSE_INDEX_FILE="$INDEX" bash "$G" widgets)
has "keyword match returns the right path" "$out" "unique-tool.sh"
has "keyword match includes purpose" "$out" "Converts widgets to gadgets"

out=$(REUSE_INDEX_FILE="$INDEX" bash "$G" --query nightly)
has "--query form matches" "$out" "nightly-backup.sh"

out=$(REUSE_INDEX_FILE="$INDEX" bash "$G" my-skill)
has "query matches a skill entry by name" "$out" "SKILL.md"

out=$(REUSE_INDEX_FILE="$INDEX" bash "$G" totally-unrelated-keyword-xyz)
eq "no match -> no output" "$out" ""

echo "missing index:"
out=$(REUSE_INDEX_FILE="$tmp/does-not-exist.json" bash "$G" anything 2>&1 1>/dev/null); c=$?
has "missing index -> soft nudge on stderr" "$out" "reuse_scan.sh --build"
ec  "missing index -> exit 0 (not an error)" "$c" 0

echo "determinism:"
out1=$(REUSE_INDEX_FILE="$tmp/index2.json" bash "$G" --build "$tmp/proj1/scripts" "$tmp/proj2/scripts" "$tmp/skills/my-skill/SKILL.md")
out2=$(REUSE_INDEX_FILE="$tmp/index2.json" bash "$G" --build "$tmp/proj1/scripts" "$tmp/proj2/scripts" "$tmp/skills/my-skill/SKILL.md")
eq "rebuilding twice gives the same summary" "$out1" "$out2"

echo "empty roots (bash 3.2 nounset regression):"
# A prior version crashed with "unbound variable" under bash 3.2's `set -u` when the
# roots array ended up with zero elements (e.g. --build with no args finds zero
# default roots). Point HOME at a fresh empty dir so both default-root generators
# genuinely yield nothing, reproducing the exact zero-element case.
empty_home=$(mktemp -d)
out=$(HOME="$empty_home" REUSE_INDEX_FILE="$tmp/empty-index.json" bash "$G" --build 2>&1); c=$?
ec "zero default roots -> exits 0, does not crash" "$c" 0
has "zero default roots -> reports 0 entries" "$out" "Indexed 0 entries (0 scripts, 0 skills)"
rm -rf "$empty_home"

echo "unwritable index path:"
out=$(REUSE_INDEX_FILE="$tmp/no-such-dir/index.json" bash "$G" --build "$tmp/proj1/scripts" 2>&1); c=$?
ec "unwritable (missing-parent) index path -> exit 1" "$c" 1
has "unwritable index path -> error reported on stderr" "$out" "could not"

echo "symlink index path:"
ln -sf "$tmp/symlink-target-never-created" "$tmp/symlink-index.json"
out=$(REUSE_INDEX_FILE="$tmp/symlink-index.json" bash "$G" --build "$tmp/proj1/scripts" 2>&1); c=$?
ec "symlink at index path -> exit 1, refuses" "$c" 1
has "symlink at index path -> explains why on stderr" "$out" "symlink"

echo "jq-absent fallback (forces the sed query path):"
fakebin=$(mktemp -d)
for tool in bash sed grep tr awk basename dirname mktemp mv rm cat sort; do
  p=$(command -v "$tool" 2>/dev/null) && ln -sf "$p" "$fakebin/$tool"
done
out=$(PATH="$fakebin" REUSE_INDEX_FILE="$INDEX" bash "$G" widgets)
has "jq-absent fallback still finds the match" "$out" "unique-tool.sh"
has "jq-absent fallback includes the purpose" "$out" "Converts widgets to gadgets"
rm -rf "$fakebin"

echo "long purpose truncation:"
longcomment=$(printf 'A%.0s' $(seq 1 400))
mkdir -p "$tmp/proj3/scripts"
printf '#!/bin/bash\n# %s\necho hi\n' "$longcomment" > "$tmp/proj3/scripts/longpurpose.sh"
bash "$G" --build "$tmp/proj3/scripts" > /dev/null 2>&1
REUSE_INDEX_FILE="$tmp/long-index.json" bash "$G" --build "$tmp/proj3/scripts" > /dev/null 2>&1
json=$(cat "$tmp/long-index.json")
has "long purpose is truncated with an ellipsis marker" "$json" "..."
hasnot "long purpose does not contain the full untruncated string" "$json" "$longcomment"

echo "secret redaction:"
mkdir -p "$tmp/proj4/scripts"
printf '#!/bin/bash\n# Uses key AKIAABCDEFGHIJKLMNOP for S3 access.\necho hi\n' > "$tmp/proj4/scripts/secretish.sh"
REUSE_INDEX_FILE="$tmp/secret-index.json" bash "$G" --build "$tmp/proj4/scripts" > /dev/null 2>&1
json=$(cat "$tmp/secret-index.json")
has "AWS-style key pattern gets redacted" "$json" "[REDACTED]"
hasnot "raw key value is not indexed verbatim" "$json" "AKIAABCDEFGHIJKLMNOP"

echo "unreadable script:"
mkdir -p "$tmp/proj5/scripts"
printf '#!/bin/bash\n# Should never be read.\necho hi\n' > "$tmp/proj5/scripts/noaccess.sh"
chmod 000 "$tmp/proj5/scripts/noaccess.sh"
if [ "$(id -u)" != "0" ]; then
  REUSE_INDEX_FILE="$tmp/noaccess-index.json" bash "$G" --build "$tmp/proj5/scripts" > /dev/null 2>&1
  json=$(cat "$tmp/noaccess-index.json")
  has "unreadable file flagged distinctly, not as no-header-comment" "$json" "(unreadable: permission denied)"
else
  echo "  skip - running as root, chmod 000 has no effect"
fi
chmod 644 "$tmp/proj5/scripts/noaccess.sh"

echo ""
echo "PASS=$pass FAIL=$fail"
[ "$fail" -eq 0 ]
