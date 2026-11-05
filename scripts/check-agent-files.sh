#!/bin/bash
# The agent instructions of this repository stay in one place for Codex,
# Claude Code and OpenCode: AGENTS.md at the root, CLAUDE.md importing it,
# skills in .agents/skills with .claude/skills linking to them, and no
# instruction files that only some of the harnesses would load.
# Usage: scripts/check-agent-files.sh [repository root]
cd "${1:-.}" || exit 1
bad=()
tracked=$(git ls-files) || exit 1

[ -s AGENTS.md ] || bad+=("AGENTS.md is missing or empty")
[ "$(head -1 CLAUDE.md 2>/dev/null)" = "@AGENTS.md" ] || bad+=("CLAUDE.md must start with @AGENTS.md")
{ [ -L .claude/skills ] && [ "$(readlink .claude/skills)" = ../.agents/skills ]; } \
  || bad+=(".claude/skills must be a symlink to ../.agents/skills")

while IFS= read -r f; do
  [ -n "$f" ] && bad+=("$f: instructions only some harnesses load")
done <<< "$(printf '%s\n' "$tracked" \
  | grep -E '(^|/)(AGENTS|AGENTS\.override|CLAUDE|CLAUDE\.local)\.md$|^\.claude/(rules|commands|agents)/|^\.opencode/|^\.codex/' \
  | grep -vxE '(AGENTS|CLAUDE)\.md')"

skills=0
for f in .agents/skills/*/SKILL.md; do
  [ -f "$f" ] || continue
  skills=$((skills + 1))
  dir=$(basename "$(dirname "$f")")
  front=$(awk 'NR == 1 { if ($0 != "---") exit; next } /^---$/ { exit } { print }' "$f")
  name=$(printf '%s\n' "$front" | sed -n 's/^name: //p')
  description=$(printf '%s\n' "$front" | sed -n 's/^description: //p')
  [ -n "$front" ] || bad+=("$f: frontmatter must start on line 1")
  [[ $dir =~ ^[a-z0-9]+(-[a-z0-9]+)*$ ]] || bad+=("$f: directory name must be lowercase words joined by hyphens")
  [ "$name" = "$dir" ] || bad+=("$f: name must be $dir")
  { [ -n "$description" ] && [ "${#description}" -le 1024 ]; } \
    || bad+=("$f: description must be one line of 1 to 1024 characters")
  grep -qF "\`$dir\`" AGENTS.md || bad+=("$f: not listed in the skills table of AGENTS.md")
done
[ "$skills" -gt 0 ] || bad+=("no skills in .agents/skills")

if [ ${#bad[@]} -gt 0 ]; then printf '%s\n' "${bad[@]}"; exit 1; fi
echo ok
