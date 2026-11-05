#!/bin/bash
# The agent instructions of this repository stay in one place for Codex,
# Claude Code and OpenCode: AGENTS.md at the root, CLAUDE.md importing it,
# skills in .agents/skills with .claude/skills linking to them, and no
# instruction files that only some of the harnesses would load.
# Untracked files count too, so a local run catches a file before it is added.
# Usage: scripts/check-agent-files.sh [repository root]
cd "${1:-.}" || exit 1
bad=()
files=$(git -c core.quotePath=false ls-files --cached --others --exclude-standard) || exit 1

[ -s AGENTS.md ] || bad+=("AGENTS.md is missing or empty")
# Codex cuts all project instructions at 32 KiB without a warning.
[ "$(wc -c < AGENTS.md)" -le 24576 ] || bad+=("AGENTS.md is larger than 24 KiB")
[ "$(head -1 CLAUDE.md 2>/dev/null)" = "@AGENTS.md" ] || bad+=("CLAUDE.md must start with @AGENTS.md")
{ [ -L .claude/skills ] && [ "$(readlink .claude/skills)" = ../.agents/skills ]; } \
  || bad+=(".claude/skills must be a symlink to ../.agents/skills")

while IFS= read -r f; do
  [ -n "$f" ] && bad+=("$f: instructions only some harnesses load")
done <<< "$(printf '%s\n' "$files" \
  | grep -E '(^|/)(AGENTS|AGENTS\.override|CLAUDE|CLAUDE\.local)\.md$|(^|/)opencode\.jsonc?$|^\.claude/(rules|commands|agents)/|^\.opencode/|^\.codex/' \
  | grep -vxE '(AGENTS|CLAUDE)\.md')"

# The skills table in AGENTS.md and the skill directories must match both ways.
# shellcheck disable=SC2016 # the backticks are literal Markdown
listed=$(awk '/^## / { table = ($0 == "## Skills") } table' AGENTS.md | sed -n 's/^|.*| `\([^`]*\)` |$/\1/p')
for name in $listed; do
  [ -f ".agents/skills/$name/SKILL.md" ] || bad+=("AGENTS.md lists the skill $name, but .agents/skills/$name/SKILL.md does not exist")
done

skills=0
for f in .agents/skills/*/SKILL.md; do
  [ -f "$f" ] || continue
  skills=$((skills + 1))
  dir=$(basename "$(dirname "$f")")
  front=$(awk 'NR == 1 { if ($0 != "---") exit; next } /^---$/ { closed = 1; exit } { print } END { if (!closed) print "UNCLOSED" }' "$f")
  name=$(printf '%s\n' "$front" | sed -n 's/^name: //p')
  description=$(printf '%s\n' "$front" | sed -n 's/^description: //p')
  [ "$(head -1 "$f")" = --- ] || bad+=("$f: frontmatter must start on line 1")
  if printf '%s\n' "$front" | grep -qx UNCLOSED; then bad+=("$f: frontmatter is not closed with ---"); fi
  if printf '%s\n' "$front" | grep -vqE '^(name|description): |^UNCLOSED$'; then
    bad+=("$f: frontmatter may hold only name and description, each on one line")
  fi
  [[ $dir =~ ^[a-z0-9]+(-[a-z0-9]+)*$ ]] || bad+=("$f: directory name must be lowercase words joined by hyphens")
  [ "$name" = "$dir" ] || bad+=("$f: name must be $dir")
  { [ -n "$description" ] && [ "${#description}" -le 1024 ] && [[ ! $description =~ ^[\>\|\"\'] ]]; } \
    || bad+=("$f: description must be one plain line of 1 to 1024 characters")
  printf '%s\n' "$listed" | grep -qx "$dir" || bad+=("$f: not listed in the skills table of AGENTS.md")
done
[ "$skills" -gt 0 ] || bad+=("no skills in .agents/skills")

if [ ${#bad[@]} -gt 0 ]; then printf '%s\n' "${bad[@]}"; exit 1; fi
echo ok
