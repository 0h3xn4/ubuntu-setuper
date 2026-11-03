#!/usr/bin/env bash
# check-readme-sync.sh — verify that README.md (the manual guide) mentions
# everything setup.sh and its config files know about: every package, tool,
# home file, GNOME setting, privacy service and install step. Run it after
# changing workstation.conf, a module, or setup.sh. Read-only.
#
#   tools/check-readme-sync.sh        exit 0 = in sync, 1 = README misses things
set -euo pipefail
cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/.." || exit 1

README=README.md
missing=0
need() {   # need KIND ITEM  — ITEM must appear in the README as a whole word
  if ! grep -qwF -- "$2" "$README"; then
    printf 'README is missing %-10s %s\n' "$1:" "$2"
    missing=$((missing + 1))
  fi
}

# --- package and tool lists from the config files -----------------------
# shellcheck source=/dev/null
source workstation.conf
for m in modules/*/module.conf; do
  # shellcheck source=/dev/null
  source "$m"
done
for arr in PKGS_BASE PKGS_CPP PKGS_GUI PKGS_DOCS PKGS_PYTHON PKGS_RUST_BUILD PKGS_NODE \
           PKGS_PODMAN PKGS_DOCKER PKGS_KATE PKGS_NICE_TO_HAVE UV_TOOLS CARGO_TOOLS NPM_TOOLS RUST_COMPONENTS \
           PKGS_EMBEDDED PKGS_EMBEDDED_GUI PKGS_WIRESHARK PKGS_VERIFICATION PKGS_FRAMA_C \
           EMBEDDED_UV_TOOLS_VERIFICATION EMBEDDED_CARGO_TOOLS EMBEDDED_RUST_TARGETS \
           EMBEDDED_PY_PACKAGES EMBEDDED_RUST_CRATES \
           PKGS_DESKTOP_LIBREOFFICE PKGS_DESKTOP_KEEPASSXC PKGS_DESKTOP_VLC \
           PKGS_DESKTOP_GIMP PKGS_DESKTOP_INKSCAPE PKGS_DESKTOP_DEJADUP; do
  declare -n a="$arr"
  for item in "${a[@]}"; do need "$arr" "$item"; done
  unset -n a
done
for item in $OFFLINE_PY_PACKAGES $OFFLINE_RUST_CRATES $OFFLINE_CONTAINER_IMAGES; do need cache "$item"; done

# --- files installed into the home directory -----------------------------
while IFS= read -r f; do
  rel="${f#*/home/}"
  need "home file" "$rel"
done < <(find files/home modules/*/files/home -type f | sort)

# --- script options a user of the manual should know about -------------------
for opt in --full --explain --check --undo --dry-run ws-doctor manifest-diff.sh check-all.sh e2e.sh; do need "option" "$opt"; done

# --- every `step "Title"` in setup.sh and the modules ----------------------
while IFS= read -r title; do
  need "step" "step \"$title\""
done < <(grep -hoE 'step "[^"]+"' setup.sh modules/*/module.sh | sed 's/^step "//; s/"$//' | grep -vx 'Title' | grep -v '^\$' | sort -u)

# --- GNOME settings (schema and key of every gset call) -------------------
while read -r schema key; do
  need "gsettings" "$schema"
  need "gsettings" "$key"
done < <(grep -hoE '^[[:space:]]*gset org\.[A-Za-z.]+ [a-z-]+' setup.sh modules/*/module.sh | awk '{print $2, $3}' | sort -u)

# --- privacy services -------------------------------------------------------
units="$(sed -n '/^UNITS_[A-Z]*=(/,/)/p' setup.sh | grep -oE '[a-z-]+\.(service|path|timer)')"
for u in $units; do need "service" "$u"; done

# --- every opt-in system-change switch (core table and the modules' opt_in hooks) ---
while IFS= read -r sw; do need "switch" "$sw"; done < <(
  { sed -n '/^OPT_IN_CORE=(/,/^)/p' setup.sh | grep -oE '"[A-Z_]+\|' | tr -d '"|';
    grep -hoE 'echo "[A-Z_]+\|' modules/*/module.sh | sed 's/echo "//; s/|//'; } | sort -u)

# --- every step must have a plain-language description (setup.sh --explain) ---
for p in work personal; do
  if ./setup.sh --explain --profile "$p" 2>/dev/null | grep -q 'no description yet'; then
    echo "profile $p: a step has no STEP_WHY description (see ./setup.sh --explain --profile $p)"
    missing=$((missing + 1))
  fi
done

if (( missing )); then
  echo "$missing item(s) missing: update README.md (and keep it in step with setup.sh)."
  exit 1
fi
echo "README.md mentions everything setup.sh knows about."
