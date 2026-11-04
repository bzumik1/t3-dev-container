#!/bin/bash
# Usage: tests/run.sh <image> <suite>   (suites: tests/suites/*.sh)
set -uo pipefail

image="${1:?Usage: tests/run.sh <image> <suite>}"
suite="${2:?Usage: tests/run.sh <image> <suite>}"

# shellcheck source=tests/lib.sh
source "$(dirname "$0")/lib.sh"
trap finish EXIT

# shellcheck source=/dev/null
source "$root/tests/suites/$suite.sh"
