# shellcheck shell=bash
# ~/.bashrc.d/20-offline.sh — installed by workstation-setup
#
# Enforces the no-cloud policy at runtime: package managers resolve only from
# the local caches that were filled during installation, and never contact
# PyPI or crates.io on their own.
#
#   Python:  uv pip install numpy         (served from the local wheelhouse)
#   Rust:    cargo add heapless           (served from the local crate cache)
#
# To deliberately fetch something (e.g. from an internal mirror approved by
# IT), override for ONE command only:
#   UV_OFFLINE=0 uv add <pkg>        CARGO_NET_OFFLINE=false cargo update
#
# Remove this file to switch the enforcement off entirely.

export UV_OFFLINE=1
export UV_FIND_LINKS="$HOME/.local/share/workstation/wheelhouse"
export PIP_NO_INDEX=1
export PIP_FIND_LINKS="$HOME/.local/share/workstation/wheelhouse"
export CARGO_NET_OFFLINE=true
