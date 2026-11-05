#!/bin/bash
# Every docker exec the docs or the helper suggest must land in the agents'
# sandbox: "t3-dev <subcommand>" (the helper moves itself there) or the
# documented warning against "-u 0". Missing files fail.
# shellcheck disable=SC2016 # the backticks are literal Markdown
for f in "$@"; do [ -r "$f" ] || { echo "missing: $f"; exit 1; }; done
hits=$(grep -nE 'docker (container |compose )?exec\b' "$@" \
  | grep -vE 'docker exec (-it )?t3-dev t3-dev [a-z-]+' \
  | grep -vF 'Nepoužívejte `docker exec -u 0`')
if [ -n "$hits" ]; then echo "$hits"; exit 1; fi
hits=$(grep -nE 'docker (container |compose )?exec\b.*-u 0' "$@" | grep -vF 'Nepoužívejte `docker exec -u 0` ani')
if [ -n "$hits" ]; then echo "$hits"; exit 1; fi
exit 0
