# shellcheck shell=bash
# ~/.bashrc.d/20-offline.sh — installed by workstation-setup
#
# THE STRICT OFFLINE LOCK. It is OFF by default (ENFORCE_OFFLINE_ENV=0): you are not blocked from the network.
# Install it only on an air-gapped or policy machine (ENFORCE_OFFLINE_ENV=1); it applies to your own terminal and to
# everything you start from it, so it also blocks the commands you type yourself.
#
# Enforces the no-cloud policy at runtime: package managers resolve only from
# the local caches that were filled during installation, and never contact
# PyPI or crates.io.
#
#   Python:  uv pip install numpy         (served from the local wheelhouse)
#   Rust:    cargo add heapless           (served from the local crate cache)
#
# To deliberately fetch something (e.g. from an internal mirror approved by
# IT), override for ONE command only:
#   UV_OFFLINE=0 uv add <pkg>        CARGO_NET_OFFLINE=false cargo update
#
# Remove this file (rm ~/.bashrc.d/20-offline.sh) to switch the enforcement off entirely.

export UV_OFFLINE=1
export UV_FIND_LINKS="$HOME/.local/share/workstation/wheelhouse"
export PIP_NO_INDEX=1
export PIP_FIND_LINKS="$HOME/.local/share/workstation/wheelhouse"
export CARGO_NET_OFFLINE=true
