#!/bin/bash
# Every docker exec the docs or the helper suggest must go through "t3-dev shell".
# shellcheck disable=SC2016 # the backticks are literal Markdown
hits=$(grep -nE 'docker (container |compose )?exec\b' "$@" | grep -vF 'docker exec -it t3-dev t3-dev shell' | grep -vF 'Nepoužívejte `docker exec -u 0`')
if [ -n "$hits" ]; then echo "$hits"; exit 1; fi
