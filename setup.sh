#!/usr/bin/env bash
# =============================================================================
#  setup.sh — workstation setup for software development on the latest
#             Ubuntu LTS release
#
#  USAGE
#    ./setup.sh --profile NAME     Choose the profile (work, personal, or your
#                                  own file in profiles/). Remembered in
#                                  ~/.config/workstation/profile afterwards.
#    ./setup.sh --full             The FULL setup: switch on every opt-in system change
#                                  (services, /etc drop-ins, groups, GNOME settings,
#                                  ~/.bashrc loader, git defaults, ...). A switch you
#                                  set yourself still wins (SET_GNOME_FONT=0 ./setup.sh
#                                  --full). Also usable as FULL_SETUP=1. Without it
#                                  none of these is touched. Combine with --explain or
#                                  --check to see exactly what it would do.
#    ./setup.sh --explain          Plain-language tour of every step this profile would
#                                  run: what it does, why, and where it changes things.
#                                  Changes nothing, needs no network. Start here.
#    ./setup.sh --check            Dry run: shows what would be installed and
#                                  changed, finds missing packages and
#                                  conflicts. Changes nothing. Start here.
#    ./setup.sh                    Install and configure everything, then write
#                                  a manifest and run the self-test.
#    ./setup.sh --self-test        Only run the self-test (any time later, too).
#    ./setup.sh --manifest         Only write a manifest of the installed software.
#    ./setup.sh --lock             Pin the exact versions now installed into
#                                  locks/<profile>.lock. Commit it: every machine
#                                  with this profile then gets identical tools.
#    ./setup.sh --upgrade          Ignore the pins: install the newest stable
#                                  versions, run the self-test. Then review and
#                                  re-pin with --lock.
#    ./setup.sh --undo [FILE]      Take back what an install run did: replays the undo
#                                  file (newest ~/workstation-undo-*.sh by default)
#                                  newest-first, after showing every command and asking.
#                                  Add --dry-run to only list, --yes to skip the question.
#                                  Never removes APT packages (see README, Undo).
#    ./setup.sh --list-profiles    Show the available profiles and modules.
#    ./setup.sh --help
#
#  Options combine, e.g.:  ./setup.sh --profile personal --check
#
#  STRUCTURE
#    core                 always installed: bash, Helix + language servers, git
#                         tooling, Python/C/C++/Rust, offline docs, privacy
#                         hardening, offline caches
#    modules/<name>/      optional parts (embedded, desktop, ...)
#    profiles/<name>.conf chooses the modules of a machine
#
#  Settings and package lists live in workstation.conf, modules/*/module.conf
#  and the profile. Environment variables override switches for one run,
#  e.g.:  INSTALL_DOCKER=1 ./setup.sh
#  Run as your normal user, NOT with sudo.
#
#  NO-CLOUD POLICY (fixed, every profile)
#    Downloading during installation is allowed. Afterwards, no installed
#    tool contacts external services: no cloud-connected tools, update
#    checks and telemetry are disabled, and uv/pip/cargo/podman work only
#    from local caches that are filled during installation. Networked apps
#    (browser, mail) only do what you direct them to do.
#
#  SAFETY POLICY (fixed, every profile)
#    Never removes packages (apt --no-remove), never upgrades installed ones
#    (no 'apt upgrade'; apt --no-upgrade), never edits package-owned
#    config files, never touches kernel, boot, coreutils or APT sources.
#    Every change is recorded in ~/workstation-undo-<timestamp>.sh.
#
#  VERSIONS
#    Always the latest Ubuntu LTS release (detected, never hardcoded). For
#    software with an LTS line, the newest LTS; otherwise the newest stable
#    release, never betas, release candidates or nightlies.
#
#  REPRODUCIBILITY
#    Versions of tools outside APT are pinned per profile in
#    locks/<profile>.lock; downloads are verified against SHA-256 checksums;
#    each run writes a manifest listing every installed package and tool version.
# =============================================================================
# The step descriptions show '~' literally on purpose.
# shellcheck disable=SC2088
set -Eeuo pipefail

# Remember which variables the user set in the environment: they win over --full.
declare -A ENV_AT_START=()
while IFS= read -r _v; do ENV_AT_START[$_v]=1; done < <(compgen -v | grep -E '^[A-Z][A-Z0-9_]*$' || true)
unset _v

SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}")"
SCRIPT_DIR="$(dirname "$SCRIPT_PATH")"
FILES="$SCRIPT_DIR/files"
MODULES_DIR="$SCRIPT_DIR/modules"
PROFILES_DIR="$SCRIPT_DIR/profiles"
LOCKS_DIR="$SCRIPT_DIR/locks"
CONF_FILE="${WORKSTATION_CONF:-$SCRIPT_DIR/workstation.conf}"
PROFILE_STATE="$HOME/.config/workstation/profile"

MODE=install
UPGRADE=0
FULL="${FULL_SETUP:-0}"      # 1 = --full: all opt-in system changes ON
UNDO_ARG=""                  # --undo [FILE]
DRY_RUN=0                    # --undo --dry-run: only list
ASSUME_YES=0                 # --undo --yes: do not ask
PROFILE="${WORKSTATION_PROFILE:-}"
LIST_PROFILES=0
while (( $# )); do
  case "$1" in
    --upgrade)     UPGRADE=1 ;;
    --check)       MODE=check ;;
    --explain)     MODE=explain ;;
    --full)        FULL=1 ;;
    --self-test)   MODE=selftest ;;
    --manifest)    MODE=manifest ;;
    --lock)        MODE=lock ;;
    --list-profiles) LIST_PROFILES=1 ;;
    --undo)        MODE=undo
                   if [[ ${2:-} != "" && ${2:-} != --* ]]; then UNDO_ARG="$2"; shift; fi ;;
    --dry-run)     DRY_RUN=1 ;;
    --yes|-y)      ASSUME_YES=1 ;;
    --profile)     [[ $# -ge 2 ]] || { echo "--profile needs a name" >&2; exit 2; }; PROFILE="$2"; shift ;;
    --profile=*)   PROFILE="${1#--profile=}" ;;
    -h|--help)     sed -n '2,/^# =====/p' "$SCRIPT_PATH" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *)             echo "Unknown option: $1   (see ./setup.sh --help)" >&2; exit 2 ;;
  esac
  shift
done

# The shell configuration installed by this script sets these variables to
# enforce offline operation at runtime. Installation is allowed to download,
# so clear them for this script only.
unset UV_OFFLINE PIP_NO_INDEX CARGO_NET_OFFLINE UV_FIND_LINKS PIP_FIND_LINKS

# ----------------------------------------------------------------------------
# Internals
# ----------------------------------------------------------------------------
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
DATA_DIR="$HOME/.local/share/workstation"
TEMPLATE_DIR="$DATA_DIR/templates"
WHEELHOUSE="$DATA_DIR/wheelhouse"
RUST_CACHE_DIR="$DATA_DIR/rust-offline-cache"
HASH_DB="$DATA_DIR/download-hashes.txt"
SELFTEST_DIR="$DATA_DIR/selftest"
SELFTEST_FILE="$DATA_DIR/selftest-results.txt"
LOG_FILE="$HOME/workstation-setup-$TIMESTAMP.log"
UNDO_FILE="$HOME/workstation-undo-$TIMESTAMP.sh"
MANIFEST_FILE=""
STATE_DIR="$(mktemp -d)"
MISSING_FILE="$STATE_DIR/missing"
GROUPS_FILE="$STATE_DIR/groups"
FAILED_STEPS=()
EXPLAIN=0                  # 1 = --explain: steps only describe themselves
declare -A STEP_WHY=() STEP_TOUCHES=()   # plain-language description per step title
FIRST_RUN_DATA=0
T_PASS=0; T_FAIL=0; T_SKIP=0; T_WARN=0
MODULES=()                 # enabled modules, set by load_config
MODULE_DIR=""               # module being sourced (modules read it at load time)
LOCK_FILE=""                # locks/<profile>.lock, set by load_config
CARGO_LOCK_FILE=""
export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$PATH"
USER="${USER:-$(id -un)}"
trap 'rm -rf "$STATE_DIR"' EXIT

c_blue=$'\e[1;34m'; c_green=$'\e[1;32m'; c_yellow=$'\e[1;33m'; c_red=$'\e[1;31m'; c_off=$'\e[0m'
section() { printf '\n%s==== %s ====%s\n' "$c_blue" "$*" "$c_off"; }
log()     { printf '%s==>%s %s\n' "$c_blue" "$c_off" "$*"; }
ok()      { printf '%s ✓%s %s\n' "$c_green" "$c_off" "$*"; }
warn()    { printf '%s !%s %s\n' "$c_yellow" "$c_off" "$*" >&2; }
die()     { printf '%s ✗%s %s\n' "$c_red" "$c_off" "$*" >&2; exit 1; }
have()    { command -v "$1" >/dev/null 2>&1; }
on()      { [[ "$1" == 1 ]]; }
any_on()  { local v; for v in "$@"; do if [[ $v == 1 ]]; then return 0; fi; done; return 1; }

# Print the elements of the array whose name is given, one per line.
array_items() { local -n _arr="$1"; if (( ${#_arr[@]} )); then printf '%s\n' "${_arr[@]}"; fi; }

# First line of a command's output, never failing (for version reports).
first_line() { timeout 15 "$@" 2>&1 | head -n1 || true; }

record_undo() { printf '%s\n' "$*" >> "$UNDO_FILE"; }

init_undo_file() {
  cat > "$UNDO_FILE" <<EOF
#!/usr/bin/env bash
# Undo script for workstation-setup, run at $TIMESTAMP
#
# REVIEW BEFORE RUNNING. You can also copy individual lines instead of
# running the whole file. Lines are in the order the changes were made.
#
# Installed APT packages are NOT removed here. To revert them, use APT's
# history (APT 3 and later):  apt history-list   then   sudo apt history-undo <ID>
# With older APT, see /var/log/apt/history.log for what was installed.
# Tools in your home directory can be removed with:
#   uv tool uninstall <name> / cargo uninstall <name> / npm rm -g <name>
set -x
EOF
  chmod +x "$UNDO_FILE"
}

# Print what a step does and where it changes things (STEP_WHY / STEP_TOUCHES,
# defined next to the steps and in the modules).
describe_step() {
  local name="$1"
  if [[ -n ${STEP_WHY[$name]:-} ]]; then
    printf '%s\n' "${STEP_WHY[$name]}" | fold -s -w 88 | sed 's/ *$//; s/^/    /'
  elif (( EXPLAIN )); then
    echo "    (no description yet)"
  fi
  if [[ -n ${STEP_TOUCHES[$name]:-} ]]; then
    printf 'Changes: %s\n' "${STEP_TOUCHES[$name]}" | fold -s -w 88 | sed 's/ *$//; 1!s/^/             /; 1s/^/    /'
  fi
}

# Run a setup step in a subshell with strict error handling. A failing step is
# recorded and reported at the end, but does not abort the remaining steps.
step() {
  local name="$1"; shift
  section "$name"
  describe_step "$name"
  if (( EXPLAIN )); then return 0; fi
  set +e
  ( set -Eeuo pipefail; "$@" )
  local rc=$?
  set -e
  if (( rc != 0 )); then
    FAILED_STEPS+=("$name")
    warn "Step '$name' did not complete (exit $rc). Continuing; see log."
  fi
}

apt_has() { apt-cache show "$1" >/dev/null 2>&1; }

# Print "<package> <candidate-version>" for every given package that has an
# installable candidate. One apt-cache call for all packages: fast.
apt_candidates() {
  (( $# )) || return 0
  apt-cache policy "$@" 2>/dev/null | awk '
    /^[^ ].*:$/     { pkg = substr($0, 1, length($0) - 1); next }
    /^  Candidate:/ { if ($2 != "(none)") print pkg, $2 }'
}

# Install apt packages, skipping (and recording) any that don't exist.
# --no-remove: abort rather than uninstall anything to resolve a conflict.
# --no-upgrade: do not upgrade packages that are already installed; this
# script never upgrades the system (updates are Ubuntu's own business).
apt_install() {
  local available=() pkg ver
  local -A cand=()
  while read -r pkg ver; do cand[$pkg]=$ver; done < <(apt_candidates "$@")
  for pkg in "$@"; do
    if [[ -n ${cand[$pkg]:-} ]]; then
      available+=("$pkg")
    else
      warn "Not in archive, skipping: $pkg"
      echo "$pkg (not found)" >> "$MISSING_FILE"
    fi
  done
  (( ${#available[@]} )) || return 0
  if ! sudo env DEBIAN_FRONTEND=noninteractive apt-get install -y --no-remove --no-upgrade "${available[@]}"; then
    warn "Batch install failed; retrying one package at a time"
    for pkg in "${available[@]}"; do
      sudo env DEBIAN_FRONTEND=noninteractive apt-get install -y --no-remove --no-upgrade "$pkg" \
        || { warn "Skipped (conflict or error): $pkg"; echo "$pkg (not installed: conflict or error)" >> "$MISSING_FILE"; }
    done
  fi
  return 0
}

# Write a config file from stdin. Existing files are kept unless FORCE_CONFIG=1,
# in which case they're backed up first. Identical files are left alone.
write_config() {
  local path="$1" tmp
  tmp="$(mktemp)"
  cat > "$tmp"
  mkdir -p "$(dirname "$path")"
  if [[ -e "$path" ]]; then
    if cmp -s "$tmp" "$path"; then
      rm -f "$tmp"; ok "Unchanged: $path"; return 0
    fi
    if ! on "$FORCE_CONFIG"; then
      rm -f "$tmp"; warn "Exists, left untouched (FORCE_CONFIG=1 to replace): $path"; return 0
    fi
    cp -a "$path" "$path.bak.$TIMESTAMP"
    warn "Backed up $path -> $path.bak.$TIMESTAMP"
    record_undo "mv -f $(printf %q "$path.bak.$TIMESTAMP") $(printf %q "$path")"
  else
    record_undo "rm -f $(printf %q "$path")"
  fi
  mv "$tmp" "$path"
  chmod 644 "$path"
  ok "Wrote $path"
}

# Source of a file for ~/<rel>: files/home (core) or a module's files/home.
home_src() {
  local rel="$1" m
  if [[ -f $FILES/home/$rel ]]; then echo "$FILES/home/$rel"; return 0; fi
  for m in "${MODULES[@]}"; do
    if [[ -f $MODULES_DIR/$m/files/home/$rel ]]; then echo "$MODULES_DIR/$m/files/home/$rel"; return 0; fi
  done
  return 1
}

# Install the file for ~/<rel> (see home_src) to ~/<rel>.
install_file() {
  local rel="$1" mode="${2:-644}" src
  src="$(home_src "$rel")" || { warn "No source file for ~/$rel"; return 1; }
  write_config "$HOME/$rel" < "$src"
  if [[ $mode != 644 ]]; then chmod "$mode" "$HOME/$rel"; fi
}

# Install a NEW file below /etc (or elsewhere in the system) from $1 to $2.
# An existing file is never overwritten: package-owned or administrator files
# stay as they are.
install_system_file() {
  local src="$1" dest="$2"
  if [[ -e $dest ]]; then
    if cmp -s "$src" "$dest"; then ok "Unchanged: $dest"
    else warn "Exists, left untouched (not ours to overwrite): $dest"; fi
    return 0
  fi
  sudo install -D -m 644 "$src" "$dest"
  record_undo "sudo rm -f $(printf %q "$dest") && sudo rmdir --ignore-fail-on-non-empty $(printf %q "$(dirname "$dest")")"
  ok "Installed $dest"
}

# Copy a directory of project starter files to the template store as
# templates/<name>/ (used by ws-init). Templates are reference copies:
# refreshed on every run (backups are kept).
install_templates() {
  local src="$1" name="$2" FORCE_CONFIG=1 f rel
  while IFS= read -r -d '' f; do
    rel="${f#"$src/"}"
    write_config "$TEMPLATE_DIR/$name/$rel" < "$f"
  done < <(find "$src" -type f -print0)
}

# True when a GNOME desktop session (dbus) is available for gsettings.
have_desktop_session() { have gsettings && [[ -n "${DBUS_SESSION_BUS_ADDRESS:-}" ]]; }

# Set a GNOME setting, recording the old value for the undo script.
gset() {
  local schema="$1" key="$2" value="$3" old
  old="$(gsettings get "$schema" "$key" 2>/dev/null)" || { warn "Unknown setting: $schema $key"; return 0; }
  if [[ "$old" == "$value" || "$old" == "'$value'" ]]; then ok "Unchanged: $schema $key"; return 0; fi
  gsettings set "$schema" "$key" "$value"
  record_undo "gsettings set $schema $key $(printf %q "$old")"
  ok "Set $schema $key = $value"
}

add_to_groups() {
  local g
  for g in "$@"; do
    getent group "$g" >/dev/null || continue
    if id -nG "$USER" | grep -qw "$g"; then continue; fi
    sudo usermod -aG "$g" "$USER"
    echo "$g" >> "$GROUPS_FILE"
    record_undo "sudo gpasswd -d $(printf %q "$USER") $g"
    ok "Added $USER to group '$g'"
  done
}

# Download a file and verify its SHA-256 against the lock file. Without a pin
# the checksum is recorded (trust on first use) so --lock can pin it.
fetch_verified() {
  local url="$1" dest="$2" tmp sum pinned
  tmp="$(mktemp)"
  if ! curl -fsSL --retry 3 --connect-timeout 20 "$url" -o "$tmp"; then
    rm -f "$tmp"; warn "Download failed: $url"; return 1
  fi
  sum="$(sha256sum "$tmp" | cut -d' ' -f1)"
  pinned="${DOWNLOAD_SHA256[$url]:-}"
  if [[ -n $pinned && $sum != "$pinned" ]]; then
    rm -f "$tmp"
    warn "CHECKSUM MISMATCH: $url"
    warn "  expected (lock file):  $pinned"
    warn "  received:             $sum"
    warn "  The file changed upstream. Verify the new file, then re-pin with --lock."
    return 1
  elif [[ -n $pinned ]]; then
    ok "Checksum verified: ${url##*/}"
  else
    warn "First download of ${url##*/}: SHA-256 $sum recorded (trust on first use)."
    warn "  Compare it with the publisher if required; './setup.sh --lock' pins it."
  fi
  mkdir -p "$(dirname "$HASH_DB")" "$(dirname "$dest")"
  printf '%s %s\n' "$url" "$sum" >> "$HASH_DB"
  mv "$tmp" "$dest"
}

# Download URL to DEST and verify it against a checksum file PUBLISHED by the
# project itself (stronger than trust-on-first-use).
#   $3 = URL of the checksum file
#   $4 = file name to look for in it; empty = the file holds a single hash
# Understands "HASH  name", "HASH *./name" and a bare "HASH". If the project's
# checksum cannot be fetched it falls back to fetch_verified (with a warning).
fetch_published() {
  local url="$1" dest="$2" sumurl="$3" name="${4:-}" tmp sums expected actual
  tmp="$(mktemp)"
  if ! curl -fsSL --retry 3 --connect-timeout 20 "$url" -o "$tmp"; then
    rm -f "$tmp"; warn "Download failed: $url"; return 1
  fi
  if ! sums="$(curl -fsSL --retry 3 --connect-timeout 20 "$sumurl" 2>/dev/null)"; then
    rm -f "$tmp"
    warn "No published checksum at $sumurl; falling back to trust-on-first-use"
    fetch_verified "$url" "$dest"; return
  fi
  if [[ -n $name ]]; then
    expected="$(awk -v n="$name" '{ f = $2; sub(/^\*/, "", f); sub(/^\.\//, "", f); if (f == n) { print $1; exit } }' <<<"$sums")"
  else
    expected="$(awk 'NR == 1 { print $1 }' <<<"$sums")"
  fi
  if [[ ! $expected =~ ^[0-9a-fA-F]{64}$ ]]; then
    rm -f "$tmp"; warn "Could not read a SHA-256 for ${name:-the file} from $sumurl"; return 1
  fi
  actual="$(sha256sum "$tmp" | cut -d' ' -f1)"
  if [[ ${expected,,} != "$actual" ]]; then
    rm -f "$tmp"
    warn "CHECKSUM MISMATCH against the project's published checksum: $url"
    warn "  published: $expected"
    warn "  received:  $actual"
    return 1
  fi
  ok "Checksum verified against the project's published checksum: ${url##*/}"
  mkdir -p "$(dirname "$HASH_DB")" "$(dirname "$dest")"
  printf '%s %s published\n' "$url" "$actual" >> "$HASH_DB"
  mv "$tmp" "$dest"
}

# The release tag behind a ".../releases/latest/download/<asset>" URL: read from
# the first redirect, so no API call is needed (and it works behind proxies that
# block api.github.com). Prints nothing if it cannot be determined.
release_tag_of() {
  curl -s -o /dev/null -D - --max-time 30 "$1" 2>/dev/null \
    | awk 'tolower($1) == "location:" { if (match($2, /\/download\/[^\/]+\//)) { print substr($2, RSTART + 10, RLENGTH - 11); exit } }'
}

# CPU architecture as used in the projects' release file names (x86_64, aarch64).
host_arch() { uname -m; }

uv_asset() { echo "uv-$(host_arch)-unknown-linux-gnu.tar.gz"; }
uv_base_url() {
  if [[ -n ${UV_VERSION:-} ]]; then echo "https://github.com/astral-sh/uv/releases/download/$UV_VERSION"
  else echo "https://github.com/astral-sh/uv/releases/latest/download"; fi
}
rustup_init_url() { echo "https://static.rust-lang.org/rustup/dist/$(host_arch)-unknown-linux-gnu/rustup-init"; }
starship_asset() { echo "starship-$(host_arch)-unknown-linux-gnu.tar.gz"; }
starship_base_url() { echo "https://github.com/starship/starship/releases/latest/download"; }
helix_url() {  # $1 = version
  echo "https://github.com/helix-editor/helix/releases/download/$1/helix-$1-x86_64-linux.tar.xz"
}
# Pinned version, or the newest stable release (GitHub's "latest" excludes
# pre-releases and drafts). Network access here happens at install time only.
helix_version() {
  if [[ -n ${HELIX_VERSION:-} ]]; then echo "$HELIX_VERSION"; return 0; fi
  curl -fsSL https://api.github.com/repos/helix-editor/helix/releases/latest 2>/dev/null \
    | python3 -c 'import json, sys; print(json.load(sys.stdin)["tag_name"])' 2>/dev/null \
    || curl -s -o /dev/null -D - --max-time 30 https://github.com/helix-editor/helix/releases/latest \
    | awk 'tolower($1) == "location:" { n = split($2, a, "/"); gsub(/\r/, "", a[n]); print a[n]; exit }'
}

# ----------------------------------------------------------------------------
# Modules and the lists they extend
#
# A module offers hooks named mod_<module>_<hook> (see modules/embedded/
# module.sh). module_collect calls one hook of every enabled module and
# concatenates their output (one item per line).
# ----------------------------------------------------------------------------
module_collect() {
  local m
  for m in "${MODULES[@]}"; do
    if declare -F "mod_${m}_$1" >/dev/null; then "mod_${m}_$1"; fi
  done
}

# Names of the package arrays (from the config files) enabled by the switches.
pkg_groups() {
  echo PKGS_BASE
  if on "$INSTALL_CPP"; then echo PKGS_CPP; fi
  if on "$INSTALL_GUI_TOOLS"; then echo PKGS_GUI; fi
  if on "$INSTALL_KATE"; then echo PKGS_KATE; fi
  if on "$INSTALL_NICE_TO_HAVE"; then echo PKGS_NICE_TO_HAVE; fi
  if on "$INSTALL_OFFLINE_DOCS"; then echo PKGS_DOCS; fi
  if on "$INSTALL_PYTHON"; then echo PKGS_PYTHON; fi
  if on "$INSTALL_RUST" && on "$INSTALL_CARGO_TOOLS"; then echo PKGS_RUST_BUILD; fi
  if on "$INSTALL_BASH_LSP"; then echo PKGS_NODE; fi
  if on "$INSTALL_PODMAN"; then echo PKGS_PODMAN; fi
  if on "$INSTALL_DOCKER"; then echo PKGS_DOCKER; fi
  module_collect pkg_groups
  echo PKGS_EXTRA
}

# Files from files/home (core) and the modules' files/home that the enabled
# features install. The cheat sheet is generated, see install_cheatsheet.
home_files() {
  echo .bashrc.d/10-workstation.sh
  echo .inputrc
  echo .local/bin/ws-init
  echo .local/bin/ws-doctor
  echo .config/lazygit/config.yml
  echo .config/tealdeer/config.toml
  if on "$INSTALL_OH_MY_BASH"; then echo .bashrc.d/15-oh-my-bash.sh; fi
  if on "$INSTALL_KATE"; then echo .config/kate/lspclient/settings.json; fi
  if on "$ENFORCE_OFFLINE_ENV"; then echo .bashrc.d/20-offline.sh; fi
  if on "$INSTALL_CPP"; then echo .gdbinit; fi
  if on "$INSTALL_PYTHON"; then echo .config/uv/uv.toml; fi
  if on "$INSTALL_HELIX"; then echo .config/helix/config.toml; echo .config/helix/languages.toml; fi
  if on "$INSTALL_PODMAN" || on "$CACHE_CONTAINER_IMAGES"; then echo .config/containers/containers.conf; fi
  module_collect home_files
}

# User groups the enabled features need (one per line, unique).
needed_groups() {
  {
    if on "$INSTALL_DOCKER" && on "$JOIN_DOCKER_GROUP"; then echo docker; fi
    module_collect groups
  } | awk '!seen[$0]++'
}

uv_tool_list() {
  if on "$INSTALL_PYTHON"; then printf '%s\n' "${UV_TOOLS[@]}"; module_collect uv_tools; fi
}
cargo_tool_list() {
  if on "$INSTALL_RUST" && on "$INSTALL_CARGO_TOOLS"; then
    printf '%s\n' "${CARGO_TOOLS[@]}"; module_collect cargo_tools
  fi
}
rust_target_list() {
  if (( ${#RUST_TARGETS[@]} )); then printf '%s\n' "${RUST_TARGETS[@]}"; fi
  module_collect rust_targets
}
py_package_list() {
  # shellcheck disable=SC2086  # the setting is a space-separated word list
  printf '%s\n' $OFFLINE_PY_PACKAGES
  module_collect py_packages
}
rust_crate_list() {
  # shellcheck disable=SC2086
  printf '%s\n' $OFFLINE_RUST_CRATES
  module_collect rust_crates
}

# The cheat sheet is assembled from the core part, one part per module and
# the maintenance part. It is generated, so it is refreshed on every run
# (a backup is kept if you changed it).
cheatsheet_content() {
  local m f
  cat "$FILES/cheatsheet/00-core.md"
  for m in "${MODULES[@]}"; do
    f="$MODULES_DIR/$m/files/cheatsheet.md"
    if [[ -r $f ]]; then echo; cat "$f"; fi
  done
  echo
  cat "$FILES/cheatsheet/99-maintenance.md"
}
install_cheatsheet() {
  local FORCE_CONFIG=1
  cheatsheet_content | write_config "$HOME/WORKSTATION-CHEATSHEET.md"
}

# ----------------------------------------------------------------------------
# Profiles
# ----------------------------------------------------------------------------
profile_names() {
  local f
  for f in "$PROFILES_DIR"/*.conf; do
    [[ -e $f ]] || continue
    f="${f##*/}"; printf '%s\n' "${f%.conf}"
  done
}

list_profiles() {
  local p desc
  echo "Profiles (./setup.sh --profile NAME):"
  while IFS= read -r p; do
    desc="$(sed -n 's/^PROFILE_DESCRIPTION="\(.*\)"$/\1/p' "$PROFILES_DIR/$p.conf" | head -n1)"
    printf '  %-12s %s\n' "$p" "$desc"
  done < <(profile_names)
  echo
  echo "Modules (always on: core):"
  local m
  for m in "$MODULES_DIR"/*/; do
    [[ -f $m/module.conf ]] || continue
    m="${m%/}"; printf '  %s\n' "${m##*/}"
  done
  if [[ -r $PROFILE_STATE ]]; then echo; echo "This machine's remembered profile: $(<"$PROFILE_STATE")"; fi
}

# Decide the profile: --profile / WORKSTATION_PROFILE, else the remembered one,
# else ask (interactive) or stop.
resolve_profile() {
  if [[ -z $PROFILE && -r $PROFILE_STATE ]]; then PROFILE="$(<"$PROFILE_STATE")"; fi
  if [[ -z $PROFILE ]]; then
    if [[ -t 0 && -t 1 ]]; then
      list_profiles
      read -rp "Profile to use: " PROFILE
    else
      list_profiles >&2
      die "No profile chosen. Use --profile NAME (or set WORKSTATION_PROFILE)."
    fi
  fi
  [[ $PROFILE =~ ^[a-z0-9][a-z0-9_-]*$ ]] || die "Invalid profile name: $PROFILE"
  [[ -f $PROFILES_DIR/$PROFILE.conf ]] || die "Unknown profile '$PROFILE'. Available: $(profile_names | paste -sd' ' -)"
}

# Load order: lock (pins win), profile, core config, module configs and code.
# Switches use ': "${X:=default}"', so what is set first wins:
#   environment > lock > profile > workstation.conf > module defaults
load_config() {
  resolve_profile
  LOCK_FILE="${WORKSTATION_LOCK:-$LOCKS_DIR/$PROFILE.lock}"
  CARGO_LOCK_FILE="${LOCK_FILE%.lock}.Cargo.lock"
  declare -gA UV_PINS=() CARGO_PINS=() NPM_PINS=() PY_PINS=() IMAGE_PINS=() DOWNLOAD_SHA256=()
  # --upgrade deliberately ignores the pins to move to the newest versions.
  if [[ -f $LOCK_FILE ]] && (( ! UPGRADE )); then
    # shellcheck source=/dev/null
    source "$LOCK_FILE"
  fi
  PROFILE_MODULES=()
  # shellcheck source=/dev/null
  source "$PROFILES_DIR/$PROFILE.conf"
  [[ -f $CONF_FILE ]] || die "Config file not found: $CONF_FILE"
  # shellcheck source=workstation.conf
  source "$CONF_FILE"
  local m
  for m in "${PROFILE_MODULES[@]}"; do
    [[ $m =~ ^[a-z][a-z0-9_]*$ && -f $MODULES_DIR/$m/module.conf && -f $MODULES_DIR/$m/module.sh ]] \
      || die "Profile '$PROFILE' lists unknown module '$m'."
    MODULE_DIR="$MODULES_DIR/$m"
    # shellcheck source=/dev/null
    source "$MODULE_DIR/module.conf"
    # shellcheck source=/dev/null
    source "$MODULE_DIR/module.sh"
    MODULES+=("$m")
  done
  apply_full
}

# --full: switch on every opt-in system change (core table + modules' opt_in
# hook), except those the user set explicitly in the environment.
apply_full() {
  if (( ! FULL )); then return 0; fi
  local entry var
  local -a entries=("${OPT_IN_CORE[@]}")
  mapfile -t -O "${#entries[@]}" entries < <(module_collect opt_in)
  for entry in "${entries[@]}"; do
    var="${entry%%|*}"
    if [[ -z ${ENV_AT_START[$var]:-} ]]; then printf -v "$var" '%s' 1; fi
  done
}

# Normalized Python package name (PEP 503), without version specifiers.
py_norm() {
  local n="${1%%[=<>!~ []*}"
  n="${n,,}"
  printf '%s' "${n//[_.]/-}"
}

# Checks that this is Ubuntu, an LTS release, and the LATEST LTS release.
# Uses distro-info's offline release database (no network access).
# Sets OS_PROBLEM to a description of the first problem found, or "".
os_check() {
  OS_PROBLEM=""
  OS_VERIFIED=0
  # shellcheck disable=SC1091
  . /etc/os-release
  if [[ ${ID:-} != ubuntu ]]; then
    OS_PROBLEM="This setup is for Ubuntu; detected ${PRETTY_NAME:-an unknown system}."
  elif [[ ${VERSION:-} != *LTS* ]]; then
    OS_PROBLEM="Ubuntu ${VERSION_ID:-?} is not a long-term support (LTS) release. Use the latest LTS release."
  elif ! have ubuntu-distro-info; then
    warn "Cannot verify that Ubuntu ${VERSION_ID:-?} is the LATEST LTS release (package distro-info missing)."
  else
    local latest latest_name
    latest="$(ubuntu-distro-info --lts 2>/dev/null || true)"
    latest_name="$(ubuntu-distro-info --lts --fullname 2>/dev/null || echo "$latest")"
    if [[ -n $latest ]]; then OS_VERIFIED=1; fi
    if [[ -n $latest && $latest != "${VERSION_CODENAME:-}" ]]; then
      OS_PROBLEM="Ubuntu ${VERSION_ID:-?} is an LTS release, but the latest LTS is ${latest_name}.
   Upgrade with: sudo do-release-upgrade   (LTS-to-LTS upgrades are offered
   once the new release's first point release, .1, is available)."
    fi
  fi
}

# ============================================================================
# INSTALL STEPS
# ============================================================================
preflight() {
  [[ $EUID -ne 0 ]] || die "Run this as your normal user, not as root or with sudo."
  os_check
  if [[ -n $OS_PROBLEM ]]; then
    warn "$OS_PROBLEM"
    read -rp "Continue anyway? [y/N] " answer
    [[ "$answer" == [yY] ]] || exit 1
  fi
  [[ "$(uname -m)" == x86_64 ]] || warn "Not x86_64: some packages may be unavailable."
  have sudo || die "sudo is not available."

  log "Requesting sudo (kept alive for the duration of the script)"
  sudo -v
  ( while true; do sudo -n true; sleep 50; kill -0 "$$" 2>/dev/null || exit; done ) 2>/dev/null &
  SUDO_KEEPALIVE_PID=$!
  trap 'kill "$SUDO_KEEPALIVE_PID" 2>/dev/null || true; rm -rf "$STATE_DIR"' EXIT

  log "Updating package lists"
  sudo apt-get update || die "apt-get update failed. Check network / proxy settings."
  sudo env DEBIAN_FRONTEND=noninteractive apt-get install -y --no-remove --no-upgrade curl ca-certificates gnupg distro-info
}

system_tuning() {
  # Large source trees (clangd, rust-analyzer, file watchers) need more inotify
  # watches. A new drop-in file; nothing existing is modified.
  local f=/etc/sysctl.d/60-dev-inotify.conf
  if [[ ! -e $f ]]; then
    printf 'fs.inotify.max_user_watches = 524288\nfs.inotify.max_user_instances = 1024\n' \
      | sudo tee "$f" >/dev/null
    record_undo "sudo rm -f $f"       # recorded as soon as the file exists, whatever sysctl does next
    if sudo sysctl -p "$f" >/dev/null 2>&1; then ok "Raised inotify limits"
    else warn "Wrote $f but could not apply it now (a container?); it takes effect at the next boot"; fi
  else
    ok "Unchanged: $f"
  fi
}

# Disable (never mask) units that are currently enabled.
disable_units() {
  local u state
  for u in "$@"; do
    state="$(systemctl is-enabled "$u" 2>/dev/null || true)"
    if [[ $state == enabled ]]; then
      # 'disable' is what matters; stopping is best effort (no running systemd in a container)
      sudo systemctl disable "$u" >/dev/null 2>&1 || { warn "Could not disable $u"; continue; }
      sudo systemctl stop "$u" >/dev/null 2>&1 || true
      record_undo "sudo systemctl enable $u"
      ok "Disabled $u"
    fi
  done
}

UNITS_REPORTING=(apport.service apport-autoreport.path apport-autoreport.timer
                 whoopsie.service whoopsie.path kerneloops.service)
UNITS_MOTD=(motd-news.timer)
UNITS_FWUPD=(fwupd-refresh.timer)
NM_CONNECTIVITY_CONF=/etc/NetworkManager/conf.d/99-no-connectivity-check.conf

# Units to disable, according to the switches (one per line).
enabled_privacy_units() {
  if on "$DISABLE_REPORTING_SERVICES"; then printf '%s\n' "${UNITS_REPORTING[@]}"; fi
  if on "$DISABLE_MOTD_NEWS"; then printf '%s\n' "${UNITS_MOTD[@]}"; fi
  if on "$DISABLE_FWUPD_REFRESH"; then printf '%s\n' "${UNITS_FWUPD[@]}"; fi
}

privacy_hardening() {
  # Only services are disabled and NEW drop-in files are added. No packages
  # are removed and no package-owned config files are edited, so updates
  # (including unattended security updates) keep working normally. Each part
  # runs only if its own switch is on.
  local units
  mapfile -t units < <(enabled_privacy_units)
  if (( ${#units[@]} )); then disable_units "${units[@]}"; fi

  if on "$DISABLE_APT_NEWS" && have pro; then
    if sudo pro config set apt_news=false >/dev/null 2>&1; then
      record_undo "sudo pro config set apt_news=true"
      ok "Disabled APT news"
    fi
  fi

  if on "$DISABLE_NM_CONNECTIVITY_CHECK" && [[ -d /etc/NetworkManager/conf.d && ! -e $NM_CONNECTIVITY_CONF ]]; then
    printf '[connectivity]\nenabled=false\n' | sudo tee "$NM_CONNECTIVITY_CONF" >/dev/null
    sudo systemctl reload NetworkManager 2>/dev/null || true
    record_undo "sudo rm -f $NM_CONNECTIVITY_CONF && sudo systemctl reload NetworkManager"
    ok "Disabled NetworkManager connectivity check"
  fi
}

# lazygit is not in every Ubuntu release (not in 24.04). Fallback: its release
# tarball, checked against the checksums.txt the project publishes. The version
# is read from that file, so no API call is needed.
lazygit_fallback() {
  have lazygit && return 0
  apt_has lazygit && return 0
  on "$ALLOW_CURL_INSTALLERS" || return 0
  local base="https://github.com/jesseduffield/lazygit/releases/latest/download" arch=x86_64 asset
  if [[ $(host_arch) == aarch64 ]]; then arch=arm64; fi
  asset="$(curl -fsSL --retry 3 --connect-timeout 20 "$base/checksums.txt" 2>/dev/null \
           | awk -v a="_linux_$arch.tar.gz" 'index($2, a) { print $2; exit }')"
  [[ -n $asset ]] || { warn "Could not find a lazygit release for this CPU"; return 0; }
  fetch_published "$base/$asset" "$STATE_DIR/$asset" "$base/checksums.txt" "$asset"
  mkdir -p "$HOME/.local/bin"
  tar -xzf "$STATE_DIR/$asset" -C "$HOME/.local/bin" lazygit
  record_undo "rm -f ~/.local/bin/lazygit"
  ok "Installed lazygit from the project's release (not in the Ubuntu archive)"
}

base_cli() {
  apt_install "${PKGS_BASE[@]}"
  lazygit_fallback
  if have tldr; then
    # Fetch the example pages ONCE now; auto-update stays off afterwards.
    install_file .config/tealdeer/config.toml
    tldr --update || warn "Could not download tldr pages"
  fi
}

cpp_toolchain() {
  apt_install "${PKGS_CPP[@]}"
  install_file .gdbinit
}

gui_tools() { apt_install "${PKGS_GUI[@]}"; }

offline_docs() {
  apt_install "${PKGS_DOCS[@]}"
}

ensure_uv() {
  have uv && return 0
  if apt_has uv; then apt_install uv; fi
  have uv && return 0
  on "$ALLOW_CURL_INSTALLERS" || { warn "uv is not in the archive and ALLOW_CURL_INSTALLERS=0"; return 1; }
  # The release tarball, checked against the checksum astral publishes next to it
  # (not the installer script: it would also edit your shell startup files).
  local asset base dir; asset="$(uv_asset)"; base="$(uv_base_url)"; dir="${asset%.tar.gz}"
  fetch_published "$base/$asset" "$STATE_DIR/$asset" "$base/$asset.sha256" "$asset"
  tar -xzf "$STATE_DIR/$asset" -C "$STATE_DIR"
  mkdir -p "$HOME/.local/bin"
  install -m 755 "$STATE_DIR/$dir/uv" "$STATE_DIR/$dir/uvx" "$HOME/.local/bin/"
  record_undo "rm -f ~/.local/bin/uv ~/.local/bin/uvx"
  have uv
}

uv_tool_install() {
  local t="$1" pin="${UV_PINS[$1]:-}" current
  current="$(uv tool list 2>/dev/null | awk -v t="$t" '$1 == t { sub(/^v/, "", $2); print $2 }')"
  if [[ -z $pin ]]; then
    if [[ -n $current ]] && on "$UPGRADE"; then uv tool upgrade "$t"; return; fi
    if [[ -n $current ]]; then ok "$t $current (already installed)"; return 0; fi
    uv tool install "$t"
    record_undo "uv tool uninstall $t"
  else
    if [[ $current == "$pin" ]]; then ok "$t $pin (pinned, already installed)"; return 0; fi
    uv tool install --reinstall "$t==$pin"
    if [[ -z $current ]]; then record_undo "uv tool uninstall $t"; fi
  fi
}

python_tools() {
  apt_install "${PKGS_PYTHON[@]}"
  ensure_uv || return 1
  # Never let uv download Python interpreters on its own.
  install_file .config/uv/uv.toml
  export UV_PYTHON_DOWNLOADS=never
  local t tools
  mapfile -t tools < <(uv_tool_list)
  for t in "${tools[@]}"; do
    uv_tool_install "$t" || { warn "uv tool install failed: $t"; echo "$t (uv tool)" >> "$MISSING_FILE"; }
  done
}

rust_toolchain() {
  if ! have rustup && apt_has rustup; then apt_install rustup; fi
  if ! have rustup; then
    on "$ALLOW_CURL_INSTALLERS" || { warn "rustup is not in the archive and ALLOW_CURL_INSTALLERS=0"; return 1; }
    # rustup-init itself, checked against the .sha256 the Rust project publishes
    # (instead of the sh.rustup.rs script that downloads it).
    fetch_published "$(rustup_init_url)" "$STATE_DIR/rustup-init" "$(rustup_init_url).sha256" "rustup-init"
    chmod +x "$STATE_DIR/rustup-init"
    "$STATE_DIR/rustup-init" -y --no-modify-path --default-toolchain none
    record_undo "rustup self uninstall -y"
  fi
  # The archive's rustup has no self-uninstall, so undo what we add: the toolchain (with its
  # components and targets) and, if this run creates it, the ~/.rustup directory itself.
  # (Decided before 'rustup set ...' below, which already creates ~/.rustup/settings.toml.)
  if [[ ! -e $HOME/.rustup ]]; then record_undo "rm -rf ~/.rustup"; fi
  if rustup set auto-self-update disable >/dev/null 2>&1; then
    record_undo "rustup set auto-self-update enable"
  fi
  if ! rustup toolchain list 2>/dev/null | grep -q "^$RUST_TOOLCHAIN"; then
    record_undo "rustup toolchain uninstall $RUST_TOOLCHAIN"
  fi
  rustup toolchain install "$RUST_TOOLCHAIN" --profile default
  rustup default "$RUST_TOOLCHAIN"
  rustup component add "${RUST_COMPONENTS[@]}"
  local targets
  mapfile -t targets < <(rust_target_list)
  if (( ${#targets[@]} )); then rustup target add "${targets[@]}"; fi

  if on "$INSTALL_CARGO_TOOLS"; then
    apt_install "${PKGS_RUST_BUILD[@]}"
    local specs=() c pin cargo_tools
    mapfile -t cargo_tools < <(cargo_tool_list)
    for c in "${cargo_tools[@]}"; do
      pin="${CARGO_PINS[$c]:-}"
      if [[ -n $pin ]]; then specs+=("$c@$pin"); else specs+=("$c"); fi
    done
    local installed_before; installed_before="$(cargo install --list 2>/dev/null || true)"
    for c in "${cargo_tools[@]}"; do
      if ! grep -q "^$c v" <<<"$installed_before"; then record_undo "cargo uninstall $c"; fi
    done
    log "Compiling cargo tools (this can take 10+ minutes)"
    cargo install --locked "${specs[@]}"
  fi
}

bash_lsp() {
  apt_install "${PKGS_NODE[@]}"
  have npm || { warn "npm is not available"; return 1; }
  npm config set prefix "$HOME/.local"
  # Stop npm from contacting the registry for update notices, funding, audits.
  npm config set update-notifier false
  npm config set fund false
  npm config set audit false
  record_undo "npm config delete prefix; npm config delete update-notifier; npm config delete fund; npm config delete audit"
  local specs=() t pin
  for t in "${NPM_TOOLS[@]}"; do
    pin="${NPM_PINS[$t]:-}"
    if [[ -n $pin ]]; then specs+=("$t@$pin"); else specs+=("$t"); fi
  done
  for t in "${NPM_TOOLS[@]}"; do
    if [[ ! -e $HOME/.local/lib/node_modules/$t ]]; then record_undo "npm uninstall -g $t"; fi
  done
  npm install -g "${specs[@]}"
}

kate_setup() {
  apt_install "${PKGS_KATE[@]}"
  # Language servers for Kate's LSP client: ours (basedpyright, ruff, cmake, taplo) in
  # addition to Kate's defaults (clangd, rust-analyzer, bash-language-server). Merged
  # over Kate's built-in settings by Kate itself. JSON/YAML servers are not installed
  # on purpose: their defaults download schemas from the internet.
  install_file .config/kate/lspclient/settings.json
}

nice_to_have() { apt_install "${PKGS_NICE_TO_HAVE[@]}"; }

helix_setup() {
  # No snap: snapd auto-refreshes from the online Snap Store.
  if ! have hx && ! have helix && apt_has helix; then apt_install helix; fi
  # A Helix installed from a release tarball (not apt) is moved to the newest
  # stable release on --upgrade.
  local tarball_install=0
  if [[ -L "$HOME/.local/bin/hx" && "$(readlink "$HOME/.local/bin/hx")" == "$HOME/.local/opt/"* ]]; then
    tarball_install=1
  fi
  if { ! have hx && ! have helix; } || { on "$UPGRADE" && (( tarball_install )); }; then
    on "$ALLOW_CURL_INSTALLERS" || { warn "Helix is not in the archive and ALLOW_CURL_INSTALLERS=0"; return 1; }
    local ver; ver="$(helix_version)" || { warn "Could not determine the latest Helix release"; return 1; }
    if have hx && [[ "$(hx --version | awk '{ print $2 }')" == "$ver" ]]; then
      ok "Helix $ver is the newest stable release"
    else
    local name="helix-${ver}-x86_64-linux" dest="$HOME/.local/opt"
    fetch_verified "$(helix_url "$ver")" "$STATE_DIR/helix.tar.xz"
    mkdir -p "$dest" "$HOME/.local/bin"
    tar -xJf "$STATE_DIR/helix.tar.xz" -C "$dest"
    # Helix finds its 'runtime' directory next to the real binary.
    ln -sf "$dest/$name/hx" "$HOME/.local/bin/hx"
    record_undo "rm -rf $(printf %q "$dest/$name") ~/.local/bin/hx"
    ok "Installed Helix $ver to $dest/$name"
    fi
  fi
  install_file .config/helix/config.toml
  install_file .config/helix/languages.toml
}

containers() {
  if on "$INSTALL_PODMAN"; then
    apt_install "${PKGS_PODMAN[@]}"
    # Whenever podman is installed, it must never pull images by itself (guard: if this podman
    # rejects the file, remove it again, unless it was already there).
    local conf="$HOME/.config/containers/containers.conf" existed=0
    if [[ -e $conf ]]; then existed=1; fi
    if have podman; then
      install_file .config/containers/containers.conf
      if ! podman info >/dev/null 2>&1; then
        if (( existed == 0 )); then rm -f "$conf"; fi
        warn "podman did not accept containers.conf (pull_policy); left it out"
      fi
    fi
  fi
  if on "$INSTALL_DOCKER"; then
    apt_install "${PKGS_DOCKER[@]}"
    if on "$JOIN_DOCKER_GROUP"; then add_to_groups docker; fi
  fi
  return 0
}

# Monospace font for GNOME and its terminal: the Nerd Font if we install it.
gnome_mono_font() {
  if on "$INSTALL_NERD_FONT"; then echo 'JetBrainsMono Nerd Font Mono 11'; else echo 'JetBrains Mono 11'; fi
}

# ----------------------------------------------------------------------------
# JetBrains Mono Nerd Font: JetBrains Mono patched with icon glyphs (used by
# prompts such as starship's nerd-font-symbols preset and Oh My Bash themes).
# Not in the Ubuntu archive; downloaded once from the project's GitHub release,
# checksum-verified, installed for your user only.
# ----------------------------------------------------------------------------
NERD_FONT_DIR="$HOME/.local/share/fonts/JetBrainsMonoNerdFont"
nerd_font_version() {
  if [[ -n ${NERD_FONT_VERSION:-} ]]; then echo "$NERD_FONT_VERSION"; return 0; fi
  # "latest" excludes pre-releases and drafts. Network access at install time only.
  # The redirect of the "latest" download names the tag; the API is the second choice.
  local tag
  tag="$(release_tag_of https://github.com/ryanoasis/nerd-fonts/releases/latest/download/JetBrainsMono.tar.xz)"
  if [[ -n $tag ]]; then echo "$tag"; return 0; fi
  curl -fsSL --max-time 30 https://api.github.com/repos/ryanoasis/nerd-fonts/releases/latest \
    | python3 -c 'import json, sys; print(json.load(sys.stdin)["tag_name"])'
}

nerd_font() {
  have fc-cache || apt_install fontconfig
  # (captured, not piped into 'grep -q': with pipefail an early grep exit would look like a failure)
  local fonts; fonts="$(fc-list : family 2>/dev/null || true)"
  if [[ $fonts == *'JetBrainsMono Nerd Font Mono'* ]] && ! on "$UPGRADE"; then
    ok "JetBrains Mono Nerd Font is already installed"; return 0
  fi
  local ver base
  if ver="$(nerd_font_version 2>/dev/null)" && [[ -n $ver ]]; then
    base="https://github.com/ryanoasis/nerd-fonts/releases/download/$ver"
  else
    ver=""
    base="https://github.com/ryanoasis/nerd-fonts/releases/latest/download"
    warn "Could not look up the newest release; using the 'latest' download (its version cannot be pinned)"
  fi
  # Checked against SHA-256.txt, which the Nerd Fonts project publishes with each release.
  fetch_published "$base/JetBrainsMono.tar.xz" "$STATE_DIR/jbm-nerd.tar.xz" "$base/SHA-256.txt" "JetBrainsMono.tar.xz"
  mkdir -p "$NERD_FONT_DIR"
  # Only the two ligature families: "Nerd Font" and "Nerd Font Mono" (the Mono one
  # is the right choice for terminals). Skips the "NL" (no ligatures) and "Propo" variants.
  tar -xJf "$STATE_DIR/jbm-nerd.tar.xz" -C "$NERD_FONT_DIR" --wildcards \
    'JetBrainsMonoNerdFont-*.ttf' 'JetBrainsMonoNerdFontMono-*.ttf'
  if [[ -n $ver ]]; then printf '%s\n' "$ver" > "$NERD_FONT_DIR/.version"; fi
  fc-cache -f "$NERD_FONT_DIR"
  record_undo "rm -rf $(printf %q "$NERD_FONT_DIR") && fc-cache -f"
  ok "Installed JetBrains Mono Nerd Font ${ver:-(unpinned)} to $NERD_FONT_DIR"
}

# ----------------------------------------------------------------------------
# Oh My Bash (opt-in: INSTALL_OH_MY_BASH). Its own installer replaces ~/.bashrc
# and enables a 13-day GitHub update check, so it is NOT used: we fetch one
# pinned commit and load it from ~/.bashrc.d/15-oh-my-bash.sh with updates off.
# ----------------------------------------------------------------------------
OMB_DIR="$HOME/.local/share/oh-my-bash"
OMB_REPO=https://github.com/ohmybash/oh-my-bash.git
oh_my_bash() {
  have git || { warn "git is not installed"; return 1; }
  local commit="${OH_MY_BASH_COMMIT:-}"
  if [[ -z $commit ]]; then commit="$(git ls-remote "$OMB_REPO" HEAD | awk 'NR == 1 { print $1 }')"; fi
  [[ $commit =~ ^[0-9a-f]{40}$ ]] || { warn "Could not determine the Oh My Bash commit"; return 1; }
  if [[ -d $OMB_DIR/.git ]]; then
    if [[ "$(git -C "$OMB_DIR" rev-parse HEAD)" == "$commit" ]]; then
      ok "Oh My Bash ${commit:0:12} is already installed"
    else
      git -C "$OMB_DIR" fetch --quiet --depth=1 origin "$commit"
      git -C "$OMB_DIR" checkout --quiet --detach FETCH_HEAD
      ok "Oh My Bash moved to ${commit:0:12}"
    fi
  else
    if [[ -e $OMB_DIR ]] && [[ -n "$(ls -A "$OMB_DIR" 2>/dev/null)" ]]; then
      warn "$OMB_DIR exists and is not an Oh My Bash clone; leaving it alone"; return 1
    fi
    mkdir -p "$OMB_DIR"
    git init --quiet "$OMB_DIR"
    git -C "$OMB_DIR" remote add origin "$OMB_REPO"
    git -C "$OMB_DIR" fetch --quiet --depth=1 origin "$commit"
    git -C "$OMB_DIR" checkout --quiet --detach FETCH_HEAD
    record_undo "rm -rf $(printf %q "$OMB_DIR")"
    ok "Installed Oh My Bash ${commit:0:12} to $OMB_DIR"
  fi
  install_file .bashrc.d/15-oh-my-bash.sh
}

shell_setup() {
  mkdir -p "$HOME/.bashrc.d"
  if ! on "$ENABLE_SHELL_LOADER"; then
    log "ENABLE_SHELL_LOADER=0: ~/.bashrc is left alone (see the Summary for the line to add)"
  elif ! grep -q 'bashrc.d' "$HOME/.bashrc" 2>/dev/null; then
    cat >> "$HOME/.bashrc" <<'EOF'

# >>> workstation-setup: load ~/.bashrc.d/*.sh >>>
if [ -d "$HOME/.bashrc.d" ]; then
  for f in "$HOME"/.bashrc.d/*.sh; do [ -r "$f" ] && . "$f"; done
  unset f
fi
# <<< workstation-setup <<<
EOF
    record_undo "sed -i '/# >>> workstation-setup/,/# <<< workstation-setup <<</d' ~/.bashrc"
    ok "Added ~/.bashrc.d loader to ~/.bashrc"
  fi

  install_file .bashrc.d/10-workstation.sh
  if on "$ENFORCE_OFFLINE_ENV"; then install_file .bashrc.d/20-offline.sh; fi
  install_file .inputrc
  install_file .local/bin/ws-init 755
  install_file .local/bin/ws-doctor 755
  install_cheatsheet

  if on "$INSTALL_STARSHIP" && ! on "$INSTALL_OH_MY_BASH" && ! have starship; then
    if apt_has starship; then
      apt_install starship
    elif on "$ALLOW_CURL_INSTALLERS"; then
      local sasset; sasset="$(starship_asset)"
      fetch_published "$(starship_base_url)/$sasset" "$STATE_DIR/$sasset" "$(starship_base_url)/$sasset.sha256"
      mkdir -p "$HOME/.local/bin"
      tar -xzf "$STATE_DIR/$sasset" -C "$HOME/.local/bin" starship
      record_undo "rm -f ~/.local/bin/starship"
    fi
  fi
  if have starship && [[ ! -e "$HOME/.config/starship.toml" ]]; then
    mkdir -p "$HOME/.config"
    # Icons only if the terminal will really use the Nerd Font (we set it ourselves);
    # otherwise plain-text symbols, which need no special font.
    local preset=plain-text-symbols
    if on "$INSTALL_NERD_FONT" && on "$SET_GNOME_FONT"; then preset=nerd-font-symbols; fi
    if starship preset "$preset" -o "$HOME/.config/starship.toml"; then
      record_undo "rm -f ~/.config/starship.toml"
    fi
  fi
}

git_setup() {
  git_set() {
    git config --global --get "$1" >/dev/null && return 0
    git config --global "$1" "$2"
    record_undo "git config --global --unset $1"
  }
  # An identity you give explicitly (GIT_NAME / GIT_EMAIL) is always applied.
  if [[ -n "$GIT_NAME"  ]]; then git_set user.name  "$GIT_NAME"; fi
  if [[ -n "$GIT_EMAIL" ]]; then git_set user.email "$GIT_EMAIL"; fi
  if on "$SET_GIT_DEFAULTS"; then git_defaults; else log "SET_GIT_DEFAULTS=0: global git settings are left alone"; fi
  # lazygit checks GitHub for new versions by default; turn that off.
  install_file .config/lazygit/config.yml
}

git_defaults() {
  git_set init.defaultBranch main
  git_set pull.rebase true
  git_set rerere.enabled true
  git_set fetch.prune true
  git_set push.autoSetupRemote true
  git_set merge.conflictStyle zdiff3
  git_set diff.colorMoved default
  if have delta; then
    git_set core.pager delta
    git_set interactive.diffFilter "delta --color-only"
    git_set delta.navigate true
    git_set delta.line-numbers true
  fi
  if have git-lfs; then git lfs install --skip-repo >/dev/null; fi
  ok "Git defaults set (existing settings were kept)"
}

project_templates() {
  install_templates "$FILES/templates" generic
}

desktop_tweaks() {
  have gsettings || return 0
  if ! have_desktop_session; then
    warn "No desktop session detected; run setup.sh from a logged-in desktop"
    warn "to apply font and GNOME privacy settings."
    return 0
  fi
  # Recent Ubuntu releases use a small default monospace font; the terminal follows this.
  if on "$SET_GNOME_FONT"; then gset org.gnome.desktop.interface monospace-font-name "$(gnome_mono_font)"; fi
  if on "$SET_GNOME_PRIVACY"; then
    gset org.gnome.system.location enabled false
    gset org.gnome.desktop.datetime automatic-timezone false
    gset org.gnome.desktop.privacy report-technical-problems false
    gset org.gnome.desktop.privacy send-software-usage-stats false
    # Also turns off the web-search and Snap Store search providers in the
    # Activities overview (searching for installed apps still works).
    gset org.gnome.desktop.search-providers disable-external true
  fi
}

# ============================================================================
# OFFLINE CACHES (downloaded now, used offline afterwards)
# ============================================================================
cache_python() {
  have uv || { warn "uv is not installed"; return 1; }
  mkdir -p "$WHEELHOUSE"
  local venv="$STATE_DIR/pydl"
  UV_PYTHON_DOWNLOADS=never uv venv --quiet --python /usr/bin/python3 "$venv"
  uv pip install --quiet --python "$venv/bin/python" pip
  local dl=("$venv/bin/python" -m pip download --quiet --disable-pip-version-check
            --only-binary=:all: --dest "$WHEELHOUSE")
  "${dl[@]}" pip setuptools wheel
  local p name spec pkgs
  mapfile -t pkgs < <(py_package_list)
  for p in "${pkgs[@]}"; do
    name="$(py_norm "$p")"
    spec="$p"
    if [[ -n ${PY_PINS[$name]:-} ]]; then spec="$name==${PY_PINS[$name]}"; fi
    if "${dl[@]}" "$spec"; then
      ok "Cached $spec"
    else
      warn "Could not cache $spec (no wheel for this Python?)"
      echo "$p (python wheel)" >> "$MISSING_FILE"
    fi
  done
  ok "Wheelhouse: $(find "$WHEELHOUSE" -name '*.whl' | wc -l) wheels, $(du -sh "$WHEELHOUSE" | cut -f1) in $WHEELHOUSE"
}

cache_rust() {
  have cargo || { warn "cargo is not installed"; return 1; }
  local proj="$RUST_CACHE_DIR" c
  mkdir -p "$proj/src"
  printf '#![no_std]\n' > "$proj/src/lib.rs"
  {
    printf '[package]\nname = "workstation-offline-cache"\nversion = "0.0.0"\nedition = "2021"\npublish = false\n\n[dependencies]\n'
    while IFS= read -r c; do printf '%s = "*"\n' "$c"; done < <(rust_crate_list)
  } > "$proj/Cargo.toml"
  if on "$UPGRADE"; then
    rm -f "$proj/Cargo.lock"      # resolve every crate to its newest release
  elif [[ -f "$CARGO_LOCK_FILE" ]]; then
    cp "$CARGO_LOCK_FILE" "$proj/Cargo.lock"
    if (cd "$proj" && cargo fetch --locked); then
      ok "Fetched pinned crate versions (${CARGO_LOCK_FILE##*/})"
      return 0
    fi
    warn "Crate list differs from ${CARGO_LOCK_FILE##*/}; fetching latest versions (re-pin with --lock)"
    rm -f "$proj/Cargo.lock"
  fi
  (cd "$proj" && cargo fetch)
  ok "Crate cache ready: $(grep -c '^name = ' "$proj/Cargo.lock") crates"
}

cache_images() {
  have podman || { warn "podman is not installed"; return 1; }
  local img repo digest
  for img in $OFFLINE_CONTAINER_IMAGES; do
    digest="${IMAGE_PINS[$img]:-}"
    if [[ -n $digest ]]; then
      repo="${img%:*}"
      if podman pull "$repo@$digest" && podman tag "$repo@$digest" "$img"; then
        ok "Pulled $img (pinned $digest)"
      else
        warn "Could not pull $img"; echo "$img (container image)" >> "$MISSING_FILE"; continue
      fi
    else
      if podman pull "$img"; then ok "Pulled $img"
      else warn "Could not pull $img"; echo "$img (container image)" >> "$MISSING_FILE"; continue; fi
    fi
    record_undo "if podman image exists $img; then podman rmi $img; fi"
  done

  # From now on, never pull images implicitly. Guard against an incompatible
  # podman version: if podman rejects the file, remove it again.
  local conf="$HOME/.config/containers/containers.conf" existed=0
  [[ -e $conf ]] && existed=1
  install_file .config/containers/containers.conf
  if ! podman info >/dev/null 2>&1; then
    if (( existed == 0 )); then rm -f "$conf"; fi
    warn "podman did not accept containers.conf (pull_policy); left it out"
    return 1
  fi
}

# ============================================================================
# DRY RUN (--check)
# ============================================================================
plan_tool() {
  local label="$1" cmd="$2" pkg="$3" url="$4" how
  if have "$cmd"; then how="already installed"
  elif apt_has "$pkg"; then how="from the Ubuntu archive (package $pkg)"
  elif on "$ALLOW_CURL_INSTALLERS"; then
    if [[ -n ${DOWNLOAD_SHA256[$url]:-} ]]; then how="download $url (SHA-256 pinned)"
    else how="download $url (SHA-256 recorded on first use)"; fi
  else how="${c_yellow}SKIPPED: not in archive and ALLOW_CURL_INSTALLERS=0${c_off}"; fi
  printf '    %-10s %s\n' "$label" "$how"
}

plan_versions() {
  local label="$1" pins="$2"; shift 2
  local -n _pins="$pins"
  local t
  printf '    %s\n' "$label"
  for t in "$@"; do
    if [[ -n ${_pins[$t]:-} ]]; then printf '      %-24s pinned %s\n' "$t" "${_pins[$t]}"
    else printf '      %-24s latest\n' "$t"; fi
  done
}

check_mode() {
  section "Dry run: nothing will be changed"
  # shellcheck disable=SC1091
  . /etc/os-release
  log "System:  ${PRETTY_NAME:-unknown}, kernel $(uname -r), $(uname -m)"
  os_check
  if [[ -n $OS_PROBLEM ]]; then warn "$OS_PROBLEM"
  elif (( OS_VERIFIED )); then ok "Latest Ubuntu LTS release"; fi
  log "Profile: $PROFILE   modules: core${MODULES[*]:+ }${MODULES[*]}"
  log "Config:  $CONF_FILE"
  if [[ -f $LOCK_FILE ]]; then log "Lock:    $LOCK_FILE (versions pinned)"
  else log "Lock:    none, latest versions will be installed (pin them later with --lock)"; fi
  local newest age
  newest="$(find /var/lib/apt/lists -maxdepth 1 -name '*_Packages*' -printf '%T@\n' 2>/dev/null | sort -n | tail -n1)"
  if [[ -n $newest ]]; then
    age=$(( ( $(date +%s) - ${newest%.*} ) / 3600 ))
    if (( age >= 24 )); then warn "Package lists are ${age}h old. For accurate results run first:  sudo apt update"; fi
  else
    warn "No package lists found. For accurate results run first:  sudo apt update"
  fi

  section "APT packages"
  local g pkg cand inst ver s1 s2 s3 n_have=0 n_new=0 n_missing=0
  local -a pkgs=() to_install=() all=()
  local -A CAND=() INST=()
  for g in $(pkg_groups); do mapfile -t pkgs < <(array_items "$g"); all+=("${pkgs[@]}"); done
  # Two batched queries instead of one per package.
  while read -r pkg ver; do CAND[$pkg]=$ver; done < <(apt_candidates "${all[@]}")
  # shellcheck disable=SC2034  # s1, s2 only consume dpkg-query columns
  while read -r pkg s1 s2 s3 ver; do
    if [[ $s3 == installed ]]; then INST[$pkg]=$ver; fi
  done < <(dpkg-query -W -f='${Package} ${Status} ${Version}\n' "${all[@]}" 2>/dev/null || true)
  for g in $(pkg_groups); do
    mapfile -t pkgs < <(array_items "$g")
    (( ${#pkgs[@]} )) || continue
    printf '\n  %s\n' "$g"
    for pkg in "${pkgs[@]}"; do
      inst="${INST[$pkg]:-}"
      cand="${CAND[$pkg]:-}"
      if [[ -n $inst ]]; then
        printf '    %-34s installed (%s)\n' "$pkg" "$inst"; n_have=$((n_have + 1))
      elif [[ -n $cand ]]; then
        printf '    %-34s will install %s\n' "$pkg" "$cand"; to_install+=("$pkg"); n_new=$((n_new + 1))
      else
        printf '    %-34s %sNOT AVAILABLE (will be skipped)%s\n' "$pkg" "$c_yellow" "$c_off"
        n_missing=$((n_missing + 1))
      fi
    done
  done
  echo
  log "$n_have installed, $n_new to install, $n_missing not available"
  if (( ${#to_install[@]} )); then
    local sim
    if sim="$(apt-get install -s --no-remove --no-upgrade "${to_install[@]}" 2>&1)"; then
      ok "Simulation: $(grep -c '^Inst ' <<<"$sim" || true) packages incl. dependencies would be installed, none removed"
    else
      warn "Simulation found a conflict. Setup would skip the affected packages:"
      grep -E '^ [^ ]+ : (Depends|PreDepends|Conflicts|Breaks)' <<<"$sim" | sed 's/^ */      /' || true
      grep -E '^E: ' <<<"$sim" | sed 's/^/      /' || true
      warn "Often caused by a third-party repository (e.g. NodeSource). Inspect with:"
      warn "  apt-get install -s <package>"
    fi
  fi

  section "Tools installed outside APT"
  if on "$INSTALL_PYTHON"; then plan_tool uv uv uv "$(uv_base_url)/$(uv_asset) (checked against the published .sha256)"; fi
  if on "$INSTALL_RUST"; then plan_tool rustup rustup rustup "$(rustup_init_url) (checked against the published .sha256)"; fi
  if on "$INSTALL_HELIX"; then
    if [[ -n ${HELIX_VERSION:-} ]]; then plan_tool Helix hx helix "$(helix_url "$HELIX_VERSION")"
    else plan_tool Helix hx helix "https://github.com/helix-editor/helix/releases/latest"; fi
  fi
  if on "$INSTALL_STARSHIP" && ! on "$INSTALL_OH_MY_BASH"; then plan_tool starship starship starship "$(starship_base_url)/$(starship_asset) (checked against the published .sha256)"; fi
  if on "$INSTALL_NERD_FONT"; then printf '    %-10s %s\n' "Nerd Font" "download JetBrainsMono.tar.xz from github.com/ryanoasis/nerd-fonts (${NERD_FONT_VERSION:-newest stable}; checked against the published SHA-256.txt)"; fi
  if on "$INSTALL_OH_MY_BASH"; then printf '    %-10s %s\n' "Oh My Bash" "git clone of ONE commit (${OH_MY_BASH_COMMIT:-current HEAD}) from github.com/ohmybash/oh-my-bash"; fi
  echo
  if on "$INSTALL_RUST"; then printf '    Rust toolchain: %s\n' "$RUST_TOOLCHAIN"; fi
  if on "$INSTALL_PYTHON"; then
    local -a uvt; mapfile -t uvt < <(uv_tool_list)
    plan_versions "uv tools:" UV_PINS "${uvt[@]}"
  fi
  if on "$INSTALL_RUST" && on "$INSTALL_CARGO_TOOLS"; then
    local -a cat; mapfile -t cat < <(cargo_tool_list)
    plan_versions "cargo tools:" CARGO_PINS "${cat[@]}"
    mapfile -t cat < <(rust_target_list)
    if (( ${#cat[@]} )); then printf '    Rust targets: %s\n' "${cat[*]}"; fi
  fi
  if on "$INSTALL_BASH_LSP"; then plan_versions "npm tools:" NPM_PINS "${NPM_TOOLS[@]}"; fi

  section "Offline caches"
  local n img
  local -a items
  if on "$CACHE_PYTHON"; then
    mapfile -t items < <(py_package_list)
    n=0; for img in "${items[@]}"; do if [[ -n ${PY_PINS[$(py_norm "$img")]:-} ]]; then n=$((n + 1)); fi; done
    log "Python wheelhouse: ${#items[@]} packages + dependencies ($n pinned) -> $WHEELHOUSE"
  fi
  if on "$CACHE_RUST"; then
    mapfile -t items < <(rust_crate_list)
    if [[ -f "$CARGO_LOCK_FILE" ]]; then n="pinned by ${CARGO_LOCK_FILE##*/}"; else n="latest versions"; fi
    log "Rust crates: ${#items[@]} crates + dependencies ($n)"
  fi
  if on "$CACHE_CONTAINER_IMAGES"; then
    for img in $OFFLINE_CONTAINER_IMAGES; do
      if [[ -n ${IMAGE_PINS[$img]:-} ]]; then log "Container image: $img (pinned digest)"
      else log "Container image: $img (latest)"; fi
    done
  fi
  module_collect check_caches

  section "Planned system changes (only the switches that are ON; each recorded in an undo script)"
  if on "$TUNE_INOTIFY" && [[ ! -e /etc/sysctl.d/60-dev-inotify.conf ]]; then
    echo "    new file /etc/sysctl.d/60-dev-inotify.conf (more file watches for language servers)"
  fi
  local -a want_groups=()
  mapfile -t want_groups < <(needed_groups)
  for g in "${want_groups[@]}"; do
    if id -nG "$USER" | grep -qw "$g"; then echo "    group $g: already a member"
    else echo "    group $g: add $USER"; fi
  done
  local u state
  while IFS= read -r u; do
    state="$(systemctl is-enabled "$u" 2>/dev/null || true)"
    if [[ $state == enabled ]]; then echo "    service $u: disable"; fi
  done < <(enabled_privacy_units)
  if on "$DISABLE_APT_NEWS"; then echo "    APT news: off ('pro config set apt_news=false')"; fi
  if on "$DISABLE_NM_CONNECTIVITY_CHECK" && [[ -d /etc/NetworkManager/conf.d && ! -e $NM_CONNECTIVITY_CONF ]]; then
    echo "    new file $NM_CONNECTIVITY_CONF (no connectivity probe)"
  fi
  if on "$SET_GNOME_PRIVACY"; then echo "    GNOME: location services, automatic timezone, problem reporting, usage stats, external search providers off"; fi
  if on "$SET_GNOME_FONT"; then echo "    GNOME: monospace font JetBrains Mono 11"; fi
  if on "$ENABLE_SHELL_LOADER"; then echo "    ~/.bashrc: one marked block that loads ~/.bashrc.d"; fi
  if on "$SET_GIT_DEFAULTS"; then echo "    ~/.gitconfig: global git defaults (only options you have not set)"; fi
  module_collect check
  echo
  show_opt_in

  section "Files in your home directory"
  local rel target src
  while IFS= read -r rel; do
    target="$HOME/$rel"
    src="$(home_src "$rel")" || { echo "    MISSING SOURCE for ~/$rel"; continue; }
    if [[ ! -e $target ]]; then echo "    new       ~/$rel"
    elif cmp -s "$src" "$target"; then echo "    unchanged ~/$rel"
    elif on "$FORCE_CONFIG"; then echo "    replace   ~/$rel (backup kept)"
    else echo "    keep      ~/$rel (yours differs; FORCE_CONFIG=1 replaces it)"; fi
  done < <(home_files)
  echo "    generated ~/WORKSTATION-CHEATSHEET.md (refreshed; backup kept if you edited it)"
  echo "    templates ~/.local/share/workstation/templates (refreshed)"

  echo
  ok "Dry run complete. Nothing was changed. Run ./setup.sh to apply."
}

# ============================================================================
# SELF-TEST (--self-test)
# ============================================================================
skip()     { echo "SKIP: $*"; exit 77; }
needs()    { local t; for t in "$@"; do have "$t" || skip "$t not installed"; done; }
needs_on() { on "${!1:-0}" || skip "$1=0 in workstation.conf"; }

# run_test "title" function [module]
# Exit codes of a test: 0 pass, 77 skip, 78 warning (not a failure), else fail.
run_test() {
  local name="$1" fn="$2" tag="${3:-}" dir rc log label
  dir="$SELFTEST_DIR/$fn"
  rm -rf "$dir"; mkdir -p "$dir"
  log="$dir/output.log"
  label="$name"
  if [[ -n $tag ]]; then label="[$tag] $name"; fi
  set +e
  ( set -Eeuo pipefail; cd "$dir"; "$fn" ) > "$log" 2>&1
  rc=$?
  set -e
  case $rc in
    0)  T_PASS=$((T_PASS + 1))
        printf '  %sPASS%s  %s\n' "$c_green" "$c_off" "$label"
        echo "PASS  $label" >> "$SELFTEST_FILE" ;;
    77) T_SKIP=$((T_SKIP + 1))
        printf '  %sSKIP%s  %s (%s)\n' "$c_yellow" "$c_off" "$label" "$(sed -n 's/^SKIP: //p' "$log" | tail -n1)"
        echo "SKIP  $label" >> "$SELFTEST_FILE" ;;
    78) T_WARN=$((T_WARN + 1))
        printf '  %sWARN%s  %s\n' "$c_yellow" "$c_off" "$label"
        sed 's/^/          /' "$log" | tail -n 8
        echo "WARN  $label" >> "$SELFTEST_FILE" ;;
    *)  T_FAIL=$((T_FAIL + 1))
        printf '  %sFAIL%s  %s   (log: %s)\n' "$c_red" "$c_off" "$label" "$log"
        tail -n 8 "$log" | sed 's/^/          /'
        echo "FAIL  $label" >> "$SELFTEST_FILE" ;;
  esac
}

t_host_c() {
  needs gcc
  printf '#include <stdio.h>\nint main(void) { puts("host C OK"); return 0; }\n' > hello.c
  gcc -std=c17 -Wall -Wextra -Werror -O2 hello.c -o hello
  ./hello | grep -q "host C OK"
}

t_host_cpp() {
  needs clang++
  cat > hello.cpp <<'EOF'
#include <iostream>
#include <vector>
int main() { std::vector<int> v{1, 2, 3}; std::cout << "host C++ OK " << v.size() << '\n'; }
EOF
  clang++ -std=c++20 -Wall -Wextra -Werror hello.cpp -o hello
  ./hello | grep -q "host C++ OK"
}

t_sanitizers() {
  needs gcc
  cat > bug.c <<'EOF'
#include <stdlib.h>
int main(void) {
    volatile int *p = malloc(4 * sizeof *p);
    p[4] = 1;                 /* deliberate heap buffer overflow */
    free((void *)p);
    return 0;
}
EOF
  gcc -g -fsanitize=address,undefined bug.c -o bug
  if ./bug 2> asan.txt; then echo "AddressSanitizer did not detect the overflow"; exit 1; fi
  grep -q "heap-buffer-overflow" asan.txt
}

t_cmake_gtest() {
  needs cmake ninja g++
  cp -r "$FILES/selftest/gtest/." .
  cmake -S . -B build -G Ninja -DCMAKE_EXPORT_COMPILE_COMMANDS=ON
  cmake --build build
  ctest --test-dir build --output-on-failure
  test -s build/compile_commands.json
}

# Builds a template store from the repository files, so the test checks the
# files in this folder (not whatever was installed earlier).
selftest_template_store() {
  local dest="$1" m
  mkdir -p "$dest"
  cp -r "$FILES/templates" "$dest/generic"
  for m in "${MODULES[@]}"; do
    if [[ -d $MODULES_DIR/$m/files/templates ]]; then cp -r "$MODULES_DIR/$m/files/templates" "$dest/$m"; fi
  done
}

t_cmake_presets() {
  needs cmake ninja gcc
  cp -r "$FILES/selftest/presets/." .
  selftest_template_store "$PWD/tpl"
  WS_TEMPLATE_DIR="$PWD/tpl" "$FILES/home/.local/bin/ws-init" >/dev/null
  cmake --preset host-debug
  cmake --build --preset host-debug
  ctest --preset host-debug
  test -s build/host-debug/compile_commands.json
}

t_ws_init() {
  selftest_template_store "$PWD/tpl"
  mkdir proj && cd proj
  WS_TEMPLATE_DIR="$PWD/../tpl" "$FILES/home/.local/bin/ws-init" > init1.txt
  if grep -q embedded init1.txt; then echo "generic run copied module files"; return 1; fi
  test -f .editorconfig && test -f .clang-format && test -f .pre-commit-config.yaml && test -f CMakePresets.json
  echo keep > .editorconfig
  WS_TEMPLATE_DIR="$PWD/../tpl" "$FILES/home/.local/bin/ws-init" > init2.txt
  grep -q 'skip (exists): .editorconfig' init2.txt
  [[ "$(cat .editorconfig)" == keep ]]       # never overwrites
}

t_clangd_host() {
  needs clangd
  printf '%s\n' -std=c11 -Wall > compile_flags.txt
  printf '#include <stdio.h>\nint main(void) { printf("%%d\\n", 42); return 0; }\n' > x.c
  clangd --check=x.c
}

t_python_tools() {
  needs ruff basedpyright
  cat > sample.py <<'EOF'
"""Self-test sample."""


def add(a: int, b: int) -> int:
    """Return the sum of a and b."""
    return a + b


print(add(1, 2))
EOF
  ruff check sample.py
  ruff format --check sample.py
  basedpyright sample.py
}

t_python_offline() {
  needs_on CACHE_PYTHON
  needs uv
  [[ -d $WHEELHOUSE ]] || skip "wheelhouse not created yet"
  py_package_list | grep -qx pytest || skip "pytest not in OFFLINE_PY_PACKAGES"
  export UV_OFFLINE=1 UV_PYTHON_DOWNLOADS=never
  uv venv --quiet --python /usr/bin/python3 venv
  uv pip install --quiet --python venv/bin/python --no-index --find-links "$WHEELHOUSE" pytest
  printf 'def test_ok():\n    assert 1 + 1 == 2\n' > test_ok.py
  venv/bin/python -m pytest -q test_ok.py
}

t_rust_host() {
  needs rustc
  printf 'fn main() { println!("rust OK"); }\n' > main.rs
  rustc --edition 2021 main.rs -o main
  ./main | grep -q "rust OK"
}

t_rust_offline() {
  needs_on CACHE_RUST
  needs cargo
  [[ -f $RUST_CACHE_DIR/Cargo.lock ]] || skip "crate cache not created yet"
  rust_crate_list | grep -qx anyhow || skip "anyhow not in OFFLINE_RUST_CRATES"
  export CARGO_NET_OFFLINE=true
  cargo new --quiet --vcs none --lib offline_test
  cd offline_test
  cargo add --quiet anyhow
  cargo build --quiet
}

t_language_servers() {
  local want=() missing=() s
  if on "$INSTALL_CPP"; then want+=(clangd); fi
  if on "$INSTALL_RUST"; then want+=(rust-analyzer); fi
  if on "$INSTALL_PYTHON"; then want+=(ruff basedpyright-langserver cmake-language-server); fi
  if on "$INSTALL_RUST" && on "$INSTALL_CARGO_TOOLS"; then want+=(taplo); fi
  if on "$INSTALL_BASH_LSP"; then want+=(bash-language-server); fi
  (( ${#want[@]} )) || skip "no language servers enabled"
  for s in "${want[@]}"; do have "$s" || missing+=("$s"); done
  if have rust-analyzer; then rust-analyzer --version; fi
  if (( ${#missing[@]} )); then echo "missing: ${missing[*]}"; exit 1; fi
  echo "found: ${want[*]}"
}

t_helix() {
  needs_on INSTALL_HELIX
  local hx; hx="$(command -v hx || command -v helix || true)"
  [[ -n $hx ]] || { echo "Helix not found"; exit 1; }
  "$hx" --version
  "$hx" --health > health.txt 2>&1
  grep -qi 'error' health.txt && grep -i 'error' health.txt | head -n5 || true
  for lang in c cpp python rust; do "$hx" --health "$lang"; done
}

t_precommit_offline() {
  needs_on INSTALL_PYTHON
  needs pre-commit git trailing-whitespace-fixer clang-format ruff shellcheck
  export PRE_COMMIT_HOME="$PWD/pre-commit-cache"
  git init -q repo
  cd repo
  git config user.email selftest@localhost
  git config user.name selftest
  cp -r "$FILES/templates/." .
  cp "$FILES/selftest/presets/crc16.c" "$FILES/selftest/presets/crc16.h" .
  printf 'def ok() -> int:\n    return 1\n' > ok.py
  if grep -Eq '^[[:space:]]*-[[:space:]]*repo:[[:space:]]*https?://' .pre-commit-config.yaml; then
    echo "template references a remote hook repository"; exit 1
  fi
  git add -A
  pre-commit run --all-files || true      # first run may reformat files
  git add -A
  pre-commit run --all-files              # second run must be clean
}

t_containers() {
  needs_on CACHE_CONTAINER_IMAGES
  needs podman
  local img missing=()
  for img in $OFFLINE_CONTAINER_IMAGES; do podman image exists "$img" || missing+=("$img"); done
  if (( ${#missing[@]} )); then echo "not available offline: ${missing[*]}"; exit 1; fi
  timeout 120 podman run --rm --network=none "${OFFLINE_CONTAINER_IMAGES%% *}" true
  echo "all images present; container ran without network"
}

t_groups() {
  local want=() g missing=() pending=()
  mapfile -t want < <(needed_groups)
  (( ${#want[@]} )) || skip "no groups needed"
  for g in "${want[@]}"; do
    if ! getent group "$g" | cut -d: -f4 | tr ',' '\n' | grep -qx "$USER"; then missing+=("$g")
    elif ! id -nG | grep -qw "$g"; then pending+=("$g"); fi
  done
  if (( ${#missing[@]} )); then echo "not a member of: ${missing[*]}"; exit 1; fi
  if (( ${#pending[@]} )); then echo "member of ${pending[*]}; log out and back in to activate"; fi
}

# Core checks plus those of every module (hook nocloud_problems prints one
# line per problem, nocloud_warnings one per warning). Problems fail the
# test; warnings only report (status WARN).
t_nocloud_policy() {
  local problems=() warnings=() u line
  if have gh; then problems+=("gh (GitHub CLI) is installed"); fi
  if have lazygit && ! grep -q 'method: never' "$HOME/.config/lazygit/config.yml" 2>/dev/null; then
    problems+=("lazygit update check is not disabled"); fi
  if have uv && ! grep -q 'python-downloads = "never"' "$HOME/.config/uv/uv.toml" 2>/dev/null; then
    problems+=("uv may download Python interpreters"); fi
  if have tldr && ! grep -q 'auto_update = false' "$HOME/.config/tealdeer/config.toml" 2>/dev/null; then
    problems+=("tldr auto-update is not disabled"); fi
  if have npm && [[ "$(npm config get update-notifier 2>/dev/null)" != false ]]; then
    problems+=("npm update notifier is enabled"); fi
  if [[ -f "$HOME/.config/helix/languages.toml" ]]; then
    python3 -I - "$HOME/.config/helix/languages.toml" <<'EOF' || problems+=("Helix JSON/YAML language servers are enabled")
import sys, tomllib
langs = {l["name"]: l for l in tomllib.load(open(sys.argv[1], "rb")).get("language", [])}
sys.exit(0 if all(langs.get(n, {}).get("language-servers") == [] for n in ("json", "yaml")) else 1)
EOF
  fi
  if have podman \
     && ! grep -q 'pull_policy = "never"' "$HOME/.config/containers/containers.conf" 2>/dev/null; then
    problems+=("podman may pull images implicitly"); fi
  if on "$ENFORCE_OFFLINE_ENV" && [[ ! -f "$HOME/.bashrc.d/20-offline.sh" ]]; then
    problems+=("offline environment (~/.bashrc.d/20-offline.sh) missing"); fi
  if grep -Eq 'repo:[[:space:]]*https?://' "$TEMPLATE_DIR/generic/.pre-commit-config.yaml" 2>/dev/null; then
    problems+=("pre-commit template references remote repositories"); fi
  # Only what you switched on is checked; the rest stays as Ubuntu ships it
  # (listed by './setup.sh --explain').
  if have systemctl; then
    while IFS= read -r u; do
      if [[ "$(systemctl is-enabled "$u" 2>/dev/null || true)" == enabled ]]; then problems+=("$u is enabled"); fi
    done < <(enabled_privacy_units)
  fi
  if on "$DISABLE_NM_CONNECTIVITY_CHECK" && [[ -d /etc/NetworkManager/conf.d && ! -f $NM_CONNECTIVITY_CONF ]]; then
    problems+=("NetworkManager connectivity check is enabled"); fi
  # The runtime offline lock lives in ~/.bashrc.d; without the loader it is not active.
  if on "$ENFORCE_OFFLINE_ENV" && ! grep -q 'bashrc.d' "$HOME/.bashrc" 2>/dev/null; then
    warnings+=("~/.bashrc does not load ~/.bashrc.d, so the offline lock for uv/pip/cargo is not active in new shells (ENABLE_SHELL_LOADER=1, or add the loader yourself)"); fi
  if on "$INSTALL_KATE" && have kate; then
    # Kate's default JSON/YAML language servers download schemas from the internet:
    # fine while they are not installed, a policy problem if someone installs them.
    for u in vscode-json-languageserver yaml-language-server; do
      if have "$u"; then problems+=("$u is installed: Kate would use it, and it fetches schemas online"); fi
    done
    [[ -f $HOME/.config/kate/lspclient/settings.json ]] || problems+=("Kate LSP settings missing (~/.config/kate/lspclient/settings.json)")
  fi
  if on "$INSTALL_OH_MY_BASH"; then
    local omb_file="$HOME/.bashrc.d/15-oh-my-bash.sh"
    if [[ ! -f $omb_file ]]; then problems+=("Oh My Bash is enabled but $omb_file is missing")
    elif ! grep -q '^export DISABLE_AUTO_UPDATE=true' "$omb_file"; then
      problems+=("Oh My Bash would check GitHub for updates (DISABLE_AUTO_UPDATE is not true)"); fi
  fi
  # GNOME Online Accounts (Google, Microsoft, Nextcloud, ...) sync in the background.
  if grep -q '^\[Account' "${XDG_CONFIG_HOME:-$HOME/.config}/goa-1.0/accounts.conf" 2>/dev/null; then
    warnings+=("GNOME Online Accounts: an online account is set up (Settings > Online Accounts); it syncs in the background"); fi
  while IFS= read -r line; do problems+=("$line"); done < <(module_collect nocloud_problems)
  while IFS= read -r line; do warnings+=("$line"); done < <(module_collect nocloud_warnings)
  if (( ${#problems[@]} )); then printf 'policy problem: %s\n' "${problems[@]}"; exit 1; fi
  if (( ${#warnings[@]} )); then printf 'warning: %s\n' "${warnings[@]}"; exit 78; fi
  echo "all no-cloud policy checks passed"
}

t_offline_docs() {
  needs_on INSTALL_OFFLINE_DOCS
  needs man
  local missing=()
  man -w 3 printf >/dev/null 2>&1 || missing+=("C library man pages")
  man -w 3posix pthread_create >/dev/null 2>&1 || missing+=("POSIX man pages")
  compgen -G '/usr/share/cppreference/doc/html/*index.html' >/dev/null \
    || compgen -G '/usr/share/cppreference/doc/html/*/index.html' >/dev/null || missing+=("cppreference")
  compgen -G '/usr/share/doc/python3*/html/index.html' >/dev/null || missing+=("Python docs")
  compgen -G '/usr/share/doc/cmake*/html/index.html' >/dev/null || missing+=("CMake docs")
  if have rustup; then rustup doc --path >/dev/null 2>&1 || missing+=("Rust docs"); fi
  if (( ${#missing[@]} )); then printf 'missing: %s\n' "${missing[@]}"; exit 1; fi
  echo "all offline documentation present"
}

t_ccache() {
  needs ccache cmake ninja gcc
  # 10-workstation.sh must turn ccache on for CMake builds...
  local launcher
  launcher="$(bash --norc -c '. "$1" >/dev/null 2>&1; echo "$CMAKE_C_COMPILER_LAUNCHER"' _ "$FILES/home/.bashrc.d/10-workstation.sh")"
  [[ $launcher == ccache ]] || { echo "CMAKE_C_COMPILER_LAUNCHER is '$launcher', not ccache"; exit 1; }
  # ...and a second build in a fresh build directory must hit the cache.
  export CCACHE_DIR="$PWD/cc" CMAKE_C_COMPILER_LAUNCHER=ccache
  cp -r "$FILES/selftest/presets/." .
  ccache --zero-stats >/dev/null
  local i
  for i in 1 2; do
    rm -rf "build$i"
    cmake -S . -B "build$i" -G Ninja >/dev/null
    cmake --build "build$i" >/dev/null
  done
  ccache --print-stats | awk -F'\t' '$1 == "direct_cache_hit" || $1 == "preprocessed_cache_hit" { s += $2 } END { exit !(s > 0) }' \
    || { ccache -s; echo "no cache hit on the second build"; exit 1; }
  echo "second build was served from the ccache"
}

t_ws_doctor() {
  # It must run on its own (no repo needed) and print its summary; whether it
  # reports problems depends on the machine, so only a crash fails this test.
  local out rc=0
  out="$("$FILES/home/.local/bin/ws-doctor" --quiet 2>&1)" || rc=$?
  (( rc <= 1 )) || { echo "$out"; exit 1; }
  grep -q 'ws-doctor summary' <<<"$out" || { echo "$out"; exit 1; }
  tail -n 1 <<<"$out"
}

t_kate() {
  needs_on INSTALL_KATE
  needs kate
  python3 -I - "$HOME/.config/kate/lspclient/settings.json" <<'EOT'
import json, sys
servers = json.load(open(sys.argv[1]))["servers"]
assert servers["python"]["servers"]["basedpyright"]["command"][0] == "basedpyright-langserver"
print("Kate LSP settings parse; servers:", ", ".join(sorted(servers)))
EOT
  QT_QPA_PLATFORM=offscreen kate --version
}

t_nerd_font() {
  needs_on INSTALL_NERD_FONT
  needs fc-list
  local fonts; fonts="$(fc-list : family 2>/dev/null || true)"
  [[ $fonts == *'JetBrainsMono Nerd Font Mono'* ]] || { echo "JetBrainsMono Nerd Font Mono not found by fontconfig"; exit 1; }
  echo "found: $(grep -c 'JetBrainsMono Nerd Font' <<<"$fonts") font entries"
}

t_oh_my_bash() {
  needs_on INSTALL_OH_MY_BASH
  needs git
  [[ -d $OMB_DIR/.git ]] || { echo "Oh My Bash is not installed in $OMB_DIR"; exit 1; }
  # Load it exactly like a new interactive shell would, without ~/.bashrc, and
  # check that the update check is off and the framework came up.
  local out
  # shellcheck disable=SC2016  # the commands run in the child shell, not here
  out="$(env -i HOME="$HOME" TERM=dumb PATH="$PATH" bash --norc -i -c \
    '. ~/.bashrc.d/15-oh-my-bash.sh; echo "update=$DISABLE_AUTO_UPDATE"; echo "theme=$OSH_THEME"; declare -F _omb_util_command_exists >/dev/null && echo "framework=loaded"' 2>&1)"
  grep -q 'update=true' <<<"$out" || { echo "$out"; exit 1; }
  grep -q 'framework=loaded' <<<"$out" || { echo "$out"; exit 1; }
  echo "Oh My Bash loads; auto-update is off"
}

self_test() {
  section "Self-test (profile: $PROFILE, modules: core${MODULES[*]:+ }${MODULES[*]})"
  mkdir -p "$SELFTEST_DIR"
  {
    echo "# Self-test $(date -u '+%Y-%m-%d %H:%M UTC') on $(hostname), profile $PROFILE"
  } > "$SELFTEST_FILE"
  T_PASS=0; T_FAIL=0; T_SKIP=0; T_WARN=0
  run_test "Host C compiler (gcc)"                    t_host_c
  run_test "Host C++ compiler (clang++)"              t_host_cpp
  run_test "Sanitizers detect a real bug"             t_sanitizers
  run_test "CMake + Ninja + GoogleTest"               t_cmake_gtest
  run_test "CMake presets template (host)"            t_cmake_presets
  run_test "ws-init copies starter files, never overwrites" t_ws_init
  run_test "clangd understands host code"             t_clangd_host
  run_test "Python: ruff + basedpyright"              t_python_tools
  run_test "Python: offline install from wheelhouse"  t_python_offline
  run_test "Rust: host build"                         t_rust_host
  run_test "Rust: offline build from crate cache"     t_rust_offline
  run_test "Language servers present"                 t_language_servers
  run_test "Helix loads its configuration"            t_helix
  run_test "pre-commit runs fully offline"            t_precommit_offline
  run_test "Container images available offline"       t_containers
  run_test "Group memberships"                        t_groups
  run_test "No-cloud policy"                          t_nocloud_policy
  run_test "Offline documentation"                    t_offline_docs
  run_test "JetBrains Mono Nerd Font installed"       t_nerd_font
  run_test "Kate starts and its LSP settings parse"   t_kate
  run_test "ws-doctor runs on its own"                t_ws_doctor
  run_test "ccache speeds up a CMake rebuild"         t_ccache
  run_test "Oh My Bash loads with updates off"        t_oh_my_bash
  module_collect selftests
  echo
  local summary_line="$T_PASS passed, $T_FAIL failed, $T_WARN warnings, $T_SKIP skipped"
  echo "# $summary_line" >> "$SELFTEST_FILE"
  if (( T_FAIL )); then warn "Self-test: $summary_line   (logs in $SELFTEST_DIR)"
  else ok "Self-test: $summary_line"; fi
  (( T_FAIL == 0 ))
}

# ============================================================================
# MANIFEST (--manifest)
# ============================================================================
write_manifest() {
  section "Manifest"
  MANIFEST_FILE="$HOME/workstation-manifest-$TIMESTAMP.txt"
  (
    set +e +o pipefail
    echo "# Workstation manifest"
    echo "# Generated $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
    echo
    echo "## Machine"
    echo "Host:      $(hostname)"
    echo "User:      $USER"
    echo "OS:        $(. /etc/os-release; echo "$PRETTY_NAME")"
    echo "Kernel:    $(uname -r) ($(uname -m))"
    echo "CPU:       $(awk -F': ' '/model name/ { print $2; exit }' /proc/cpuinfo)"
    echo
    echo "## Setup"
    echo "Profile:   $PROFILE   modules: core${MODULES[*]:+ }${MODULES[*]}"
    echo "Script:    $SCRIPT_PATH  sha256 $(sha256sum "$SCRIPT_PATH" | cut -d' ' -f1)"
    if git -C "$SCRIPT_DIR" rev-parse HEAD >/dev/null 2>&1; then
      echo "Git:       $(git -C "$SCRIPT_DIR" rev-parse HEAD)$(git -C "$SCRIPT_DIR" diff --quiet HEAD -- . || echo ' (uncommitted changes)')"
    fi
    echo "Config:    $CONF_FILE  sha256 $(sha256sum "$CONF_FILE" | cut -d' ' -f1)"
    if [[ -f $LOCK_FILE ]]; then echo "Lock:      $LOCK_FILE  sha256 $(sha256sum "$LOCK_FILE" | cut -d' ' -f1)"
    else echo "Lock:      (none: versions not pinned)"; fi
    echo
    if [[ -s $NERD_FONT_DIR/.version ]]; then echo "Nerd Font:  JetBrainsMono $(<"$NERD_FONT_DIR/.version")"; fi
    if [[ -d $OMB_DIR/.git ]]; then echo "Oh My Bash: $(git -C "$OMB_DIR" rev-parse HEAD)"; fi
    echo "## Key tools"
    local t
    local -a key_tools
    mapfile -t key_tools < <(printf '%s\n' gcc g++ clang clangd clang-format clang-tidy cmake ninja make gdb \
             cppcheck valgrind python3 uv ruff basedpyright pre-commit rustc cargo rust-analyzer \
             hx node npm podman docker git; module_collect manifest_tools)
    for t in "${key_tools[@]}"; do
      if have "$t"; then printf '%-26s %s\n' "$t" "$(first_line "$t" --version)"; fi
    done
    echo
    echo "## Rust"
    if have rustup; then rustup show active-toolchain; echo "Targets:"; rustup target list --installed | sed 's/^/  /'; fi
    if have cargo; then echo "cargo install --list:"; cargo install --list | sed 's/^/  /'; fi
    echo
    echo "## Python tools (uv tool list)"
    if have uv; then uv tool list; fi
    echo
    echo "## npm global packages"
    if have npm; then npm ls -g --depth=0; fi
    echo
    echo "## Offline caches"
    if [[ -d $WHEELHOUSE ]]; then
      echo "Wheelhouse ($WHEELHOUSE), sha256:"
      (cd "$WHEELHOUSE" && sha256sum -- *.whl | sed 's/^/  /')
    fi
    if [[ -f $RUST_CACHE_DIR/Cargo.lock ]]; then
      echo "Rust crate cache Cargo.lock sha256 $(sha256sum "$RUST_CACHE_DIR/Cargo.lock" | cut -d' ' -f1)"
    fi
    if have podman; then echo "Container images:"; podman images --digests --format '  {{.Repository}}:{{.Tag}} {{.Digest}}'; fi
    module_collect manifest_extra
    echo
    echo "## Downloads outside APT (url sha256)"
    if [[ -f $HASH_DB ]]; then sort -u "$HASH_DB"; else echo "(none)"; fi
    echo
    echo "## Self-test"
    if [[ -f $SELFTEST_FILE ]]; then cat "$SELFTEST_FILE"; else echo "(not run)"; fi
    echo
    echo "## APT packages (all installed: name, version, architecture)"
    dpkg-query -W -f='${Package}\t${Version}\t${Architecture}\n' | sort
  ) > "$MANIFEST_FILE" 2>&1
  ln -sf "$MANIFEST_FILE" "$HOME/workstation-manifest-latest.txt"
  ok "Manifest: $MANIFEST_FILE ($(wc -l < "$MANIFEST_FILE") lines)"
}

# ============================================================================
# LOCK (--lock)
# ============================================================================
write_lock() {
  section "Pinning installed versions"
  local tmp; tmp="$(mktemp)"
  local -a uvt cargot pyp
  mapfile -t uvt < <(uv_tool_list)
  mapfile -t cargot < <(cargo_tool_list)
  mapfile -t pyp < <(py_package_list)
  mkdir -p "$(dirname "$LOCK_FILE")"
  (
    set +e +o pipefail
    echo "# ${LOCK_FILE##*/} — exact versions for setup.sh, generated by: ./setup.sh --profile $PROFILE --lock"
    echo "# Profile: $PROFILE   modules: core${MODULES[*]:+ }${MODULES[*]}"
    echo "# Generated $(date -u '+%Y-%m-%d %H:%M UTC') on $(hostname) ($(. /etc/os-release; echo "$PRETTY_NAME"))"
    cat <<'EOF'
#
# Pins the exact versions of everything NOT managed by APT, so every machine
# set up from this folder with this profile gets identical tools. Commit it to
# version control (together with the matching .Cargo.lock). After a deliberate
# upgrade, regenerate it with:  ./setup.sh --profile <profile> --lock
#
# APT packages are intentionally not pinned: that would block Ubuntu security
# updates. Their exact versions are recorded in each machine's manifest.

EOF
    # The format strings are literal on purpose: they write ': "${X:=value}"'.
    # shellcheck disable=SC2016
    if have rustc; then printf ': "${RUST_TOOLCHAIN:=%s}"\n' "$(rustc --version | awk '{ print $2 }')"; fi
    # shellcheck disable=SC2016
    if have uv;    then printf ': "${UV_VERSION:=%s}"\n' "$(uv --version | awk '{ print $2 }')"; fi
    local hx; hx="$(command -v hx || command -v helix || true)"
    # shellcheck disable=SC2016
    if [[ -n $hx ]]; then printf ': "${HELIX_VERSION:=%s}"\n' "$("$hx" --version | awk '{ print $2 }')"; fi
    # shellcheck disable=SC2016
    if [[ -s $NERD_FONT_DIR/.version ]]; then printf ': "${NERD_FONT_VERSION:=%s}"\n' "$(<"$NERD_FONT_DIR/.version")"; fi
    # shellcheck disable=SC2016
    if [[ -d $OMB_DIR/.git ]]; then printf ': "${OH_MY_BASH_COMMIT:=%s}"\n' "$(git -C "$OMB_DIR" rev-parse HEAD)"; fi
    module_collect lock_pins
    echo

    echo "declare -gA UV_PINS=("
    if have uv; then
      uv tool list 2>/dev/null | awk -v want=" ${uvt[*]} " \
        '$2 ~ /^v[0-9]/ && index(want, " " $1 " ") { sub(/^v/, "", $2); printf "  [\"%s\"]=\"%s\"\n", $1, $2 }'
    fi
    echo ")"

    echo "declare -gA CARGO_PINS=("
    if have cargo; then
      cargo install --list 2>/dev/null | awk -v want=" ${cargot[*]} " \
        '/^[^ ].* v[0-9][^ ]*:$/ && index(want, " " $1 " ") { v = $2; sub(/^v/, "", v); sub(/:$/, "", v); printf "  [\"%s\"]=\"%s\"\n", $1, v }'
    fi
    echo ")"

    echo "declare -gA NPM_PINS=("
    if have npm; then
      npm ls -g --depth=0 --json 2>/dev/null > "$STATE_DIR/npm.json"
      python3 -I - "$STATE_DIR/npm.json" "${NPM_TOOLS[@]}" <<'PY'
import json, sys
deps = json.load(open(sys.argv[1])).get("dependencies", {})
for name in sys.argv[2:]:
    version = deps.get(name, {}).get("version")
    if version:
        print(f'  ["{name}"]="{version}"')
PY
    fi
    echo ")"

    echo "declare -gA PY_PINS=("
    if [[ -d $WHEELHOUSE ]]; then
      python3 -I - "$WHEELHOUSE" "${pyp[@]}" <<'PY'
import os, re, sys
wheelhouse, wanted = sys.argv[1], sys.argv[2:]
norm = lambda s: re.sub(r"[-_.]+", "-", s).lower()
vkey = lambda v: tuple(int(x) for x in re.findall(r"\d+", v))
found = {}
for f in os.listdir(wheelhouse):
    if f.endswith(".whl"):
        name, version = f.split("-")[:2]
        found.setdefault(norm(name), []).append(version)
for w in wanted:
    n = norm(re.split(r"[=<>!~\[ ]", w)[0])
    if n in found:
        print(f'  ["{n}"]="{max(found[n], key=vkey)}"')
PY
    fi
    echo ")"

    echo "declare -gA IMAGE_PINS=("
    if have podman; then
      local img digest
      for img in $OFFLINE_CONTAINER_IMAGES; do
        digest="$(podman image inspect --format '{{.Digest}}' "$img" 2>/dev/null)"
        if [[ -n $digest ]]; then printf '  ["%s"]="%s"\n' "$img" "$digest"; fi
      done
    fi
    echo ")"

    echo "declare -gA DOWNLOAD_SHA256=("
    if [[ -f $HASH_DB ]]; then
      awk '$3 != "published" { h[$1] = $2 } END { for (u in h) printf "  [\"%s\"]=\"%s\"\n", u, h[u] }' "$HASH_DB" | sort
    fi
    echo ")"
  ) > "$tmp"

  # Validate before replacing anything.
  # shellcheck disable=SC1090  # the generated file is checked on purpose
  if ! bash -n "$tmp" || ! ( set -u; source "$tmp" ) ; then
    rm -f "$tmp"; die "Generated lock file is invalid; nothing was changed."
  fi
  if [[ -f $LOCK_FILE ]]; then cp -a "$LOCK_FILE" "$LOCK_FILE.bak.$TIMESTAMP"; warn "Previous lock kept as $LOCK_FILE.bak.$TIMESTAMP"; fi
  mv "$tmp" "$LOCK_FILE"
  ok "Wrote $LOCK_FILE"
  if [[ -f $RUST_CACHE_DIR/Cargo.lock ]]; then
    cp "$RUST_CACHE_DIR/Cargo.lock" "$CARGO_LOCK_FILE"
    ok "Wrote $CARGO_LOCK_FILE (crate versions)"
  fi
  local n; n="$(grep -c '^  \["' "$LOCK_FILE" || true)"
  log "$n versions and checksums pinned. Commit both lock files to version control."
}

# ============================================================================
# SUMMARY
# ============================================================================
summary() {
  section "Summary"
  echo "Profile:      $PROFILE   (modules: core${MODULES[*]:+ }${MODULES[*]})"
  echo "Log file:     $LOG_FILE"
  echo "Undo script:  $UNDO_FILE   (review before running)"
  echo "Manifest:     ${MANIFEST_FILE:-not written}"
  echo "Self-test:    $T_PASS passed, $T_FAIL failed, $T_WARN warnings, $T_SKIP skipped   (re-run: ./setup.sh --self-test)"
  echo
  if (( ${#FAILED_STEPS[@]} )); then
    warn "Steps that did not fully complete:"
    printf '     - %s\n' "${FAILED_STEPS[@]}"
  else
    ok "All steps completed"
  fi
  if [[ -s "$MISSING_FILE" ]]; then
    warn "Packages/tools that were skipped or failed:"
    sort -u "$MISSING_FILE" | sed 's/^/     - /'
  fi

  local groups_note=""
  if [[ -s "$GROUPS_FILE" ]]; then groups_note=" (new groups: $(sort -u "$GROUPS_FILE" | paste -sd, -))"; fi
  cat <<EOF

$(if on "$UPGRADE"; then printf '%s\n' "${c_yellow}Upgrade run:${c_off} newest stable versions installed, pins ignored. Review the self-test,
then pin the new versions with ./setup.sh --lock and commit the lock files.
"; fi)
${c_blue}Next steps${c_off}
  1. Log out and back in${groups_note}.
  2. Open a terminal and run:  ws-help        (cheat sheet for everything set up here)
                               hx --tutor      (30 min, learn the editor)
  3. If not set yet:
       git config --global user.name  "Your Name"
       git config --global user.email "you@company.com"
       ssh-keygen -t ed25519
  4. In a project:  ws-init   then   pre-commit install
     (modules add starter files too, see:  ws-init --list)
  5. First machine of your team?  ./setup.sh --profile $PROFILE --lock   and commit
     locks/$PROFILE.lock plus locks/$PROFILE.Cargo.lock, so every other machine
     with this profile gets identical versions.

$(if ! grep -q 'bashrc.d' "$HOME/.bashrc" 2>/dev/null; then cat <<'SNIP'
Shell setup is installed but NOT active:
  ~/.bashrc does not load ~/.bashrc.d (ENABLE_SHELL_LOADER=0). To activate it, add
  this line to ~/.bashrc yourself (or re-run with ENABLE_SHELL_LOADER=1):
      for f in "$HOME"/.bashrc.d/*.sh; do [ -r "$f" ] && . "$f"; done; unset f
  Until then: ~/.cargo/bin is not on your PATH, and the aliases, the prompt and the
  offline lock for uv/pip/cargo are not active.
SNIP
fi)

$(show_opt_in)

${c_yellow}Still network-connected (OS level, outside this script's scope)${c_off}
  Discuss these with IT; they should point at internal infrastructure:
  - apt / unattended-upgrades       -> internal Ubuntu mirror
  - snapd (Firefox, Thunderbird, App Center) -> Snap Store proxy, or remove/hold snaps
  - chrony time sync (NTS, Ubuntu)  -> internal NTP server
  - Ubuntu Insights is opt-in: decline any consent prompt
EOF
}

# ============================================================================
# MAIN
# ============================================================================
# ============================================================================
# SYSTEM CHANGES THAT ARE OFF BY DEFAULT
# "SWITCH|what it would do". Modules add theirs with the 'opt_in' hook.
# ============================================================================
OPT_IN_CORE=(
  "TUNE_INOTIFY|raise the inotify limits (NEW file /etc/sysctl.d/60-dev-inotify.conf)"
  "DISABLE_REPORTING_SERVICES|disable crash/problem reporting services (apport, whoopsie, kerneloops)"
  "DISABLE_MOTD_NEWS|disable the MOTD news timer (motd-news.timer)"
  "DISABLE_FWUPD_REFRESH|disable the firmware metadata refresh timer (fwupd-refresh.timer)"
  "DISABLE_APT_NEWS|turn off APT news from Canonical ('pro config set apt_news=false')"
  "DISABLE_NM_CONNECTIVITY_CHECK|turn off NetworkManager's connectivity probe (NEW file in /etc/NetworkManager/conf.d)"
  "SET_GNOME_FONT|set the GNOME monospace font (JetBrainsMono Nerd Font Mono 11; JetBrains Mono 11 without the Nerd Font)"
  "SET_GNOME_PRIVACY|GNOME: no location, no automatic time zone, no problem reports, no usage stats, no web search"
  "JOIN_DOCKER_GROUP|add your user to group 'docker' (only with INSTALL_DOCKER=1; equivalent to root)"
  "ENABLE_SHELL_LOADER|append ONE marked block to ~/.bashrc that loads ~/.bashrc.d (aliases, PATH, prompt, offline lock)"
  "SET_GIT_DEFAULTS|set global git defaults (only options you have not set yourself)"
  "INSTALL_OH_MY_BASH|install Oh My Bash (pinned commit in ~/.local/share/oh-my-bash, loaded from ~/.bashrc.d; replaces the starship prompt)"
)

# Print every opt-in change with its state: what is ON is done, what is off is left as is.
show_opt_in() {
  local entry var text state
  local -a entries=("${OPT_IN_CORE[@]}")
  mapfile -t -O "${#entries[@]}" entries < <(module_collect opt_in)
  echo "System changes (off by default; one switch each, in workstation.conf, a profile or the environment):"
  for entry in "${entries[@]}"; do
    var="${entry%%|*}"; text="${entry#*|}"
    state="off"; if on "${!var:-0}"; then state="ON "; fi
    printf '  [%s] %-31s %s\n' "$state" "$var" "$text"
  done
}

# ============================================================================
# WHAT EACH STEP DOES (shown during install and by --explain)
#   STEP_WHY[title]      what the step does and why, in plain language
#   STEP_TOUCHES[title]  where it changes things: apt packages, files in ~,
#                        system files/services (sudo), network use at install
# Modules add their own entries in their module.sh.
# ============================================================================
STEP_WHY["System tuning"]="(Only with TUNE_INOTIFY=1.) Raises the inotify limits so language servers and file watchers can watch large source trees."
STEP_TOUCHES["System tuning"]="system: one NEW file /etc/sysctl.d/60-dev-inotify.conf (sudo)."

STEP_WHY["Privacy hardening"]="(Only with the DISABLE_* switches.) Stops Ubuntu's own background reporting, one switch each: crash reports, MOTD news, the firmware-refresh timer, APT news, the network connectivity probe. Services are disabled, never masked or removed. It runs after all installs, because installing packages can switch such timers back on."
STEP_TOUCHES["Privacy hardening"]="system, only for the switches that are on: disables services, a NEW file /etc/NetworkManager/conf.d/99-no-connectivity-check.conf, 'pro config set apt_news=false' (sudo)."

STEP_WHY["Base CLI tools"]="Everyday command-line tools (git, ripgrep, fzf, jq, tmux, ...) and the tldr example pages."
STEP_TOUCHES["Base CLI tools"]="apt packages; ~/.config/tealdeer/config.toml; network: tldr pages, once."

STEP_WHY["JetBrains Mono Nerd Font"]="JetBrains Mono with icon glyphs added (the 'Nerd Font' and 'Nerd Font Mono' families), installed for your user only, so prompts and themes can show icons. It is not in the Ubuntu archive: downloaded once from the project's GitHub release and checksum-verified. To use it, pick 'JetBrainsMono Nerd Font Mono' as the terminal font (SET_GNOME_FONT=1 does it for GNOME)."
STEP_TOUCHES["JetBrains Mono Nerd Font"]="~/.local/share/fonts/JetBrainsMonoNerdFont (32 font files) and the font cache; network: github.com release download, once (checked against the project's published SHA-256.txt)."

STEP_WHY["Oh My Bash"]="(Only with INSTALL_OH_MY_BASH=1.) The Oh My Bash framework (themes, aliases, plugins) from ONE pinned commit, loaded from ~/.bashrc.d/15-oh-my-bash.sh with its GitHub update check switched off. Its own installer is not used because it would replace your ~/.bashrc. While it is enabled it owns the prompt, so the starship prompt is not started."
STEP_TOUCHES["Oh My Bash"]="~/.local/share/oh-my-bash (git clone of one commit), ~/.bashrc.d/15-oh-my-bash.sh; network: github.com, at install time only."

STEP_WHY["Kate editor"]="Kate, the KDE text editor (a graphical editor next to Helix), as a Debian package from the Ubuntu archive (not a snap or Flatpak). It brings in KDE libraries. Its built-in language-server client is pointed at the same local servers Helix uses (clangd, rust-analyzer, basedpyright, ruff, taplo, cmake, bash); I found no telemetry or update-check dependency in Kate's build files."
STEP_TOUCHES["Kate editor"]="apt packages (kate and KDE libraries); ~/.config/kate/lspclient/settings.json."

STEP_WHY["Extra terminal tools"]="Nice-to-have terminal tools: zellij (a beginner-friendlier terminal multiplexer than tmux) and difftastic (structural diffs). Packages the archive of your Ubuntu release lacks are skipped and reported."
STEP_TOUCHES["Extra terminal tools"]="apt packages."

STEP_WHY["C/C++ toolchain"]="Compilers, build systems, debuggers, static analyzers and test frameworks for C and C++."
STEP_TOUCHES["C/C++ toolchain"]="apt packages; ~/.gdbinit."

STEP_WHY["GUI tools"]="Meld, a visual diff and merge tool."
STEP_TOUCHES["GUI tools"]="apt package."

STEP_WHY["Python tools"]="uv (package and tool manager) and the Python developer tools (ruff, basedpyright, pre-commit, ...), installed per user. uv is told never to download Python interpreters."
STEP_TOUCHES["Python tools"]="apt packages; ~/.local (uv and the tools); ~/.config/uv/uv.toml; network: uv's release tarball only if uv is not in the archive (checked against astral's published checksum), PyPI for the tools."

STEP_WHY["Rust toolchain"]="rustup with the newest stable Rust, the editor components, and cargo tools compiled from source (slow). rustup's self-update is switched off."
STEP_TOUCHES["Rust toolchain"]="apt build libraries; ~/.rustup and ~/.cargo; network: rustup-init only if not in the archive (checked against the Rust project's published checksum), Rust servers, crates.io."

STEP_WHY["Offline documentation"]="Reference documentation that works without internet: C/C++ (cppreference), Python, CMake, POSIX, glibc, GDB."
STEP_TOUCHES["Offline documentation"]="apt packages (docs, man pages)."

STEP_WHY["Bash language server"]="Editor support for shell scripts, installed with npm into your home directory. npm is told not to contact the registry for update notices, funding messages or audits."
STEP_TOUCHES["Bash language server"]="apt packages (nodejs, npm); ~/.local (npm global prefix); npm settings in ~/.npmrc; network: npm registry."

STEP_WHY["Helix editor"]="The Helix terminal editor, from the Ubuntu archive or the official release tarball (never a snap), with a configuration that disables the JSON/YAML language servers because they download schemas."
STEP_TOUCHES["Helix editor"]="apt package, or ~/.local/opt and ~/.local/bin/hx; ~/.config/helix/*; network: GitHub release only if Helix is not in the archive."

STEP_WHY["Containers"]="Podman and Distrobox for isolated build environments (Docker only if you switched it on). With podman, a small config file makes it never pull images by itself."
STEP_TOUCHES["Containers"]="apt packages; ~/.config/containers/containers.conf (with podman); with Docker and JOIN_DOCKER_GROUP=1 also adds you to the 'docker' group (sudo)."

STEP_WHY["Shell (bash) setup"]="Aliases, history, prompt and integrations (fzf, zoxide, direnv, starship) and the ws- helper commands (ws-init, ws-doctor), written to ~/.bashrc.d, plus the offline lock for uv, pip and cargo and the generated cheat sheet. They only take effect if ~/.bashrc loads ~/.bashrc.d: that single edit is ENABLE_SHELL_LOADER=1 (off by default; the summary prints the lines to add yourself)."
STEP_TOUCHES["Shell (bash) setup"]="files in ~/.bashrc.d, ~/.inputrc, ~/.local/bin, ~/.config/starship.toml, ~/WORKSTATION-CHEATSHEET.md; with ENABLE_SHELL_LOADER=1 one marked block in ~/.bashrc; network: starship's release tarball only if not in the archive (checked against its published checksum)."

STEP_WHY["Git setup"]="Switches lazygit's update check off. With SET_GIT_DEFAULTS=1 it also sets sensible global git defaults, only where you have not set a value yourself; GIT_NAME/GIT_EMAIL are applied if you give them."
STEP_TOUCHES["Git setup"]="~/.config/lazygit/config.yml; ~/.gitconfig only with SET_GIT_DEFAULTS=1 or GIT_NAME/GIT_EMAIL."

STEP_WHY["Project templates"]="Starter files for new projects (formatter, linter, pre-commit and CMake presets), copied into a project by ws-init without overwriting anything."
STEP_TOUCHES["Project templates"]="~/.local/share/workstation/templates."

STEP_WHY["Desktop settings"]="(Only with SET_GNOME_FONT=1 and/or SET_GNOME_PRIVACY=1.) A readable monospace font (JetBrainsMono Nerd Font Mono, which the terminal follows), and GNOME privacy settings: no location services, no automatic time zone, no problem reports or usage stats, no web search in the Activities overview. Needs a desktop session."
STEP_TOUCHES["Desktop settings"]="GNOME settings of your user (dconf)."

STEP_WHY["Offline cache: Python wheels"]="Downloads a local library of Python packages now, so uv and pip can install them later without network."
STEP_TOUCHES["Offline cache: Python wheels"]="~/.local/share/workstation/wheelhouse; network: PyPI, now."

STEP_WHY["Offline cache: Rust crates"]="Downloads common Rust crates now, so cargo can build later without network."
STEP_TOUCHES["Offline cache: Rust crates"]="~/.cargo/registry and ~/.local/share/workstation/rust-offline-cache; network: crates.io, now."

STEP_WHY["Offline cache: container images"]="Pulls the container images now and tells podman never to pull images by itself afterwards."
STEP_TOUCHES["Offline cache: container images"]="podman image storage in your home directory; ~/.config/containers/containers.conf; network: image registry, now."

# The ordered list of install steps. Used by the real run and by --explain.
run_steps() {
  if on "$TUNE_INOTIFY"; then step "System tuning"   system_tuning; fi
  step "Base CLI tools"                base_cli
  if on "$INSTALL_NERD_FONT";    then step "JetBrains Mono Nerd Font"  nerd_font; fi
  if on "$INSTALL_CPP";          then step "C/C++ toolchain"           cpp_toolchain; fi
  if on "$INSTALL_GUI_TOOLS";    then step "GUI tools"                 gui_tools; fi
  if on "$INSTALL_PYTHON";       then step "Python tools"              python_tools; fi
  if on "$INSTALL_RUST";         then step "Rust toolchain"            rust_toolchain; fi
  if on "$INSTALL_OFFLINE_DOCS"; then step "Offline documentation"     offline_docs; fi
  if on "$INSTALL_BASH_LSP";     then step "Bash language server"      bash_lsp; fi
  if on "$INSTALL_HELIX";        then step "Helix editor"              helix_setup; fi
  if on "$INSTALL_KATE";         then step "Kate editor"               kate_setup; fi
  if on "$INSTALL_NICE_TO_HAVE"; then step "Extra terminal tools"      nice_to_have; fi
  step "Containers"                    containers
  step "Shell (bash) setup"            shell_setup
  if on "$INSTALL_OH_MY_BASH";   then step "Oh My Bash"                oh_my_bash; fi
  step "Git setup"                     git_setup
  step "Project templates"             project_templates
  if any_on "$SET_GNOME_FONT" "$SET_GNOME_PRIVACY"; then step "Desktop settings" desktop_tweaks; fi
  module_collect steps
  # After every package install: installing packages can switch their timers on (a dependency
  # pulls in motd-news.timer, fwupd-refresh.timer, apport ...), so disabling them earlier did not stick.
  if any_on "$DISABLE_REPORTING_SERVICES" "$DISABLE_MOTD_NEWS" "$DISABLE_FWUPD_REFRESH" \
            "$DISABLE_APT_NEWS" "$DISABLE_NM_CONNECTIVITY_CHECK"; then
    step "Privacy hardening"           privacy_hardening
  fi
  if on "$CACHE_PYTHON";           then step "Offline cache: Python wheels"     cache_python; fi
  if on "$CACHE_RUST";             then step "Offline cache: Rust crates"       cache_rust; fi
  if on "$CACHE_CONTAINER_IMAGES"; then step "Offline cache: container images" cache_images; fi
}

# --explain: the whole run in plain language. Changes nothing, needs no network.
explain_mode() {
  EXPLAIN=1
  section "What this setup does: profile $PROFILE (modules: core${MODULES[*]:+ }${MODULES[*]})"
  if (( FULL )); then echo "FULL SETUP (--full): every opt-in system change is ON, unless you set it yourself."; fi
  cat <<EOT
Steps run in this order, as your normal user; sudo is used only where a step
says "system". Every step below is skipped or included according to your
switches. Nothing is installed or changed by --explain.
EOT
  run_steps
  section "In every profile, always"
  cat <<EOT
  Never:  remove a package, upgrade the system (no 'apt upgrade'), edit a file
          owned by a package, mask a service, add an APT repository or PPA,
          install a snap or Flatpak, or touch kernel, boot, coreutils or APT sources.
  Always: use apt with --no-remove --no-upgrade, keep an undo script
          (~/workstation-undo-<time>.sh), verify downloads outside APT by SHA-256,
          and, once the caches are filled, leave nothing that contacts the internet by itself.
  Next:   './setup.sh --check' shows the same plan down to package names and
          versions; './setup.sh' runs it; './setup.sh --self-test' verifies it.

EOT
  show_opt_in
}

# --undo: replay an undo file newest-first. The commands are the ones this setup
# recorded itself (see record_undo); all of them are shown before anything runs.
undo_mode() {
  local file="${UNDO_ARG:-}" line i n=0 failed=0 answer
  local -a cmds=() failures=()
  if [[ -z $file ]]; then
    file="$(find "$HOME" -maxdepth 1 -name 'workstation-undo-*.sh' -printf '%T@ %p\n' 2>/dev/null | sort -nr | head -n1 | cut -d' ' -f2- || true)"
  fi
  [[ -n $file && -f $file ]] || die "No undo file found (looked for ~/workstation-undo-*.sh). Give one: ./setup.sh --undo FILE"
  while IFS= read -r line; do
    case $line in ''|'#'*|'set -x') continue ;; esac
    cmds+=("$line")
  done < "$file"
  (( ${#cmds[@]} )) || { ok "$file records no changes: nothing to undo"; return 0; }

  section "Undo: $file"
  echo "These ${#cmds[@]} commands will run, newest first. Installed APT packages are NOT removed"
  echo "(see 'Undo' in the README for apt history)."
  echo
  for (( i = ${#cmds[@]} - 1; i >= 0; i-- )); do n=$((n + 1)); printf '  %2d. %s\n' "$n" "${cmds[i]}"; done
  echo
  if (( DRY_RUN )); then ok "Dry run: nothing was changed"; return 0; fi
  if (( ! ASSUME_YES )); then
    [[ -t 0 && -t 1 ]] || die "Not a terminal: add --yes to run without asking"
    read -rp "Run these commands? [y/N] " answer
    [[ $answer == [yY] ]] || { echo "Nothing was changed."; return 1; }
  fi
  if printf '%s\n' "${cmds[@]}" | grep -q 'sudo '; then sudo -v || die "sudo is needed for some of these commands"; fi
  n=0
  for (( i = ${#cmds[@]} - 1; i >= 0; i-- )); do
    n=$((n + 1))
    printf '%s[%d/%d]%s %s\n' "$c_blue" "$n" "${#cmds[@]}" "$c_off" "${cmds[i]}"
    # tools we installed live in ~/.local/bin and ~/.cargo/bin, which a plain shell may not have on PATH
    if ! PATH="$HOME/.local/bin:$HOME/.cargo/bin:$PATH" bash -c "${cmds[i]}"; then failed=$((failed + 1)); failures+=("${cmds[i]}"); warn "That command failed; continuing"; fi
  done
  if (( failed )); then
    warn "$failed command(s) failed; the undo file is kept: $file"
    printf '     - %s\n' "${failures[@]}"
    return 1
  fi
  mv "$file" "$file.done-$TIMESTAMP"
  ok "Undone. The undo file was renamed to $file.done-$TIMESTAMP"
}

# Remember the chosen profile so --check/--self-test/--lock default to it.
remember_profile() {
  local old=""
  if [[ -r $PROFILE_STATE ]]; then old="$(<"$PROFILE_STATE")"; fi
  if [[ $old == "$PROFILE" ]]; then return 0; fi
  if [[ -n $old ]]; then
    warn "This machine was set up with profile '$old'; adding profile '$PROFILE'. Nothing is removed."
    record_undo "printf '%s\\n' $(printf %q "$old") > $(printf %q "$PROFILE_STATE")"
  else
    record_undo "rm -f $(printf %q "$PROFILE_STATE") && rmdir --ignore-fail-on-non-empty $(printf %q "$(dirname "$PROFILE_STATE")")"
  fi
  mkdir -p "$(dirname "$PROFILE_STATE")"
  printf '%s\n' "$PROFILE" > "$PROFILE_STATE"
  ok "Remembered profile '$PROFILE' in $PROFILE_STATE"
}

main() {
  if (( LIST_PROFILES )); then list_profiles; return 0; fi
  if [[ $MODE == undo ]]; then undo_mode; return; fi
  load_config
  case "$MODE" in
    check)    check_mode; return 0 ;;
    explain)  explain_mode; return 0 ;;
    selftest) mkdir -p "$DATA_DIR"; self_test; return ;;
    manifest) write_manifest; return 0 ;;
    lock)     write_lock; return 0 ;;
  esac

  if (( FULL )) && [[ -t 0 && -t 1 ]]; then
    section "Full setup: these system changes will be made"
    show_opt_in
    local answer
    read -rp "Apply the full setup, including every change marked ON? [y/N] " answer
    [[ $answer == [yY] ]] || { echo "Nothing was changed."; exit 1; }
  fi

  [[ -d $DATA_DIR ]] || FIRST_RUN_DATA=1
  mkdir -p "$DATA_DIR"
  : > "$MISSING_FILE"; : > "$GROUPS_FILE"
  init_undo_file
  if (( FIRST_RUN_DATA )); then
    record_undo "rm -rf ~/.local/share/workstation   # templates, offline caches, self-test files"
  fi
  exec > >(tee -a "$LOG_FILE") 2>&1

  section "Workstation setup — profile $PROFILE — $(date)"
  preflight
  remember_profile

  run_steps

  self_test || true
  write_manifest
  summary
}

main
