#!/usr/bin/env bash
# install-hooks.sh — use the repository's git hooks (tools/githooks) in this clone.
set -euo pipefail
cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/.." || exit 1
chmod +x tools/githooks/*
git config core.hooksPath tools/githooks
echo "Git hooks enabled: pre-commit runs 'tools/check-all.sh --quick'. Undo: git config --unset core.hooksPath"
