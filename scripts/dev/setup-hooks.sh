#!/usr/bin/env sh
set -eu
git config core.hooksPath .githooks
echo "hooks installed: core.hooksPath=.githooks"
