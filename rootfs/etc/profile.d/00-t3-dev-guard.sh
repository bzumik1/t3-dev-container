# Login bash (bash -l, bash -lc) moves into the agents' sandbox before ~/.profile.
if [ -n "${BASH_VERSION:-}" ] && [ -r /etc/t3-dev/bash-guard ]; then
  . /etc/t3-dev/bash-guard
fi
