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
#                                  file (newest ~/workstation-setup/workstation-undo-*.sh by default)
#                                  newest-first, after showing every command and asking.
#                                  Add --dry-run to only list, --yes to skip the question.
#                                  Never removes APT packages (see README, Undo).
#    ./setup.sh --reset-shell      For someone coming from zsh / Oh My Zsh: moves their zsh
#                                  files into a backup folder (nothing is deleted), makes bash
#                                  the login shell again and restores ~/.bashrc and ~/.profile
#                                  from /etc/skel if missing, so this setup (which is for bash)
#                                  works. Shows every command first and asks (--dry-run only
#                                  lists, --yes skips the question). Undo: ./setup.sh --undo.
#                                  The zsh package itself is never removed.
#    ./setup.sh --reset-defaults   COMPLETE reset to Ubuntu's own default, installing nothing: replays
#                                  the undo files of earlier runs; puts back Ubuntu's services, APT
#                                  news, GNOME settings, groups, git config; removes the setup's /etc
#                                  files; makes ~/.bashrc, ~/.profile, ~/.bash_logout Ubuntu's own
#                                  copies (/etc/skel) and bash the login shell; MOVES everything the
#                                  setup put in your home folder (~/.bashrc.d, tools, editor configs,
#                                  ~/.cargo, caches, the Nerd Font, ...) to a backup folder; removes
#                                  the Ubuntu packages apt's history shows the setup installed
#                                  (simulated first; refused if anything else would go). Shows every
#                                  change first and asks (--dry-run only lists, --yes skips the
#                                  question). Undo: ./setup.sh --undo (reinstalls the packages too).
#    ./setup.sh --list-profiles    Show the available profiles and modules.
#    ./setup.sh --help
#
#  Options combine, e.g.:  ./setup.sh --profile personal --check
#
#  STRUCTURE
#    core                 always installed: bash, Helix + language servers, git
#                         tooling, Python/C/C++/Rust, offline docs, offline caches
#    modules/<name>/      optional parts (embedded, desktop, ...)
#    profiles/<name>.conf chooses the modules of a machine
#
#  Settings and package lists live in workstation.conf, modules/*/module.conf
#  and the profile. Environment variables override switches for one run,
#  e.g.:  INSTALL_DOCKER=1 ./setup.sh
#  Run as your normal user, NOT with sudo.
#  The run is polite to your computer (LOW_PRIORITY=1, the default): low CPU and disk
#  priority, parallel builds capped by your cores AND free RAM. LOW_PRIORITY=0 turns it off.
#
#  NO-CLOUD POLICY (fixed, every profile)
#    Downloading during installation is allowed. Afterwards, no tool this
#    setup installs contacts external services: no cloud-connected tools, their
#    update checks and telemetry are disabled, and podman never pulls on its own.
#    Ubuntu's OWN services and telemetry (crash reports, MOTD news, firmware
#    refresh, GNOME's privacy settings) are left as Ubuntu ships them.
#    You are never blocked from the network: uv, pip, cargo and podman fetch
#    what YOU ask them to (a strict lock that limits them to the local caches
#    is opt-in, ENFORCE_OFFLINE_ENV=1). Networked apps (browser, mail) only
#    do what you direct them to do.
#
#  SAFETY POLICY (fixed, every profile)
#    Never removes packages (apt --no-remove), never upgrades installed ones
#    (no 'apt upgrade'; apt --no-upgrade), never edits package-owned
#    config files, never touches kernel, boot, coreutils or APT sources.
#    Every change is recorded in ~/workstation-setup/workstation-undo-<timestamp>.sh
#    (that folder also holds the manifest, the log and the cheat sheet; WS_OUT_DIR changes it).
#
#  VERSIONS
#    Ubuntu 24.04 LTS or 26.04 LTS (SUPPORTED_UBUNTU in workstation.conf): both are
#    verified, nobody has to upgrade to the newest. For software with an LTS line,
#    the newest LTS; otherwise the newest stable release, never betas, release
#    candidates or nightlies.
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
    --reset-shell) MODE=reset-shell ;;
    --reset-defaults) MODE=reset-defaults ;;
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
# The records of a run (undo script, manifest, log) and the generated cheat sheet live in ONE folder, not loose in
# your home directory. WS_OUT_DIR (environment) picks another folder.
OUT_DIR="${WS_OUT_DIR:-$HOME/workstation-setup}"
CHEATSHEET_FILE="$OUT_DIR/WORKSTATION-CHEATSHEET.md"
LOG_FILE="$OUT_DIR/workstation-setup-$TIMESTAMP.log"
UNDO_FILE="$OUT_DIR/workstation-undo-$TIMESTAMP.sh"
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
  mkdir -p "$OUT_DIR"
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
# Keep the machine usable while the setup runs (LOW_PRIORITY, default on). Found on a real laptop that became slow and
# laggy during a run: the script never lowered its own priority and cargo compiles on every core, several rustc at about
# 1 GB each, which can push a laptop into swapping. This process (and so apt, cargo, cmake and everything else it starts,
# also through sudo) gets nice 10 and best-effort I/O class 7, and parallel builds are capped by cores AND free RAM.
# Settings you made yourself (CARGO_BUILD_JOBS, CMAKE_BUILD_PARALLEL_LEVEL) win. Nothing is persisted: only this run.
# (On desktops the kernel also groups processes per terminal, "autogroup", so priority matters less than memory.)
gentle_jobs() {   # how many parallel build jobs are reasonable: half the cores, at most one per ~1.5 GB of free RAM
  local cpus mem_kb jobs by_mem
  cpus="$(nproc 2>/dev/null || echo 2)"
  jobs=$(( (cpus + 1) / 2 ))
  mem_kb="$(awk '/^MemAvailable:/ { print $2; exit }' "${MEMINFO:-/proc/meminfo}" 2>/dev/null || true)"
  if [[ $mem_kb =~ ^[0-9]+$ ]]; then
    by_mem=$(( mem_kb / 1500000 ))
    if (( by_mem < jobs )); then jobs=$by_mem; fi
  fi
  if (( jobs < 1 )); then jobs=1; fi
  echo "$jobs"
}
be_gentle() {
  on "$LOW_PRIORITY" || return 0
  local cur jobs
  cur="$(ps -o ni= -p $$ 2>/dev/null | tr -d ' ' || true)"
  # never LOWER a niceness you already chose (renice -n sets an absolute value)
  if [[ $cur =~ ^-?[0-9]+$ ]] && (( cur < 10 )); then renice -n 10 -p $$ >/dev/null 2>&1 || true; fi
  if have ionice; then ionice -c2 -n7 -p $$ >/dev/null 2>&1 || true; fi
  jobs="$(gentle_jobs)"
  export CARGO_BUILD_JOBS="${CARGO_BUILD_JOBS:-$jobs}"
  export CMAKE_BUILD_PARALLEL_LEVEL="${CMAKE_BUILD_PARALLEL_LEVEL:-$jobs}"
  log "Low priority (nice 10, best-effort I/O 7); at most $CARGO_BUILD_JOBS parallel build jobs. LOW_PRIORITY=0 switches this off."
}

# Network resilience, for everything this script downloads (command-line options only: no APT source and no package-owned
# configuration is touched). Found by an E2E job that sat for hours on a slow Ubuntu mirror: apt retries nothing by
# default (Acquire::Retries is 0) and curl only retried on errors, never on a download that just trickled along.
#   APT_NET   apt retries a failed fetch 3 times and gives up on a connection that is silent for 60 s.
#   CURL_DL   curl retries (transient errors, timeouts) for up to 180 s in total, and counts a transfer that stays below
#             4 KB/s for 60 s as stalled ("operation too slow", a retried error) instead of waiting for it forever.
# apt has no minimum-speed setting: a mirror that is slow but alive is still waited for (the CI job timeout is the backstop).
APT_NET=(-o Acquire::Retries=3 -o Acquire::http::Timeout=60 -o Acquire::https::Timeout=60)
CURL_DL=(--retry 6 --retry-max-time 180 --connect-timeout 20 --speed-limit 4096 --speed-time 60)

# apt-get as root, waiting for a busy lock. Ubuntu's own updater (packagekitd, behind Software Updater and GNOME Software)
# holds the apt lock for a while after login and after package installs, and apt then fails at once ("Could not get lock
# /var/lib/apt/lists/lock. It is held by process N (packagekitd)"). apt's own -o DPkg::Lock::Timeout does NOT cover the lists
# lock of 'apt-get update' (tested: apt 2.8.3 fails at once with it set), so a lock error is retried here, every 5 s, for up to
# APT_LOCK_WAIT seconds (0 = do not wait), saying who holds it. Any other failure returns at once; the lock files are never touched.
apt_run() {   # apt_run ARGS...   (e.g. apt_run install -y --no-remove --no-upgrade pkg)
  local errf rc waited=0 holder wait_for="${APT_LOCK_WAIT:-300}"
  errf="$(mktemp)"
  while :; do
    rc=0
    sudo env DEBIAN_FRONTEND=noninteractive apt-get "${APT_NET[@]}" "$@" 2>"$errf" || rc=$?
    if (( rc == 0 )) || ! grep -qE 'Could not get lock|Unable to acquire the dpkg frontend lock|Unable to lock (the )?(administration )?directory' "$errf" \
       || (( waited >= wait_for )); then
      cat "$errf" >&2; rm -f "$errf"; return "$rc"
    fi
    holder="$(sed -n 's/.*held by process \([0-9][0-9]*\) (\([^)]*\)).*/\2 (PID \1)/p' "$errf" | head -n1)"
    if (( waited % 30 == 0 )); then
      warn "The package system is busy${holder:+: $holder}. This is normal right after login or after installs (Ubuntu's own updater). Waiting up to ${wait_for} s, then giving up..."
    fi
    sleep 5; waited=$(( waited + 5 ))
  done
}

# --no-remove: abort rather than uninstall anything to resolve a conflict.
# --no-upgrade: do not upgrade packages that are already installed; this
# script never upgrades the system (updates are Ubuntu's own business).
apt_install() {
  local available=() pkg ver
  local -A cand=()
  local -a want=()
  for pkg in "$@"; do
    if pkg_applies "$pkg"; then want+=("$pkg")
    else log "Not needed on Ubuntu $(os_version_id): $pkg (${PKG_SINCE_NOTE[$pkg]:-it exists only on newer releases})"; fi
  done
  set -- "${want[@]}"
  (( $# )) || return 0
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
  if ! apt_run install -y --no-remove --no-upgrade "${available[@]}"; then
    warn "Batch install failed; retrying one package at a time"
    for pkg in "${available[@]}"; do
      apt_run install -y --no-remove --no-upgrade "$pkg" \
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
  # --undo returns to UBUNTU'S OWN DEFAULT (gsettings reset), not to the value found before (DECIDED by the user)
  record_undo "gsettings reset $schema $key"
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
  if ! curl -fsSL "${CURL_DL[@]}" "$url" -o "$tmp"; then
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
  if ! curl -fsSL "${CURL_DL[@]}" "$url" -o "$tmp"; then
    rm -f "$tmp"; warn "Download failed: $url"; return 1
  fi
  # The project publishes this checksum, so it MUST be reachable. A network hiccup is retried; if it still fails
  # we do NOT fall back to trusting the download (anyone able to block the checksum file could then get a
  # tampered file accepted). Only a SHA-256 pinned in the lock file can stand in for it.
  local try=1 tries="${FETCH_SUMS_TRIES:-4}" delay="${FETCH_SUMS_DELAY:-3}"
  sums=""
  while ! sums="$(curl -fsSL "${CURL_DL[@]}" "$sumurl" 2>/dev/null)" && (( try < tries )); do
    sleep $(( try * delay )); try=$(( try + 1 ))
  done
  if [[ -z $sums ]]; then
    rm -f "$tmp"
    if [[ -n ${DOWNLOAD_SHA256[$url]:-} ]]; then
      warn "The published checksum at $sumurl is not reachable; verifying against the SHA-256 pinned in the lock file"
      fetch_verified "$url" "$dest"; return
    fi
    warn "REFUSED: $url. The project publishes a checksum ($sumurl) but it could not be fetched, so this download cannot be verified. Try again later."
    return 1
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
rustup_init_url() {   # the newest release, or RUSTUP_VERSION (the lock) from the project's archive of releases
  if [[ -n ${RUSTUP_VERSION:-} ]]; then echo "https://static.rust-lang.org/rustup/archive/$RUSTUP_VERSION/$(host_arch)-unknown-linux-gnu/rustup-init"
  else echo "https://static.rust-lang.org/rustup/dist/$(host_arch)-unknown-linux-gnu/rustup-init"; fi
}
lazygit_base_url() {
  if [[ -n ${LAZYGIT_VERSION:-} ]]; then echo "https://github.com/jesseduffield/lazygit/releases/download/$LAZYGIT_VERSION"
  else echo "https://github.com/jesseduffield/lazygit/releases/latest/download"; fi
}
starship_asset() { echo "starship-$(host_arch)-unknown-linux-gnu.tar.gz"; }
starship_base_url() {
  if [[ -n ${STARSHIP_VERSION:-} ]]; then echo "https://github.com/starship/starship/releases/download/$STARSHIP_VERSION"
  else echo "https://github.com/starship/starship/releases/latest/download"; fi
}
helix_url() {  # $1 = version
  echo "https://github.com/helix-editor/helix/releases/download/$1/helix-$1-$(host_arch)-linux.tar.xz"
}
# Pinned version, or the newest stable release (GitHub's "latest" excludes
# pre-releases and drafts). Network access here happens at install time only.
helix_version() {
  if [[ -n ${HELIX_VERSION:-} ]]; then echo "$HELIX_VERSION"; return 0; fi
  local v
  # The redirect of /releases/latest names the newest stable tag (no API call, no rate limit); the API is the fallback.
  v="$(curl -s -o /dev/null -D - --max-time 30 https://github.com/helix-editor/helix/releases/latest 2>/dev/null \
    | awk 'tolower($1) == "location:" { n = split($2, a, "/"); gsub(/\r/, "", a[n]); print a[n]; exit }' || true)"
  if [[ -z $v ]]; then
    v="$(curl -fsSL --max-time 30 https://api.github.com/repos/helix-editor/helix/releases/latest 2>/dev/null \
      | python3 -I -c 'import json, sys; print(json.load(sys.stdin)["tag_name"])' 2>/dev/null || true)"
  fi
  [[ -n $v ]] && echo "$v"
}

# Neovim: the release tarball (nvim-linux-x86_64.tar.gz / nvim-linux-arm64.tar.gz) of the newest stable release.
# The tag comes from the redirect of the latest/download URL (no API call). NVIM_VERSION (the lock) pins one, with the "v".
nvim_asset() {
  case "$(host_arch)" in x86_64) echo nvim-linux-x86_64 ;; aarch64) echo nvim-linux-arm64 ;; *) return 1 ;; esac
}
nvim_url() { echo "https://github.com/neovim/neovim/releases/download/$1/$(nvim_asset).tar.gz"; }   # $1 = tag, e.g. v0.12.6
nvim_version() {
  if [[ -n ${NVIM_VERSION:-} ]]; then echo "$NVIM_VERSION"; return 0; fi
  local a; a="$(nvim_asset)" || return 1
  release_tag_of "https://github.com/neovim/neovim/releases/latest/download/$a.tar.gz"
}

# True if the binary $1 (a path) exists and reports version $2 as its second word ("uv 0.8.3", "helix 25.07.1 (...)").
binary_is_version() {
  [[ -x $1 ]] || return 1
  [[ "$("$1" --version 2>/dev/null | awk 'NR == 1 { print $2 }' || true)" == "$2" ]]
}

# The rule for tools without an LTS line (uv, Helix, starship; decided by the user: the newest UPSTREAM release
# wins over the Ubuntu archive's older package, like Node.js). Usage: <label> <apt package> <install function>
# <value of the *_FROM_ARCHIVE switch> <command names>.
#   - not installed: the project's release (checksum-verified, in ~/.local); if that download fails, or
#     *_FROM_ARCHIVE=1, or ALLOW_CURL_INSTALLERS=0, the archive's package. A fallback after a FAILED download is
#     written to MISSING_FILE so the summary and the E2E flag it.
#   - already installed (by you, or an earlier run): left alone. Only --upgrade moves to the newest release; it
#     installs it in ~/.local/bin, in front of any package from Ubuntu (which is never removed).
# The install function must return non-zero on any failure and must not rely on 'set -e' (it runs in an 'if').
install_upstream_first() {
  local label="$1" pkg="$2" fn="$3" from_archive="$4" cmds="$5" c installed=0 note=0
  for c in $cmds; do if have "$c"; then installed=1; fi; done
  if (( installed )); then
    if on "$UPGRADE" && ! on "$from_archive" && on "$ALLOW_CURL_INSTALLERS"; then
      "$fn" || warn "Could not move $label to the newest release; keeping the installed one"
    fi
    return 0
  fi
  if ! on "$from_archive" && on "$ALLOW_CURL_INSTALLERS"; then
    if "$fn"; then return 0; fi
    warn "Could not install $label from its release; using the Ubuntu archive's package instead (older, but supported by Ubuntu)"
    note=1
  fi
  if apt_has "$pkg"; then
    apt_install "$pkg"
    for c in $cmds; do
      if (( note )) && have "$c"; then echo "$label newest release (used the archive's)" >> "$MISSING_FILE"; break; fi
    done
  elif on "$from_archive" && on "$ALLOW_CURL_INSTALLERS"; then
    "$fn" || true
  fi
  for c in $cmds; do if have "$c"; then return 0; fi; done
  warn "$label could not be installed"
  return 1
}

# Node.js: the newest LTS release from nodejs.org (decided by the user: the newest upstream LTS wins over the
# archive's older Node.js). No APT repository (NodeSource) is added: the project's own tarball is unpacked
# in your home directory and checked against the SHASUMS256.txt the project publishes.
node_arch() {
  case "$(host_arch)" in x86_64) echo x64 ;; aarch64) echo arm64 ;; *) return 1 ;; esac
}
# Pinned version (NODE_LTS_VERSION, e.g. v26.13.0), else the newest release the project's index marks "lts".
node_version() {
  if [[ -n ${NODE_LTS_VERSION:-} ]]; then echo "$NODE_LTS_VERSION"; return 0; fi
  curl -fsSL "${CURL_DL[@]}" https://nodejs.org/dist/index.json 2>/dev/null \
    | python3 -I -c 'import json, sys
for r in json.load(sys.stdin):
    if r.get("lts"):
        print(r["version"]); break'
}
NODE_TOOLS=(node npm npx corepack)
node_install() {
  local v arch dir base asset tool target opt="$HOME/.local/opt" bin="$HOME/.local/bin"
  arch="$(node_arch)" || { warn "No Node.js release for $(host_arch)"; return 1; }
  v="$(node_version || true)"
  if [[ ! $v =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then warn "Could not determine the newest Node.js LTS release"; return 1; fi
  dir="$opt/node-$v"
  if [[ -x $dir/bin/node && "$(readlink -f "$bin/node" 2>/dev/null || true)" == "$dir/bin/node" ]]; then
    ok "Node.js $v (already installed)"; return 0
  fi
  for tool in "${NODE_TOOLS[@]}"; do   # never replace something that is not ours
    if [[ -e $bin/$tool || -L $bin/$tool ]]; then
      target="$(readlink "$bin/$tool" 2>/dev/null || true)"
      case $target in */opt/node-v*) ;; *) warn "$bin/$tool exists and is not from this setup; leaving it alone"; return 1 ;; esac
    fi
  done
  base="https://nodejs.org/dist/$v"; asset="node-$v-linux-$arch.tar.xz"
  fetch_published "$base/$asset" "$STATE_DIR/$asset" "$base/SHASUMS256.txt" "$asset" || return 1
  mkdir -p "$opt" "$bin"
  rm -rf "$dir.partial"; mkdir "$dir.partial"
  tar -xJf "$STATE_DIR/$asset" -C "$dir.partial" --strip-components=1
  if [[ ! -e $dir ]]; then record_undo "rm -rf ~/.local/opt/node-$v"; fi
  rm -rf "$dir"; mv "$dir.partial" "$dir"
  for tool in "${NODE_TOOLS[@]}"; do    # corepack is not shipped by every release: link what exists
    if [[ ! -e $dir/bin/$tool ]]; then continue; fi
    if [[ ! -e $bin/$tool && ! -L $bin/$tool ]]; then record_undo "rm -f ~/.local/bin/$tool"; fi
    ln -sfn "../opt/node-$v/bin/$tool" "$bin/$tool"
  done
  for target in "$opt"/node-v*; do      # older releases from an earlier run of this setup
    if [[ -d $target && $target != "$dir" ]]; then rm -rf "$target"; fi
  done
  hash -r
  ok "Node.js $v (newest LTS) installed in ~/.local/opt, linked from ~/.local/bin"
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
  if on "$INSTALL_BASH_LSP" && on "$NODE_FROM_ARCHIVE"; then echo PKGS_NODE; fi
  if on "$INSTALL_PODMAN"; then echo PKGS_PODMAN; fi
  if on "$INSTALL_DOCKER"; then echo PKGS_DOCKER; fi
  module_collect pkg_groups
  echo PKGS_EXTRA
}

# Files from files/home (core) and the modules' files/home that the enabled
# features install. The cheat sheet is generated, see install_cheatsheet.
home_files() {
  echo .bashrc.d/10-workstation.sh
  echo .bashrc.d/16-aliases.sh
  echo .inputrc
  echo .local/bin/ws-init
  echo .local/bin/ws-doctor
  echo .config/lazygit/config.yml
  echo .config/tealdeer/config.toml
  if on "$INSTALL_OH_MY_BASH"; then echo .bashrc.d/15-oh-my-bash.sh; fi
  if on "$INSTALL_KATE"; then echo .config/kate/lspclient/settings.json; echo .config/kate/formatting/settings.json; echo .local/bin/ws-pyformat; fi
  if on "$ENFORCE_OFFLINE_ENV"; then echo .bashrc.d/20-offline.sh; fi
  if on "$INSTALL_CPP"; then echo .gdbinit; fi
  if on "$INSTALL_PYTHON"; then echo .config/uv/uv.toml; fi
  if on "$INSTALL_HELIX"; then echo .config/helix/config.toml; echo .config/helix/languages.toml; fi
  if on "$INSTALL_NVIM"; then echo .config/nvim/init.lua; fi
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
  mkdir -p "$OUT_DIR"
  cheatsheet_content | write_config "$CHEATSHEET_FILE"
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

# Checks that this is Ubuntu, an LTS release, and one of the releases this setup is verified on
# (SUPPORTED_UBUNTU in workstation.conf). An older supported release is NOT a problem: nobody has to
# upgrade to the newest. Sets OS_PROBLEM to a description of the first problem found, or "";
# OS_INFO to a friendly note; OS_VERIFIED=1 for a supported release. No network access.
os_check() {
  OS_PROBLEM=""
  OS_INFO=""
  OS_VERIFIED=0
  # shellcheck disable=SC1090,SC1091
  . "${OS_RELEASE_FILE:-/etc/os-release}"
  local ver="${VERSION_ID:-?}" oldest newest
  local -a rel=()
  read -ra rel <<<"${SUPPORTED_UBUNTU:-}"
  oldest="$(printf '%s\n' "${rel[@]}" | sort -V | head -n1)"
  newest="$(printf '%s\n' "${rel[@]}" | sort -V | tail -n1)"
  if [[ ${ID:-} != ubuntu ]]; then
    OS_PROBLEM="This setup is for Ubuntu; detected ${PRETTY_NAME:-an unknown system}."
  elif [[ ${VERSION:-} != *LTS* ]]; then
    OS_PROBLEM="Ubuntu $ver is not a long-term support (LTS) release. Use an LTS release (verified: ${rel[*]})."
  elif [[ " ${rel[*]} " == *" $ver "* ]]; then
    OS_VERIFIED=1
    if [[ $ver != "$newest" ]]; then
      OS_INFO="Ubuntu $ver LTS is supported. The newest verified LTS is $newest; upgrading is optional, nothing here requires it."
    fi
  elif version_lt "$ver" "$oldest"; then
    OS_PROBLEM="Ubuntu $ver LTS is older than the oldest release this setup supports ($oldest): its tools are too old
   (for example Python 3.11+ is needed). Verified releases: ${rel[*]}."
  else
    OS_PROBLEM="Ubuntu $ver LTS is newer than any release this setup has been verified on (${rel[*]}).
   Run ./setup.sh --check first: package names may differ."
  fi
}

# version_lt A B: A is an older version than B (24.04 < 26.04).
version_lt() { [[ $1 != "$2" && "$(printf '%s\n%s\n' "$1" "$2" | sort -V | head -n1)" == "$1" ]]; }

# The Ubuntu release number of this machine (24.04, 26.04, ...).
# shellcheck disable=SC1090,SC1091
os_version_id() { ( . "${OS_RELEASE_FILE:-/etc/os-release}"; echo "${VERSION_ID:-}" ); }

# pkg_applies PACKAGE: false if the package exists only from a newer release than this one (PKG_SINCE).
pkg_applies() {
  local since="${PKG_SINCE[$1]:-}"
  [[ -z $since ]] && return 0
  ! version_lt "$(os_version_id)" "$since"
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
  elif [[ -n $OS_INFO ]]; then
    log "$OS_INFO"
  fi
  [[ "$(uname -m)" == x86_64 ]] || warn "Not x86_64: some packages may be unavailable."
  have sudo || die "sudo is not available."

  log "Requesting sudo (kept alive for the duration of the script)"
  sudo -v
  ( while true; do sudo -n true; sleep 50; kill -0 "$$" 2>/dev/null || exit; done ) 2>/dev/null &
  SUDO_KEEPALIVE_PID=$!
  trap 'kill "$SUDO_KEEPALIVE_PID" 2>/dev/null || true; rm -rf "$STATE_DIR"' EXIT

  log "Updating package lists"
  apt_run update || die "apt-get update failed (see the message above). A busy apt lock is waited for (APT_LOCK_WAIT=${APT_LOCK_WAIT:-300} s); otherwise check your network / proxy settings."
  apt_run install -y --no-remove --no-upgrade curl ca-certificates gnupg distro-info
}

INOTIFY_CONF_TEXT=$'fs.inotify.max_user_watches = 524288\nfs.inotify.max_user_instances = 1024\n'
system_tuning() {
  # Large source trees (clangd, rust-analyzer, file watchers) need more inotify
  # watches. A new drop-in file; nothing existing is modified.
  local f=/etc/sysctl.d/60-dev-inotify.conf
  if [[ ! -e $f ]]; then
    printf '%s' "$INOTIFY_CONF_TEXT" | sudo tee "$f" >/dev/null
    record_undo "sudo rm -f $f"       # recorded as soon as the file exists, whatever sysctl does next
    if sudo sysctl -p "$f" >/dev/null 2>&1; then ok "Raised inotify limits"
    else warn "Wrote $f but could not apply it now (a container?); it takes effect at the next boot"; fi
  else
    ok "Unchanged: $f"
  fi
}

# lazygit from its release tarball, checked against the checksums.txt the project publishes. The version
# is read from that file (the asset name carries it), so no API call is needed. The newest stable release,
# or LAZYGIT_VERSION (the lock). Not in the 24.04 archive at all; the 26.04 archive has an older one.
lazygit_installed_version() { "$1" --version 2>/dev/null | sed -n 's/.*version=\([^,]*\),.*/\1/p' | head -n1 || true; }
lazygit_install_upstream() {
  local base arch=x86_64 asset ver bin="$HOME/.local/bin" fresh=0; base="$(lazygit_base_url)"
  if [[ $(host_arch) == aarch64 ]]; then arch=arm64; fi
  # Not fatal: a failed curl in this pipeline (pipefail) used to abort the whole calling step.
  asset="$(curl -fsSL "${CURL_DL[@]}" "$base/checksums.txt" 2>/dev/null \
           | awk -v a="_linux_$arch.tar.gz" 'index($2, a) { print $2; exit }' || true)"
  if [[ -z $asset ]]; then warn "Could not find a lazygit release for this CPU (or the download failed)"; return 1; fi
  ver="${asset#lazygit_}"; ver="${ver%%_*}"
  if [[ -x $bin/lazygit && "$(lazygit_installed_version "$bin/lazygit")" == "$ver" ]]; then ok "lazygit $ver is the newest stable release"; return 0; fi
  fetch_published "$base/$asset" "$STATE_DIR/$asset" "$base/checksums.txt" "$asset" || return 1
  mkdir -p "$bin" || return 1
  if [[ ! -e $bin/lazygit && ! -L $bin/lazygit ]]; then fresh=1; fi
  if (( fresh )); then record_undo "rm -f ~/.local/bin/lazygit"; fi
  tar -xzf "$STATE_DIR/$asset" -C "$bin" lazygit || return 1
  hash -r
  ok "lazygit $ver installed in ~/.local/bin (the newest upstream release)"
}

base_cli() {
  apt_install "${PKGS_BASE[@]}"
  # The settings that switch things OFF come before anything that needs the network, so a failed download
  # can never leave the privacy configuration unwritten.
  if have tldr; then install_file .config/tealdeer/config.toml; fi
  # lazygit: the newest upstream release wins over the archive's older one (26.04) or none (24.04). A failed
  # download is reported, never fatal.
  if ! install_upstream_first lazygit lazygit lazygit_install_upstream "$LAZYGIT_FROM_ARCHIVE" lazygit; then
    warn "lazygit was not installed; re-run ./setup.sh later"
    echo "lazygit (not installed)" >> "$MISSING_FILE"
  fi
  if have tldr; then
    # Fetch the example pages ONCE now; auto-update stays off afterwards.
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

# uv from astral's release tarball (not their installer script: it would also edit your shell startup files),
# checked against the checksum astral publishes next to it. The newest stable release, or UV_VERSION (the lock).
uv_install_upstream() {
  local asset base dir tag fresh=0; asset="$(uv_asset)"; base="$(uv_base_url)"; dir="${asset%.tar.gz}"
  tag="${UV_VERSION:-$(release_tag_of "$base/$asset" || true)}"
  if [[ -n $tag ]] && binary_is_version "$HOME/.local/bin/uv" "$tag"; then ok "uv $tag is the newest stable release"; return 0; fi
  fetch_published "$base/$asset" "$STATE_DIR/$asset" "$base/$asset.sha256" "$asset" || return 1
  tar -xzf "$STATE_DIR/$asset" -C "$STATE_DIR" || return 1
  [[ -x $STATE_DIR/$dir/uv && -x $STATE_DIR/$dir/uvx ]] || { warn "The uv archive does not contain uv and uvx"; return 1; }
  mkdir -p "$HOME/.local/bin" || return 1
  if [[ ! -e $HOME/.local/bin/uv && ! -L $HOME/.local/bin/uv ]]; then fresh=1; fi
  if (( fresh )); then record_undo "rm -f ~/.local/bin/uv ~/.local/bin/uvx"; fi
  install -m 755 "$STATE_DIR/$dir/uv" "$STATE_DIR/$dir/uvx" "$HOME/.local/bin/" || return 1
  hash -r
  ok "uv $("$HOME/.local/bin/uv" --version | awk '{ print $2 }') installed in ~/.local/bin (the newest upstream release)"
}

ensure_uv() {
  install_upstream_first uv uv uv_install_upstream "$UV_FROM_ARCHIVE" uv || return 1
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

# rustup-init itself, checked against the .sha256 the Rust project publishes (instead of the sh.rustup.rs script
# that downloads it). --default-toolchain none installs only rustup; --no-modify-path leaves your shell files alone.
# On a machine that has rustup in ~/.cargo already (--upgrade) the same command updates it in place and leaves the
# toolchains alone. (Ubuntu's rustup package, if installed, is never touched: its binary stays in /usr/bin.)
rustup_install_upstream() {
  local init="$STATE_DIR/rustup-init" bin="$HOME/.cargo/bin/rustup" ver fresh=0
  fetch_published "$(rustup_init_url)" "$init" "$(rustup_init_url).sha256" "rustup-init" || return 1
  chmod +x "$init" || return 1
  ver="$("$init" --version 2>/dev/null | awk 'NR == 1 { print $2 }' || true)"
  if [[ -n $ver ]] && binary_is_version "$bin" "$ver"; then ok "rustup $ver is the newest stable release"; return 0; fi
  if [[ ! -e $bin ]]; then fresh=1; fi
  if (( fresh )); then record_undo "rustup self uninstall -y"; fi
  "$init" -y --no-modify-path --default-toolchain none || return 1
  hash -r
  ok "rustup $("$bin" --version 2>/dev/null | awk 'NR == 1 { print $2 }') installed in ~/.cargo/bin (the newest upstream release)"
}

rust_toolchain() {
  install_upstream_first rustup rustup rustup_install_upstream "$RUSTUP_FROM_ARCHIVE" rustup || return 1
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
    cargo_tools_install
  fi
}

# Compile and install the cargo tools that are MISSING. A tool you already have is left alone (like every other tool
# here; only --upgrade moves it to the newest release), so a re-run no longer recompiles it just because a newer release
# came out meanwhile (a 10+ minute build per tool). A pin from the lock that differs from the installed version is
# installed, because the lock is what you asked for.
cargo_tools_install() {
  local specs=() c pin have_ver cargo_tools installed_before skipped=()
  mapfile -t cargo_tools < <(cargo_tool_list)
  installed_before="$(cargo install --list 2>/dev/null || true)"
  for c in "${cargo_tools[@]}"; do
    pin="${CARGO_PINS[$c]:-}"
    have_ver="$(awk -v n="$c" '$1 == n { v = $2; sub(/^v/, "", v); sub(/:$/, "", v); print v; exit }' <<<"$installed_before")"
    if [[ -z $have_ver ]]; then
      record_undo "cargo uninstall $c"
    elif ! on "$UPGRADE" && [[ -z $pin || $pin == "$have_ver" ]]; then
      skipped+=("$c $have_ver"); continue
    fi
    if [[ -n $pin ]]; then specs+=("$c@$pin"); else specs+=("$c"); fi
  done
  if (( ${#skipped[@]} )); then
    ok "Cargo tools already installed, left alone (--upgrade moves them to the newest release): $(printf '%s; ' "${skipped[@]}" | sed 's/; $//')"
  fi
  if (( ${#specs[@]} )); then
    log "Compiling cargo tools: ${specs[*]} (this can take 10+ minutes)"
    cargo install --locked "${specs[@]}"
  fi
}

bash_lsp() {
  if on "$NODE_FROM_ARCHIVE"; then
    apt_install "${PKGS_NODE[@]}"
  elif ! node_install; then
    warn "Using the Ubuntu archive's Node.js instead (older, but supported by Ubuntu)"
    echo "Node.js newest LTS from nodejs.org (used the archive's)" >> "$MISSING_FILE"
    apt_install "${PKGS_NODE[@]}"
  fi
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

# Set keys in ONE group of a KConfig (.ini style) file and touch nothing else.
#   kconfig_set [--check] FILE GROUP KEY=VALUE...
# Creates the file or the group if needed. With --check nothing is written: exit 0 = it would change, 10 = already as asked.
kconfig_set() {
  python3 -I - "$@" <<'PY'
import os, sys, tempfile
args = sys.argv[1:]
check = args and args[0] == "--check"
if check:
    args = args[1:]
path, group, *pairs = args
kv = dict(p.split("=", 1) for p in pairs)
lines = open(path, encoding="utf-8").read().splitlines() if os.path.exists(path) else []
header = "[" + group + "]"
out, in_group, found, done = [], False, False, set()
def flush():
    for k, v in kv.items():
        if k not in done:
            out.append(f"{k}={v}")
            done.add(k)
for line in lines:
    stripped = line.strip()
    if stripped.startswith("[") and stripped.endswith("]"):
        if in_group:
            flush()
        in_group = stripped == header
        found = found or in_group
        out.append(line)
        continue
    if in_group and "=" in line:
        key = line.split("=", 1)[0].strip()
        if key in kv:
            out.append(f"{key}={kv[key]}")
            done.add(key)
            continue
    out.append(line)
if in_group:
    flush()
if not found:
    if out and out[-1].strip():
        out.append("")
    out.append(header)
    flush()
new = "\n".join(out) + "\n"
old = ("\n".join(lines) + "\n") if lines else None
if new == old:
    sys.exit(10)
if check:
    sys.exit(0)
d = os.path.dirname(path) or "."
os.makedirs(d, exist_ok=True)
fd, tmp = tempfile.mkstemp(dir=d, prefix=".kconfig-")
with os.fdopen(fd, "w", encoding="utf-8") as fh:
    fh.write(new)
if os.path.exists(path):
    os.chmod(tmp, os.stat(path).st_mode & 0o777)
os.replace(tmp, path)
PY
}

# Switch Kate's plugins on or off (KATE_PLUGINS_ON / KATE_PLUGINS_OFF). Kate keeps this per SESSION, in
# ~/.local/share/kate/anonymous.katesession (the session you get when you just start Kate) and
# ~/.local/share/kate/sessions/*.katesession (named ones), group [Kate Plugins]. Only those keys are changed; every other
# setting in those files stays. Each file is backed up first and the undo restores it. A session created later starts with
# Kate's 8 defaults again: Settings > Configure Kate > Plugins, or copy the keys.
kate_plugins() {
  local dir="$HOME/.local/share/kate" f p bdir="$DATA_DIR/kate-backups/$TIMESTAMP" rc
  local -a files=("$dir/anonymous.katesession") pairs=()
  for f in "$dir"/sessions/*.katesession; do if [[ -f $f ]]; then files+=("$f"); fi; done
  for p in "${KATE_PLUGINS_ON[@]}"; do pairs+=("$p=true"); done
  for p in "${KATE_PLUGINS_OFF[@]}"; do pairs+=("$p=false"); done
  if pgrep -x kate >/dev/null 2>&1; then
    warn "Kate is running: it rewrites its session files when it quits and would undo the plugin settings. Quit Kate and run ./setup.sh again."
  fi
  for f in "${files[@]}"; do
    rc=0; kconfig_set --check "$f" "Kate Plugins" "${pairs[@]}" || rc=$?
    if (( rc == 10 )); then ok "Kate plugins already set in ${f/#$HOME/~}"; continue; fi
    if (( rc != 0 )); then warn "Could not read ${f/#$HOME/~} (exit $rc); left alone"; continue; fi
    if [[ -e $f ]]; then   # the undo record comes BEFORE the change, and only for what this run changes
      mkdir -p "$bdir" && cp -p "$f" "$bdir/${f##*/}"
      record_undo "cp -p $(printf %q "$bdir/${f##*/}") $(printf %q "$f")"
    else
      record_undo "rm -f $(printf %q "$f")"
    fi
    kconfig_set "$f" "Kate Plugins" "${pairs[@]}"
    ok "Kate plugins set in ${f/#$HOME/~} (${#KATE_PLUGINS_ON[@]} on, ${#KATE_PLUGINS_OFF[@]} off on purpose)"
  done
}

# Add what is MISSING from a JSON settings file you already have, from the file this setup ships (OURS). The setup never
# overwrites a file of yours, so an older install keeps its older settings forever: Kate then ignores new defaults (the
# basedpyright level, found on the user's real machine). This adds missing keys, recursively, and changes nothing else:
# every value you set stays. A backup is made first and the undo restores it.
#   add_missing_json_keys [--check] FILE OURS    exit 0 = changed (written), 10 = nothing missing, 2 = FILE is not readable JSON
add_missing_json_keys() {
  python3 -I - "$@" <<'PY'
import json, os, sys, tempfile
args = sys.argv[1:]
check = bool(args) and args[0] == "--check"
if check:
    args = args[1:]
path, ours_path = args
ours = json.load(open(ours_path, encoding="utf-8"))
try:
    user = json.load(open(path, encoding="utf-8"))
except (OSError, ValueError):
    sys.exit(2)
def add(u, o):
    changed = False
    for key, value in o.items():
        if key not in u:
            u[key] = value
            changed = True
        elif isinstance(u[key], dict) and isinstance(value, dict):
            changed = add(u[key], value) or changed
    return changed
if not isinstance(user, dict) or not add(user, ours):
    sys.exit(10 if isinstance(user, dict) else 2)
if check:
    sys.exit(0)
fd, tmp = tempfile.mkstemp(dir=os.path.dirname(path) or ".", prefix=".settings-")
with os.fdopen(fd, "w", encoding="utf-8") as fh:
    json.dump(user, fh, indent=2)
    fh.write("\n")
os.chmod(tmp, os.stat(path).st_mode & 0o777)
os.replace(tmp, path)
PY
}

# Use add_missing_json_keys on one of your existing files, with backup and undo (both before the change).
migrate_user_json() {   # FILE OURS
  local file="$1" ours="$2" rc=0 bdir="$DATA_DIR/settings-backups/$TIMESTAMP" bname
  if [[ ! -f $file ]]; then return 0; fi
  add_missing_json_keys --check "$file" "$ours" || rc=$?
  if (( rc == 10 )); then return 0; fi
  if (( rc != 0 )); then warn "${file/#$HOME/~} is not valid JSON (exit $rc); left alone"; return 0; fi
  bname="${file#"$HOME"/}"; bname="${bname//\//_}"
  mkdir -p "$bdir" && cp -p "$file" "$bdir/$bname"
  record_undo "cp -p $(printf %q "$bdir/$bname") $(printf %q "$file")"
  add_missing_json_keys "$file" "$ours"
  ok "Added the missing defaults to ${file/#$HOME/~}; what you set is untouched (backup in ${bdir/#$HOME/~})"
}

# Helix: the same idea for languages.toml (TOML, so a block is appended instead of rewriting the file): our basedpyright
# level is added only if YOU have not set typeCheckingMode yourself, the result must still parse, otherwise the file is restored.
migrate_helix_basedpyright() {
  local file="$HOME/.config/helix/languages.toml" bdir="$DATA_DIR/settings-backups/$TIMESTAMP" rc=0
  if [[ ! -f $file ]]; then return 0; fi
  python3 -I - "$file" <<'PY' || rc=$?
import sys, tomllib
try:
    c = tomllib.load(open(sys.argv[1], "rb"))
except (OSError, ValueError):
    sys.exit(2)
cfg = c.get("language-server", {}).get("basedpyright", {}).get("config", {})
sys.exit(10 if "typeCheckingMode" in (cfg.get("basedpyright") or {}) else 0)
PY
  if (( rc == 10 )); then return 0; fi
  if (( rc != 0 )); then warn "${file/#$HOME/~} is not valid TOML (exit $rc); left alone"; return 0; fi
  mkdir -p "$bdir" && cp -p "$file" "$bdir/helix_languages.toml"
  record_undo "cp -p $(printf %q "$bdir/helix_languages.toml") $(printf %q "$file")"
  printf '\n# Added by workstation-setup: basedpyright'"'"'s own default level is very strict; "standard" is pyright'"'"'s default.\n[language-server.basedpyright.config.basedpyright]\ntypeCheckingMode = "standard"\n' >> "$file"
  if python3 -I -c 'import sys, tomllib; tomllib.load(open(sys.argv[1], "rb"))' "$file" 2>/dev/null; then
    ok "Added the basedpyright level \"standard\" to ${file/#$HOME/~}; what you set is untouched (backup in ${bdir/#$HOME/~})"
  else
    cp -p "$bdir/helix_languages.toml" "$file"
    warn "Appending to ${file/#$HOME/~} would break it (a conflicting table?): restored. Add [language-server.basedpyright.config.basedpyright] typeCheckingMode = \"standard\" yourself"
  fi
}

kate_setup() {
  apt_install "${PKGS_KATE[@]}"
  # Language servers for Kate's LSP client: ours (basedpyright, ruff, cmake, taplo) in
  # addition to Kate's defaults (clangd, rust-analyzer, bash-language-server). Merged
  # over Kate's built-in settings by Kate itself. JSON/YAML servers are not installed
  # on purpose: their defaults download schemas from the internet.
  install_file .config/kate/lspclient/settings.json
  migrate_user_json "$HOME/.config/kate/lspclient/settings.json" "$FILES/home/.config/kate/lspclient/settings.json"
  # The Format plugin runs on SAVE by default and only knows autopep8 for Python: format on request only, with ruff.
  install_file .config/kate/formatting/settings.json
  migrate_user_json "$HOME/.config/kate/formatting/settings.json" "$FILES/home/.config/kate/formatting/settings.json"
  install_file .local/bin/ws-pyformat 755
  kate_plugins
}

nice_to_have() { apt_install "${PKGS_NICE_TO_HAVE[@]}"; }

# Helix from its release tarball (the project publishes no checksum file: trust on first use, then pinned by the
# lock). Helix finds its 'runtime' directory next to the real binary, so the binary is linked, not copied.
helix_install_upstream() {
  local ver name dest="$HOME/.local/opt" bin="$HOME/.local/bin"
  ver="$(helix_version || true)"
  if [[ -z $ver ]]; then warn "Could not determine the latest Helix release"; return 1; fi
  if binary_is_version "$bin/hx" "$ver"; then ok "Helix $ver is the newest stable release"; return 0; fi
  name="helix-${ver}-$(host_arch)-linux"
  fetch_verified "$(helix_url "$ver")" "$STATE_DIR/helix.tar.xz" || return 1
  mkdir -p "$dest" "$bin" || return 1
  # Undo records come BEFORE the step that can fail, and only for what this run creates.
  if [[ ! -e $dest/$name ]]; then record_undo "rm -rf $(printf %q "$dest/$name")"; fi
  if [[ ! -e $bin/hx && ! -L $bin/hx ]]; then record_undo "rm -f ~/.local/bin/hx"; fi
  tar -xJf "$STATE_DIR/helix.tar.xz" -C "$dest" || return 1
  [[ -x $dest/$name/hx ]] || { warn "The Helix archive does not contain $name/hx"; return 1; }
  ln -sf "$dest/$name/hx" "$bin/hx" || return 1
  hash -r
  ok "Installed Helix $ver to $dest/$name (the newest upstream release)"
}

helix_setup() {
  # No snap: snapd auto-refreshes from the online Snap Store.
  install_upstream_first Helix helix helix_install_upstream "$HELIX_FROM_ARCHIVE" "hx helix" || return 1
  install_file .config/helix/config.toml
  install_file .config/helix/languages.toml
  migrate_helix_basedpyright
}

# Neovim from its release tarball (the newest upstream release wins over Ubuntu's older package, your decision for
# tools without an LTS line). The project's release page was not readable from the development sandbox, so a published
# checksum file could not be confirmed: like Helix this is trust on first use, then pinned by the lock. The tarball
# unpacks to bin/ lib/ share/ (Neovim finds its runtime relative to the real binary), so the binary is linked, not copied.
nvim_install_upstream() {
  local ver asset dest="$HOME/.local/opt" bin="$HOME/.local/bin" dir
  asset="$(nvim_asset)" || { warn "No Neovim release for $(host_arch)"; return 1; }
  ver="$(nvim_version || true)"
  if [[ ! $ver =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then warn "Could not determine the latest Neovim release"; return 1; fi
  if binary_is_version "$bin/nvim" "$ver"; then ok "Neovim $ver is the newest stable release"; return 0; fi
  dir="$dest/nvim-$ver"
  fetch_verified "$(nvim_url "$ver")" "$STATE_DIR/nvim.tar.gz" || return 1
  mkdir -p "$dest" "$bin" || return 1
  # Undo records come BEFORE the step that can fail, and only for what this run creates.
  if [[ ! -e $dir ]]; then record_undo "rm -rf $(printf %q "$dir")"; fi
  if [[ ! -e $bin/nvim && ! -L $bin/nvim ]]; then record_undo "rm -f ~/.local/bin/nvim"; fi
  rm -rf "$dir.partial"; mkdir "$dir.partial" || return 1
  tar -xzf "$STATE_DIR/nvim.tar.gz" -C "$dir.partial" --strip-components=1 || { rm -rf "$dir.partial"; return 1; }
  [[ -x $dir.partial/bin/nvim ]] || { warn "The Neovim archive does not contain $asset/bin/nvim"; rm -rf "$dir.partial"; return 1; }
  rm -rf "$dir"; mv "$dir.partial" "$dir" || return 1
  ln -sf "$dir/bin/nvim" "$bin/nvim" || return 1
  hash -r
  ok "Installed Neovim $ver to $dir (the newest upstream release)"
}

nvim_setup() {
  install_upstream_first Neovim neovim nvim_install_upstream "$NVIM_FROM_ARCHIVE" nvim || return 1
  # An init.lua next to the user's init.vim would make Neovim stop with "Conflicting configs" (E5422): leave theirs alone.
  if [[ -e $HOME/.config/nvim/init.vim ]]; then
    warn "You have ~/.config/nvim/init.vim; not adding init.lua (Neovim refuses to load both). Your config is untouched."
    return 0
  fi
  install_file .config/nvim/init.lua
}

# Install containers.conf (pull_policy = "never"). Guard against a podman that rejects it: if podman
# worked before the file and fails after it, remove the file again. If podman does not work at all
# here (a container without user namespaces), that says nothing about the file, so it stays.
install_podman_conf() {
  local conf="$HOME/.config/containers/containers.conf" existed=0 worked=0
  if [[ -e $conf ]]; then existed=1; fi
  if podman info >/dev/null 2>&1; then worked=1; fi
  install_file .config/containers/containers.conf
  if (( worked )) && ! podman info >/dev/null 2>&1; then
    if (( existed == 0 )); then rm -f "$conf"; fi
    warn "podman did not accept containers.conf (pull_policy); left it out"
    return 1
  fi
}

containers() {
  if on "$INSTALL_PODMAN"; then
    apt_install "${PKGS_PODMAN[@]}"
    # Whenever podman is installed, it must never pull images by itself.
    if have podman; then install_podman_conf || true; fi
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

# starship from its release tarball, checked against the .sha256 the project publishes.
starship_install_upstream() {
  local asset base tag fresh=0 bin="$HOME/.local/bin"; asset="$(starship_asset)"; base="$(starship_base_url)"
  tag="${STARSHIP_VERSION:-$(release_tag_of "$base/$asset" || true)}"
  if [[ -n $tag ]] && binary_is_version "$bin/starship" "${tag#v}"; then ok "starship ${tag#v} is the newest stable release"; return 0; fi
  fetch_published "$base/$asset" "$STATE_DIR/$asset" "$base/$asset.sha256" || return 1
  mkdir -p "$bin" || return 1
  if [[ ! -e $bin/starship && ! -L $bin/starship ]]; then fresh=1; fi
  if (( fresh )); then record_undo "rm -f ~/.local/bin/starship"; fi
  tar -xzf "$STATE_DIR/$asset" -C "$bin" starship || return 1
  hash -r
  ok "starship $("$bin/starship" --version | awk 'NR == 1 { print $2 }') installed in ~/.local/bin (the newest upstream release)"
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
  install_file .bashrc.d/16-aliases.sh      # after 15-oh-my-bash.sh on purpose: Oh My Bash replaces ls/ll/la/grep
  if on "$ENFORCE_OFFLINE_ENV"; then install_file .bashrc.d/20-offline.sh; fi
  install_file .inputrc
  install_file .local/bin/ws-init 755
  install_file .local/bin/ws-doctor 755
  install_cheatsheet

  if on "$INSTALL_STARSHIP" && ! on "$INSTALL_OH_MY_BASH"; then
    install_upstream_first starship starship starship_install_upstream "$STARSHIP_FROM_ARCHIVE" starship || true
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

# The global git defaults (SET_GIT_DEFAULTS), "key=value". One list for the install and for --reset-defaults.
GIT_DEFAULTS=(init.defaultBranch=main pull.rebase=true rerere.enabled=true fetch.prune=true
              push.autoSetupRemote=true merge.conflictStyle=zdiff3 diff.colorMoved=default)
GIT_DEFAULTS_DELTA=(core.pager=delta "interactive.diffFilter=delta --color-only" delta.navigate=true delta.line-numbers=true)

git_defaults() {
  local kv
  for kv in "${GIT_DEFAULTS[@]}"; do git_set "${kv%%=*}" "${kv#*=}"; done
  if have delta; then
    for kv in "${GIT_DEFAULTS_DELTA[@]}"; do git_set "${kv%%=*}" "${kv#*=}"; done
  fi
  if have git-lfs; then
    # Its global filter was never recorded for --undo (found by --reset-defaults in the E2E): record it when this run adds it.
    if [[ -z "$(git config --global --get filter.lfs.process 2>/dev/null || true)" ]]; then record_undo "git lfs uninstall --skip-repo"; fi
    git lfs install --skip-repo >/dev/null
  fi
  ok "Git defaults set (existing settings were kept)"
}

project_templates() {
  install_templates "$FILES/templates" generic
}

desktop_tweaks() {
  have gsettings || return 0
  if ! have_desktop_session; then
    warn "No desktop session detected; run setup.sh from a logged-in desktop"
    warn "to apply the font setting."
    return 0
  fi
  # Recent Ubuntu releases use a small default monospace font; the terminal follows this.
  # Ubuntu's own privacy and reporting settings are NOT touched (decided by the user: the setup leaves
  # Ubuntu's own telemetry and services as Ubuntu ships them).
  if on "$SET_GNOME_FONT"; then gset org.gnome.desktop.interface monospace-font-name "$(gnome_mono_font)"; fi
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

  # From now on, never pull images implicitly.
  install_podman_conf
}

# ============================================================================
# DRY RUN (--check)
# ============================================================================
plan_tool() {
  # $5 (optional) = the value of the tool's *_FROM_ARCHIVE switch: given, the newest upstream release is preferred.
  local label="$1" cmd="$2" pkg="$3" url="$4" from_archive="${5:-}" how cand
  if have "$cmd"; then how="already installed (--upgrade would move it to the newest upstream release)"
  elif [[ -n $from_archive ]] && ! on "$from_archive" && on "$ALLOW_CURL_INSTALLERS"; then
    how="download $url"
    if [[ -n ${DOWNLOAD_SHA256[$url]:-} ]]; then how+=" (SHA-256 pinned)"; fi
    cand="$(apt_candidates "$pkg" | awk '{ print $2 }')"
    if [[ -n $cand ]]; then how+="; the archive has $pkg $cand: not used, the newest upstream release wins (archive only if the download fails)"; fi
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
  elif (( OS_VERIFIED )); then
    ok "Ubuntu ${VERSION_ID:-?} LTS: a release this setup is verified on (${SUPPORTED_UBUNTU})"
    if [[ -n $OS_INFO ]]; then log "$OS_INFO"; fi
  fi
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
      if ! pkg_applies "$pkg"; then
        printf '    %-34s not needed on Ubuntu %s (%s)\n' "$pkg" "$(os_version_id)" "${PKG_SINCE_NOTE[$pkg]:-it exists only on newer releases}"
        continue
      fi
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
  if on "$INSTALL_PYTHON"; then plan_tool uv uv uv "$(uv_base_url)/$(uv_asset) (checked against the published .sha256)" "$UV_FROM_ARCHIVE"; fi
  if on "$INSTALL_RUST"; then plan_tool rustup rustup rustup "$(rustup_init_url) (checked against the published .sha256)" "$RUSTUP_FROM_ARCHIVE"; fi
  plan_tool lazygit lazygit lazygit "$(lazygit_base_url)/lazygit_<version>_linux_$(host_arch).tar.gz (checked against the published checksums.txt)" "$LAZYGIT_FROM_ARCHIVE"
  if on "$INSTALL_HELIX"; then
    if [[ -n ${HELIX_VERSION:-} ]]; then plan_tool Helix hx helix "$(helix_url "$HELIX_VERSION")" "$HELIX_FROM_ARCHIVE"
    else plan_tool Helix hx helix "https://github.com/helix-editor/helix/releases/latest (trust on first use: Helix publishes no checksum)" "$HELIX_FROM_ARCHIVE"; fi
  fi
  if on "$INSTALL_NVIM"; then
    if [[ -n ${NVIM_VERSION:-} ]]; then plan_tool Neovim nvim neovim "$(nvim_url "$NVIM_VERSION")" "$NVIM_FROM_ARCHIVE"
    else plan_tool Neovim nvim neovim "https://github.com/neovim/neovim/releases/latest (trust on first use: no checksum file confirmed)" "$NVIM_FROM_ARCHIVE"; fi
  fi
  if on "$INSTALL_STARSHIP" && ! on "$INSTALL_OH_MY_BASH"; then plan_tool starship starship starship "$(starship_base_url)/$(starship_asset) (checked against the published .sha256)" "$STARSHIP_FROM_ARCHIVE"; fi
  if on "$INSTALL_BASH_LSP" && ! on "$NODE_FROM_ARCHIVE"; then
    printf '    %-10s %s\n' "Node.js" "newest LTS (${NODE_LTS_VERSION:-resolved at install time}) from nodejs.org, checked against its published SHASUMS256.txt; the archive's nodejs/npm only as a fallback"
  fi
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
  echo "    generated $CHEATSHEET_FILE (refreshed; backup kept if you edited it)"
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

# basedpyright's own default level ("recommended") is so strict that ordinary working code shows a page of errors in
# Kate and Helix (found on the user's real machine). The editors are given "standard" through the language-server
# settings. This test speaks LSP to the real server the way Kate does (both Kate versions), with NO project config:
# a small untyped but working file must come out quiet; the control without settings must be strict, or it proves nothing.
t_basedpyright_default() {
  needs basedpyright-langserver python3
  local py="$FILES/selftest/lsp/default_level.py" kate="$HOME/.config/kate/lspclient/settings.json" settings mode rc=0
  [[ -f $kate ]] || kate="$FILES/home/.config/kate/lspclient/settings.json"
  settings="$(python3 -I -c 'import json, sys; print(json.dumps(json.load(open(sys.argv[1]))["servers"]["python"]["settings"]))' "$kate")" \
    || { echo "the Python server entry in $kate has no \"settings\": the file predates the quiet default and the setup never overwrites yours. Re-run ./setup.sh (it adds what is missing), or see the README troubleshooting row for Python errors"; return 1; }
  python3 -I -c 'import sys, tomllib; c = tomllib.load(open(sys.argv[1], "rb")); assert c["language-server"]["basedpyright"]["config"]["basedpyright"]["typeCheckingMode"] == "standard"' \
    "$FILES/home/.config/helix/languages.toml" || { echo "Helix's basedpyright config does not set typeCheckingMode = standard"; return 1; }
  for mode in didchange configuration; do
    rc=0; python3 -I "$py" "$mode" "$settings" || rc=$?
    (( rc == 0 )) || { echo "basedpyright is too noisy for an editor started the way Kate ($mode) does it, or did not answer (exit $rc)"; return 1; }
  done
  rc=0; python3 -I "$py" didchange none || rc=$?
  if (( rc == 0 )); then echo "control: basedpyright without settings was NOT strict: its default changed, this test proves little now"; return 78; fi
  (( rc == 3 )) || { echo "control run failed (exit $rc)"; return 1; }
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

t_nvim() {
  needs_on INSTALL_NVIM
  local nv rc=0; nv="$(command -v nvim || true)"
  [[ -n $nv ]] || { echo "Neovim not found"; exit 1; }
  "$nv" --version | head -n 2
  if [[ -e $HOME/.config/nvim/init.vim ]]; then echo "you have your own init.vim: nothing more to check"; exit 78; fi
  [[ -f $HOME/.config/nvim/init.lua ]] || { echo "~/.config/nvim/init.lua is missing"; exit 1; }
  if ! grep -q ws_nvim_config "$HOME/.config/nvim/init.lua"; then
    echo "you have your own Neovim configuration: nothing more to check"; exit 78
  fi
  # The installed config loads without an error, and (with basedpyright installed) Neovim's own LSP client gets the
  # quiet "standard" level: the one real mistake is reported, the missing type hints are not.
  cp "$FILES/selftest/lsp/nvim_check.py" nvim_check.py; cp "$FILES/selftest/lsp/nvim_check.lua" nvim_check.lua
  if have basedpyright-langserver; then
    timeout 150 "$nv" --headless -n -i NONE nvim_check.py -c 'luafile nvim_check.lua' > nvim.txt 2>&1 || rc=$?
  else
    timeout 60 "$nv" --headless -n -i NONE -c 'lua assert(vim.g.ws_nvim_config)' -c 'qa!' > nvim.txt 2>&1 || rc=$?
  fi
  cat nvim.txt
  local errs; errs="$(grep -E 'Error detected while processing|E5[0-9]{3}:' nvim.txt || true)"
  [[ -z $errs ]] || { echo "Neovim reported errors in its configuration"; exit 1; }
  case $rc in
    0) ;;
    3) echo "no language server answered"; exit 78 ;;
    *) echo "Neovim check failed (exit $rc)"; exit 1 ;;
  esac
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
# Where an installed command came from, in plain words and with the command that removes it
# (used by the no-cloud self-test, which finds tools this setup did not install itself).
describe_installed() {
  local path real pkg
  path="$(command -v "$1" 2>/dev/null || true)"; [[ -n $path ]] || { echo "not found"; return 0; }
  real="$(readlink -f "$path" 2>/dev/null || echo "$path")"
  if pkg="$(dpkg -S "$real" 2>/dev/null | head -n1 | cut -d: -f1)" && [[ -n $pkg ]]; then
    echo "$path, from the APT package $pkg; check what it is and what needs it ('apt show $pkg', 'apt rdepends --installed $pkg') before you remove it"
  elif [[ $real == */node_modules/* ]]; then
    echo "$path, an npm global package: npm uninstall -g $1"
  elif [[ $path == /snap/* || $real == /snap/* ]]; then
    echo "$path, from a snap: sudo snap remove $1"
  else
    echo "$path, installed by hand or by another tool; remove or rename that file"
  fi
}

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
  # The runtime offline lock lives in ~/.bashrc.d; without the loader it is not active.
  if on "$ENFORCE_OFFLINE_ENV" && ! grep -q 'bashrc.d' "$HOME/.bashrc" 2>/dev/null; then
    warnings+=("~/.bashrc does not load ~/.bashrc.d, so the offline lock for uv/pip/cargo is not active in new shells (ENABLE_SHELL_LOADER=1, or add the loader yourself)"); fi
  if on "$INSTALL_KATE" && have kate; then
    # Kate's default JSON/YAML language servers download schemas from the internet:
    # fine while they are not installed, a policy problem if someone installs them.
    for u in vscode-json-languageserver yaml-language-server; do
      if have "$u"; then problems+=("$u is installed ($(describe_installed "$u")): Kate would use it, and it fetches schemas online. This setup never installs it, so it was already on this machine: remove it as described, or keep it knowingly"); fi
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
# Kate (23.08 in Ubuntu 24.04 and 25.12 in 26.04, checked in its source) supports ONE server per language, with a
# flat "command" list; a nested "servers" map inside a language is silently ignored. Check the shape Kate reads.
for lang, entry in servers.items():
    assert "servers" not in entry, f"{lang}: nested 'servers' is ignored by Kate; use a flat 'command'"
    cmd = entry["command"]
    assert isinstance(cmd, list) and cmd and all(isinstance(x, str) for x in cmd), f"{lang}: 'command' must be a list of strings"
assert servers["python"]["command"][0] == "basedpyright-langserver"
print("Kate LSP settings parse; servers:", ", ".join(sorted(servers)))
EOT
  QT_QPA_PLATFORM=offscreen kate --version
  # The plugin set: every plugin we switch on must exist in this Kate, and the session file Kate starts from must say so.
  # A plugin that is missing from the package (renamed in a newer Kate) would silently not load.
  local p lib f="$HOME/.local/share/kate/anonymous.katesession" missing=()
  for p in "${KATE_PLUGINS_ON[@]}"; do
    lib="$(find /usr/lib -path '*ktexteditor*' -name "$p.so" -print -quit 2>/dev/null || true)"
    if [[ -z $lib ]]; then missing+=("$p"); fi
  done
  if (( ${#missing[@]} )); then echo "these Kate plugins are not in the installed Kate (renamed?): ${missing[*]}"; return 1; fi
  [[ -f $f ]] || { echo "$f does not exist: Kate's plugin set was not written"; return 1; }
  for p in "${KATE_PLUGINS_ON[@]}"; do
    grep -qx "$p=true" "$f" || { echo "$p is not switched on in $f"; return 1; }
  done
  for p in "${KATE_PLUGINS_OFF[@]}"; do
    grep -qx "$p=false" "$f" || { echo "$p must be switched OFF in $f (it contacts the internet or can fetch remote files)"; return 1; }
  done
  # The Format plugin: it formats on SAVE unless told otherwise (and would reformat code and JSON behind your back), and for
  # Python it only knows autopep8, which is not installed ("autopep8 is not installed" on every save). Our settings turn
  # format-on-save off and send "autopep8" to ws-pyformat (ruff). Check the shape Kate reads, then that ws-pyformat really formats.
  python3 -I - "$HOME/.config/kate/formatting/settings.json" <<'EOT'
import json, sys
c = json.load(open(sys.argv[1]))
assert c.get("formatOnSave") is False, "format on save must be off (Kate would reformat code on every save)"
assert c.get("clang-format", {}).get("formatOnSave") is False, "clang-format sets formatOnSave true itself: it must be switched off too"
assert c["autopep8"]["command"] == ["ws-pyformat"], "Python formatting must go through ws-pyformat (ruff)"
print("Kate formatting settings: format on save off, Python formatted by ruff on request")
EOT
  if have ruff; then
    printf 'x   =   [1,2,\n 3]\n' > fmt_sample.py
    local out; out="$("$HOME/.local/bin/ws-pyformat" fmt_sample.py)"
    [[ $out == "x = [1, 2, 3]" ]] || { echo "ws-pyformat did not format with ruff, got: $out"; return 1; }
  fi
  # Kate's built-in terminal panel needs konsole-kpart (Kate only suggests it): without it the panel says
  # "Konsole not installed". A part file, not a program to run, so check that the package is there.
  local st
  # shellcheck disable=SC2016
  st="$(dpkg-query -W -f='${Status}' konsole-kpart 2>/dev/null || true)"   # captured: no pipe into grep -q under pipefail
  [[ $st == *"install ok installed"* ]] || { echo "konsole-kpart is missing: Kate's terminal panel would say 'Konsole not installed'"; return 1; }
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
  run_test "basedpyright is quiet in the editors"     t_basedpyright_default
  run_test "Python: offline install from wheelhouse"  t_python_offline
  run_test "Rust: host build"                         t_rust_host
  run_test "Rust: offline build from crate cache"     t_rust_offline
  run_test "Language servers present"                 t_language_servers
  run_test "Helix loads its configuration"            t_helix
  run_test "Neovim loads its configuration, quiet LSP" t_nvim
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
  mkdir -p "$OUT_DIR"
  MANIFEST_FILE="$OUT_DIR/workstation-manifest-$TIMESTAMP.txt"
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
  ln -sf "$MANIFEST_FILE" "$OUT_DIR/workstation-manifest-latest.txt"
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
    if have nvim; then printf ': "${NVIM_VERSION:=%s}"\n' "$(nvim --version | awk 'NR == 1 { print $2 }')"; fi
    # shellcheck disable=SC2016
    if have starship; then printf ': "${STARSHIP_VERSION:=v%s}"\n' "$(starship --version | awk 'NR == 1 { print $2 }')"; fi
    # shellcheck disable=SC2016
    if have rustup; then printf ': "${RUSTUP_VERSION:=%s}"\n' "$(rustup --version 2>/dev/null | awk 'NR == 1 { print $2 }')"; fi
    local lg; lg="$(command -v lazygit || true)"
    # shellcheck disable=SC2016
    if [[ -n $lg ]]; then printf ': "${LAZYGIT_VERSION:=v%s}"\n' "$(lazygit_installed_version "$lg")"; fi
    # shellcheck disable=SC2016
    if [[ -s $NERD_FONT_DIR/.version ]]; then printf ': "${NERD_FONT_VERSION:=%s}"\n' "$(<"$NERD_FONT_DIR/.version")"; fi
    # shellcheck disable=SC2016
    if [[ -d $OMB_DIR/.git ]]; then printf ': "${OH_MY_BASH_COMMIT:=%s}"\n' "$(git -C "$OMB_DIR" rev-parse HEAD)"; fi
    # shellcheck disable=SC2016
    if [[ "$(readlink "$HOME/.local/bin/node" 2>/dev/null || true)" == */opt/node-v* ]]; then
      printf ': "${NODE_LTS_VERSION:=%s}"\n' "$("$HOME/.local/bin/node" --version)"
    fi
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
  Until then: ~/.cargo/bin is not on your PATH, and the aliases and the prompt are not active.
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
  "SET_GNOME_FONT|set the GNOME monospace font (JetBrainsMono Nerd Font Mono 11; JetBrains Mono 11 without the Nerd Font)"
  "JOIN_DOCKER_GROUP|add your user to group 'docker' (only with INSTALL_DOCKER=1; equivalent to root)"
  "ENABLE_SHELL_LOADER|append ONE marked block to ~/.bashrc that loads ~/.bashrc.d (aliases, PATH, prompt)"
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

STEP_WHY["Base CLI tools"]="Everyday command-line tools (git, ripgrep, fzf, jq, tmux, ...) and the tldr example pages."
STEP_TOUCHES["Base CLI tools"]="apt packages; ~/.config/tealdeer/config.toml; network: tldr pages, once."

STEP_WHY["JetBrains Mono Nerd Font"]="JetBrains Mono with icon glyphs added (the 'Nerd Font' and 'Nerd Font Mono' families), installed for your user only, so prompts and themes can show icons. It is not in the Ubuntu archive: downloaded once from the project's GitHub release and checksum-verified. To use it, pick 'JetBrainsMono Nerd Font Mono' as the terminal font (SET_GNOME_FONT=1 does it for GNOME)."
STEP_TOUCHES["JetBrains Mono Nerd Font"]="~/.local/share/fonts/JetBrainsMonoNerdFont (32 font files) and the font cache; network: github.com release download, once (checked against the project's published SHA-256.txt)."

STEP_WHY["Oh My Bash"]="(Only with INSTALL_OH_MY_BASH=1.) The Oh My Bash framework (themes, aliases, plugins) from ONE pinned commit, loaded from ~/.bashrc.d/15-oh-my-bash.sh with its GitHub update check switched off. Its own installer is not used because it would replace your ~/.bashrc. While it is enabled it owns the prompt, so the starship prompt is not started."
STEP_TOUCHES["Oh My Bash"]="~/.local/share/oh-my-bash (git clone of one commit), ~/.bashrc.d/15-oh-my-bash.sh; network: github.com, at install time only."

STEP_WHY["Kate editor"]="Kate, the KDE text editor (a graphical editor next to Helix), as a Debian package from the Ubuntu archive (not a snap or Flatpak), plus konsole-kpart, the part behind Kate's built-in terminal panel (Kate only suggests it, so without it the panel says \"Konsole not installed\"). It brings in KDE libraries. Its built-in language-server client is pointed at the same local servers Helix uses (clangd, rust-analyzer, basedpyright, ruff, taplo, cmake, bash); I found no telemetry or update-check dependency in Kate's build files. Kate switches on only 8 of its plugins by default, so this step also switches on a curated set for C/C++/Rust/Python/embedded work (Build, CMake Tools, Debugger, Symbol Viewer, Snippets, Formatting, Git Blame, File Browser, Colored Brackets), changing only the plugin keys in Kate's session files (backed up first, restored by --undo), and keeps Compiler Explorer (sends your code to godbolt.org) and XML Validation (xmllint may fetch schemas) OFF."
STEP_TOUCHES["Kate editor"]="apt packages (kate, konsole-kpart and KDE libraries); ~/.config/kate/lspclient/settings.json and ~/.config/kate/formatting/settings.json (new, or, if you already have one, only the MISSING defaults are added to it: your values stay, a backup goes to ~/.local/share/workstation/settings-backups); ~/.local/bin/ws-pyformat; the [Kate Plugins] group of ~/.local/share/kate/anonymous.katesession and your existing ~/.local/share/kate/sessions/*.katesession (backed up under ~/.local/share/workstation/kate-backups)."

STEP_WHY["Extra terminal tools"]="Nice-to-have terminal tools: zellij (a beginner-friendlier terminal multiplexer than tmux) and difftastic (structural diffs). Packages the archive of your Ubuntu release lacks are skipped and reported."
STEP_TOUCHES["Extra terminal tools"]="apt packages."

STEP_WHY["C/C++ toolchain"]="Compilers, build systems, debuggers, static analyzers and test frameworks for C and C++."
STEP_TOUCHES["C/C++ toolchain"]="apt packages; ~/.gdbinit."

STEP_WHY["GUI tools"]="Meld, a visual diff and merge tool."
STEP_TOUCHES["GUI tools"]="apt package."

STEP_WHY["Python tools"]="uv (package and tool manager) and the Python developer tools (ruff, basedpyright, pre-commit, ...), installed per user. uv itself is the newest stable release from astral (checksum-verified, in ~/.local/bin): the newest upstream release wins over Ubuntu's older package, which is only the fallback (UV_FROM_ARCHIVE=1 prefers it). uv is told never to download Python interpreters."
STEP_TOUCHES["Python tools"]="apt packages; ~/.local (uv and the tools); ~/.config/uv/uv.toml; network: uv's release tarball (checked against astral's published checksum; the archive's package only as a fallback), PyPI for the tools."

STEP_WHY["Rust toolchain"]="rustup with the newest stable Rust, the editor components, and cargo tools compiled from source (slow). rustup's self-update is switched off."
STEP_TOUCHES["Rust toolchain"]="apt build libraries; ~/.rustup and ~/.cargo; network: rustup-init only if not in the archive (checked against the Rust project's published checksum), Rust servers, crates.io."

STEP_WHY["Offline documentation"]="Reference documentation that works without internet: C/C++ (cppreference), Python, CMake, POSIX, glibc, GDB."
STEP_TOUCHES["Offline documentation"]="apt packages (docs, man pages)."

STEP_WHY["Bash language server"]="Editor support for shell scripts. It needs Node.js: the newest LTS release from nodejs.org (the archive's is older; no APT repository is added), unpacked in your home directory and checked against the checksum the project publishes. Then the server is installed with npm into your home directory. npm is told not to contact the registry for update notices, funding messages or audits. NODE_FROM_ARCHIVE=1 uses Ubuntu's own nodejs/npm instead."
STEP_TOUCHES["Bash language server"]="~/.local/opt/node-<version> and links in ~/.local/bin (node, npm, npx, corepack); ~/.local (npm global prefix); npm settings in ~/.npmrc; network: nodejs.org, npm registry. With NODE_FROM_ARCHIVE=1: apt packages nodejs, npm."

STEP_WHY["Helix editor"]="The Helix terminal editor: the newest stable release from the project's tarball (the newest upstream release wins over Ubuntu's older package, which is only the fallback; HELIX_FROM_ARCHIVE=1 prefers it; never a snap), with a configuration that disables the JSON/YAML language servers because they download schemas."
STEP_WHY["Keep default apps"]="Installing an app can make it the one that opens a file type Ubuntu's own list does not decide (VLC for some audio formats, Inkscape for Visio files, a KDE helper for ssh:// links). Before the first install the setup recorded which app opened each file type; here it sets back every type whose app changed, so Ubuntu's defaults stay as they were. Nothing happens without a desktop."
STEP_TOUCHES["Keep default apps"]="~/.config/mimeapps.list (only entries for types whose app changed; --undo removes exactly those). KEEP_DEFAULT_APPS=0 switches this off."
STEP_WHY["Neovim editor"]="Neovim as a second terminal editor (Helix stays your default): the newest stable release from the project's tarball (the newest upstream release wins over Ubuntu's older package, which is only the fallback; NVIM_FROM_ARCHIVE=1 prefers it; never a snap), with a small plugin-free init.lua that uses the same local language servers as Helix and Kate. No plugin manager is installed, so Neovim never downloads anything by itself; JSON/YAML get no language server because those download schemas."
STEP_TOUCHES["Neovim editor"]="apt package, or ~/.local/opt/nvim-<version> and ~/.local/bin/nvim; ~/.config/nvim/init.lua (new file only: an init.lua of yours is never overwritten, and with an init.vim of yours it is not added at all); network: the GitHub release (trust on first use, then pinned by the lock); the archive's package only as a fallback. \$EDITOR stays Helix."
STEP_TOUCHES["Helix editor"]="apt package, or ~/.local/opt and ~/.local/bin/hx; ~/.config/helix/* (if you already have a languages.toml, only the basedpyright level is appended, and only if you set none; backup in ~/.local/share/workstation/settings-backups); network: the GitHub release (Helix publishes no checksum: trust on first use, then pinned by the lock); the archive's package only as a fallback."

STEP_WHY["Containers"]="Podman and Distrobox for isolated build environments (Docker only if you switched it on). With podman, a small config file makes it never pull images by itself."
STEP_TOUCHES["Containers"]="apt packages; ~/.config/containers/containers.conf (with podman); with Docker and JOIN_DOCKER_GROUP=1 also adds you to the 'docker' group (sudo)."

STEP_WHY["Shell (bash) setup"]="Aliases, history, prompt and integrations (fzf, zoxide, direnv, starship) and the ws- helper commands (ws-init, ws-doctor), written to ~/.bashrc.d, plus the generated cheat sheet (the strict offline lock is opt-in: ENFORCE_OFFLINE_ENV=1). They only take effect if ~/.bashrc loads ~/.bashrc.d: that single edit is ENABLE_SHELL_LOADER=1 (off by default; the summary prints the lines to add yourself)."
STEP_TOUCHES["Shell (bash) setup"]="files in ~/.bashrc.d, ~/.inputrc, ~/.local/bin, ~/.config/starship.toml, ~/workstation-setup/WORKSTATION-CHEATSHEET.md; with ENABLE_SHELL_LOADER=1 one marked block in ~/.bashrc; network: starship's release tarball (checked against its published checksum; the archive's package only as a fallback)."

STEP_WHY["Git setup"]="Switches lazygit's update check off. With SET_GIT_DEFAULTS=1 it also sets sensible global git defaults, only where you have not set a value yourself; GIT_NAME/GIT_EMAIL are applied if you give them."
STEP_TOUCHES["Git setup"]="~/.config/lazygit/config.yml; ~/.gitconfig only with SET_GIT_DEFAULTS=1 or GIT_NAME/GIT_EMAIL."

STEP_WHY["Project templates"]="Starter files for new projects (formatter, linter, pre-commit and CMake presets), copied into a project by ws-init without overwriting anything."
STEP_TOUCHES["Project templates"]="~/.local/share/workstation/templates."

STEP_WHY["Desktop settings"]="(Only with SET_GNOME_FONT=1.) A readable monospace font (JetBrainsMono Nerd Font Mono, which the terminal follows). Ubuntu's own privacy and reporting settings are left as Ubuntu ships them. Needs a desktop session."
STEP_TOUCHES["Desktop settings"]="GNOME settings of your user (dconf)."

STEP_WHY["Offline cache: Python wheels"]="Downloads a local library of Python packages now, so uv and pip can install them later without network."
STEP_TOUCHES["Offline cache: Python wheels"]="~/.local/share/workstation/wheelhouse; network: PyPI, now."

STEP_WHY["Offline cache: Rust crates"]="Downloads common Rust crates now, so cargo can build later without network."
STEP_TOUCHES["Offline cache: Rust crates"]="~/.cargo/registry and ~/.local/share/workstation/rust-offline-cache; network: crates.io, now."

STEP_WHY["Offline cache: container images"]="Pulls the container images now and tells podman never to pull images by itself afterwards."
STEP_TOUCHES["Offline cache: container images"]="podman image storage in your home directory; ~/.config/containers/containers.conf; network: image registry, now."

# The ordered list of install steps. Used by the real run and by --explain.
# Default apps (KEEP_DEFAULT_APPS, on by default). An apt install can make a new app the one that opens a file type that Ubuntu's
# own list (/usr/share/applications/gnome-mimeapps.list) does not decide: audited for the full install on 24.04, 95 such types,
# e.g. VLC for some audio formats, Inkscape for Visio files, a KDE helper (pulled in by Kate) for ssh:// and telnet:// links. The
# user decided that the setup must not change a default behind their back. Before the first install the setup records, with GNOME's
# own `gio mime` (the lookup the desktop itself uses), which app opens every file type that already has one; after the installs it
# sets back each type whose app changed (a user-level default in ~/.config/mimeapps.list). --undo removes exactly those entries
# again. Without a desktop (no gio or no mimeinfo.cache, e.g. a container) there is nothing to compare and nothing is done.
DEFAULTS_BEFORE=""
mime_types_known() {
  awk -F= '/^\[MIME Cache\]/ { s = 1; next } /^\[/ { s = 0 } s && NF >= 2 { print $1 }' \
    "${MIMEINFO_CACHE:-/usr/share/applications/mimeinfo.cache}" 2>/dev/null | sort -u
}
gio_default() { LC_ALL=C gio mime "$1" 2>/dev/null | sed -n 's/^Default application for .*: \(.*\.desktop\)$/\1/p' | head -n1 || true; }
defaults_snapshot() {
  on "$KEEP_DEFAULT_APPS" || return 0
  if ! have gio || [[ ! -r ${MIMEINFO_CACHE:-/usr/share/applications/mimeinfo.cache} ]]; then return 0; fi
  local t d
  DEFAULTS_BEFORE="$STATE_DIR/default-apps.before"
  mkdir -p "$STATE_DIR"; : > "$DEFAULTS_BEFORE"
  while read -r t; do
    d="$(gio_default "$t")"
    if [[ -n $d ]]; then printf '%s %s\n' "$t" "$d" >> "$DEFAULTS_BEFORE"; fi
  done < <(mime_types_known)
  log "Recorded which app opens $(wc -l < "$DEFAULTS_BEFORE") file types; checked again after the installs (KEEP_DEFAULT_APPS)."
}
# The undo of defaults_keep, as one python program: remove exactly the entries set here (Default Applications, and the same app at
# the front of Added Associations), keep everything else in the file; delete the file only if this run created it and it is empty.
UNPIN_PY='import os, sys
p, existed = sys.argv[1], sys.argv[2] == "1"
pins = dict(a.split("=", 1) for a in sys.argv[3:])
if not os.path.exists(p): sys.exit(0)
out, sec = [], None
for line in open(p, encoding="utf-8"):
    s = line.strip()
    if s.startswith("["):
        sec = s
    elif "=" in s and sec in ("[Default Applications]", "[Added Associations]"):
        k, v = s.split("=", 1)
        if k in pins:
            apps = [a for a in v.split(";") if a]
            if sec == "[Default Applications]" and apps[:1] == [pins[k]]: continue
            if sec == "[Added Associations]" and apps[:1] == [pins[k]]:
                apps = apps[1:]
                if not apps: continue
                line = k + "=" + ";".join(apps) + ";\n"
    out.append(line)
if not existed and all(not l.strip() or l.strip().startswith("[") for l in out): os.remove(p)
else: open(p, "w", encoding="utf-8").write("".join(out))'
defaults_keep() {
  if [[ -z $DEFAULTS_BEFORE || ! -s $DEFAULTS_BEFORE ]]; then
    ok "No file-type defaults to compare (no desktop here, or KEEP_DEFAULT_APPS=0)"; return 0
  fi
  local t before now list="$HOME/.config/mimeapps.list" existed=0 shown=()
  local -a pins=()
  while read -r t before; do
    now="$(gio_default "$t")"
    if [[ -n $now && $now != "$before" ]]; then pins+=("$t=$before"); shown+=("$t: ${before%.desktop} (not ${now%.desktop})"); fi
  done < "$DEFAULTS_BEFORE"
  if (( ! ${#pins[@]} )); then ok "No default app changed"; return 0; fi
  if [[ -e $list ]]; then existed=1; fi
  # recorded BEFORE the change, as one command with everything it needs
  record_undo "python3 -I -c $(printf %q "$UNPIN_PY") $(printf %q "$list") $existed $(printf '%q ' "${pins[@]}")"
  local pin
  for pin in "${pins[@]}"; do LC_ALL=C gio mime "${pin%%=*}" "${pin#*=}" >/dev/null 2>&1 || warn "Could not set back the default for ${pin%%=*}"; done
  ok "Kept your default app for ${#pins[@]} file type(s) a new package would have taken over:"
  printf '     %s\n' "${shown[@]:0:12}"
  if (( ${#shown[@]} > 12 )); then echo "     ... and $(( ${#shown[@]} - 12 )) more"; fi
}

run_steps() {
  defaults_snapshot
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
  if on "$INSTALL_NVIM";         then step "Neovim editor"             nvim_setup; fi
  if on "$INSTALL_KATE";         then step "Kate editor"               kate_setup; fi
  if on "$INSTALL_NICE_TO_HAVE"; then step "Extra terminal tools"      nice_to_have; fi
  step "Containers"                    containers
  step "Shell (bash) setup"            shell_setup
  if on "$INSTALL_OH_MY_BASH";   then step "Oh My Bash"                oh_my_bash; fi
  step "Git setup"                     git_setup
  step "Project templates"             project_templates
  if on "$SET_GNOME_FONT";        then step "Desktop settings"          desktop_tweaks; fi
  module_collect steps
  if on "$KEEP_DEFAULT_APPS";      then step "Keep default apps"                defaults_keep; fi
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
          (~/workstation-setup/workstation-undo-<time>.sh), verify downloads outside APT by SHA-256,
          and, once the caches are filled, leave nothing that contacts the internet by itself.
  Next:   './setup.sh --check' shows the same plan down to package names and
          versions; './setup.sh' runs it; './setup.sh --self-test' verifies it.

EOT
  show_opt_in
}

# --reset-shell: this setup is for bash. Someone who comes from zsh (often with Oh My Zsh) can
# switch over with one command. NOTHING is deleted: their zsh files are MOVED into
# ~/workstation-shell-backup-<time>/, the login shell goes back to bash, and a missing ~/.bashrc or
# ~/.profile is copied from /etc/skel. Every step is recorded for --undo. The zsh package stays
# installed (this setup never removes packages). It is an explicit one-off command, like --undo:
# it is not part of an install and --full does not turn it on.
ZSH_FILES=(.oh-my-zsh .zshrc .zshenv .zprofile .zlogin .zlogout .zsh_history .zshrc.pre-oh-my-zsh
           .p10k.zsh .zsh .zsh_sessions .zcompdump*)
reset_shell_mode() {
  local user="${USER:-$(id -un)}" skel="${RESET_SKEL_DIR:-/etc/skel}" old_shell backup f pat m n=0 answer
  local -a found=() skeleton=() lines=()
  if [[ "$(id -u)" == 0 ]]; then die "Run this as your normal user, not as root"; fi
  old_shell="$(getent passwd "$user" 2>/dev/null | cut -d: -f7 || true)"
  shopt -s nullglob
  for pat in "${ZSH_FILES[@]}"; do
    for m in "$HOME"/$pat; do if [[ -e $m || -L $m ]]; then found+=("$m"); fi; done
  done
  shopt -u nullglob
  for f in .bashrc .profile; do
    if [[ ! -e $HOME/$f && -r $skel/$f ]]; then skeleton+=("$f"); fi
  done
  backup="$HOME/workstation-shell-backup-$TIMESTAMP"

  section "Reset the shell: from zsh to bash"
  echo "Login shell of $user: ${old_shell:-unknown}"
  if (( ${#found[@]} )); then
    lines+=("move to $backup/ (nothing is deleted, symlinks are moved as links): $(printf '%s ' "${found[@]##*/}")")
  fi
  if [[ ${old_shell##*/} == zsh ]]; then lines+=("sudo usermod -s /bin/bash $user   (login shell; takes effect at your next login)"); fi
  for f in "${skeleton[@]}"; do lines+=("copy $skel/$f to ~/$f (it was missing; bash needs it)"); done
  if (( ! ${#lines[@]} )); then ok "Nothing to do: no zsh files in your home directory and your login shell is not zsh"; return 0; fi
  echo "These changes will be made:"
  for f in "${lines[@]}"; do n=$((n + 1)); printf '  %d. %s\n' "$n" "$f"; done
  echo
  echo "Not touched: the zsh package (this setup never removes packages; to remove it yourself:"
  echo "  sudo apt remove zsh   (other accounts that use zsh would lose their login shell)),"
  echo "terminal profiles that start /usr/bin/zsh explicitly, and ZDOTDIR=${ZDOTDIR:-(not set)}."
  echo
  if (( DRY_RUN )); then ok "Dry run: nothing was changed"; return 0; fi
  if (( ! ASSUME_YES )); then
    [[ -t 0 && -t 1 ]] || die "Not a terminal: add --yes to run without asking"
    read -rp "Make these changes? [y/N] " answer
    [[ $answer == [yY] ]] || { echo "Nothing was changed."; return 1; }
  fi

  init_undo_file
  record_undo "# mode: reset-shell (--reset-defaults never replays this file)"
  if (( ${#found[@]} )); then
    mkdir -p "$backup"
    record_undo "rmdir --ignore-fail-on-non-empty $(printf %q "$backup")"   # recorded first, so undone last
    for f in "${found[@]}"; do
      record_undo "mv -n $(printf %q "$backup/${f##*/}") $(printf %q "$f")"
      mv -- "$f" "$backup/"
      ok "Moved ~/${f##*/} to the backup folder"
    done
  fi
  for f in "${skeleton[@]}"; do
    record_undo "rm -f $(printf %q "$HOME/$f")"
    cp -- "$skel/$f" "$HOME/$f"
    ok "Restored ~/$f from $skel"
  done
  if [[ ${old_shell##*/} == zsh ]]; then
    sudo -v || die "sudo is needed to change the login shell"
    record_undo "sudo usermod -s $(printf %q "$old_shell") $user"
    if sudo usermod -s /bin/bash "$user"; then ok "Login shell is now /bin/bash (log out and in again; open terminals keep running zsh)"
    else warn "Could not change the login shell; do it yourself: sudo usermod -s /bin/bash $user"; fi
  fi
  echo
  ok "Done. Take it back any time with: ./setup.sh --undo $UNDO_FILE"
  echo "Next: ./setup.sh --profile work --check, then ./setup.sh --profile work   (--full for the shell loader too)."
  if (( ${#found[@]} )); then echo "Your zsh files are in $backup (delete that folder yourself when you are sure you do not need them)."; fi
}

# --reset-defaults: a COMPLETE reset to UBUNTU'S OWN DEFAULT, installing nothing (decided by the user: "a complete reset
# to ubuntu default only, meaning not setting up but rather just resetting", and, after a first version that kept the
# shell: "I clearly asked to reset EVERYTHING"). In this order:
#   1. every undo file of earlier runs is replayed (newest first): that precisely takes back what those runs recorded
#      (tools, app settings from their backups, Kate's plugin keys, default-app pins, groups, ...);
#   2. Ubuntu's system settings: what any version could change outside your files, also what the removed switches did
#      (older versions could switch off Ubuntu's crash reports, MOTD news, firmware refresh, APT news, the connectivity
#      probe and GNOME's privacy settings; the user decided the setup must never stop Ubuntu's telemetry or services);
#   3. the shell: ~/.bashrc, ~/.profile, ~/.bash_logout become Ubuntu's own copies from /etc/skel, the login shell bash;
#   4. everything the setup can put in your home folder that is still there is MOVED to a backup folder (nothing is
#      deleted), the Nerd Font last (a terminal using it turns into empty boxes).
# Only what differs from Ubuntu's default is listed; everything is shown first and asked for, and parts 2-4 are
# recorded for --undo. Installed APT packages stay (this setup never removes packages). Like --reset-shell and --undo
# it is an explicit one-off command: not part of an install, and --full never runs it.
#
# Units Ubuntu's packages ENABLE when they are installed ('deb-systemd-helper enable' in their postinst; read in
# the 24.04 and 26.04 archives: apport, whoopsie, kerneloops (24.04 only), base-files, fwupd). Not in the list:
# whoopsie.service (no [Install] section: whoopsie.path starts it) and apport.service (not shipped any more).
UNITS_UBUNTU=(apport-autoreport.path apport-autoreport.timer whoopsie.path kerneloops.service
              motd-news.timer fwupd-refresh.timer)
# GNOME settings any version of this setup could change; reset to the schema default (Ubuntu's own).
RESET_GSETTINGS=("org.gnome.desktop.interface monospace-font-name" "org.gnome.system.location enabled"
                 "org.gnome.desktop.datetime automatic-timezone" "org.gnome.desktop.privacy report-technical-problems"
                 "org.gnome.desktop.privacy send-software-usage-stats"
                 "org.gnome.desktop.search-providers disable-external" "org.gnome.DejaDup backend")
# Groups the setup can add you to that Ubuntu does not give a user. plugdev is not in it: Ubuntu puts the first
# user in plugdev itself.
RESET_GROUPS=(dialout wireshark docker)
NM_CONNECTIVITY_TEXT=$'[connectivity]\nenabled=false\n'
# Ubuntu's own copies of these come from /etc/skel; the reset puts them back.
RESET_SKEL_FILES=(.bashrc .profile .bash_logout)
# What the setup (any version) can put in your home folder, relative to ~. Fresh Ubuntu has none of it, so the complete
# reset moves what is still there into the backup folder. The Nerd Font is handled separately, last.
RESET_HOME_PATHS=(.bashrc.d .inputrc .config/starship.toml .local/share/oh-my-bash .gdbinit .npmrc
  .config/helix .config/nvim .config/lazygit .config/tealdeer .config/uv .config/containers/containers.conf
  .config/kate/lspclient/settings.json .config/kate/formatting/settings.json .config/keepassxc/keepassxc.ini
  .config/vlc/vlcrc .config/workstation .local/share/workstation .local/share/uv .local/lib/node_modules
  .cargo .rustup WORKSTATION-CHEATSHEET.md workstation-manifest-latest.txt .local/share/containers
  .npm .cache/uv .cache/pip .cache/pre-commit .cache/ccache .cache/tealdeer .cache/helix .cache/starship)
# Commands the setup puts in ~/.local/bin (links into ~/.local/opt, ~/.local/share/uv or the npm prefix are found too).
RESET_LOCAL_BIN=(ws-init ws-doctor ws-devname ws-pyformat uv uvx hx nvim starship lazygit node npm npx corepack
                 probe-rs cargo-flash cargo-embed)
RESET_FONT_DIR=.local/share/fonts/JetBrainsMonoNerdFont
# The settings folders of apps whose package the reset removes (package|paths below ~).
RESET_APP_PATHS=("kate|.config/katerc .config/kate .local/share/kate .config/katevirc .config/kateschemarc .config/katemetainfos"
                 "gimp|.config/GIMP" "vlc|.config/vlc .local/share/vlc" "keepassxc|.config/keepassxc .cache/keepassxc"
                 "inkscape|.config/inkscape" "wireshark-common|.config/wireshark")
# The packages this setup installed (decided by the user: the complete reset removes them too, "safely"): read from apt's
# OWN history, the entries whose command line carries the setup's --no-remove --no-upgrade (its apt_install, its preflight,
# and the README manual). Prints "name auto|manual" for every package those entries installed. A package that was already
# on the machine never appears in an Install: line, so it is never listed.
APT_SETUP_PKGS_PY='
import gzip, os, re, sys
d = sys.argv[1]
seen = {}
for name in sorted(os.listdir(d)):
    if not name.startswith("history.log"):
        continue
    path = os.path.join(d, name)
    try:
        raw = (gzip.open if name.endswith(".gz") else open)(path, "rt", errors="replace").read()
    except OSError:
        continue
    for rec in raw.split("\n\n"):
        cmd = next((l for l in rec.splitlines() if l.startswith("Commandline:")), "")
        if "--no-remove" not in cmd or "--no-upgrade" not in cmd or " install" not in cmd:
            continue
        for l in rec.splitlines():
            if l.startswith("Install:"):
                for pkg, inside in re.findall(r"([^\s,]+) \(([^)]*)\)", l[len("Install:"):]):
                    seen[pkg] = "auto" if "automatic" in inside else seen.get(pkg, "manual")
for pkg, kind in seen.items():
    print(pkg, kind)
'

# Fill rd_pkgs (still installed) and rd_autos (of those, marked automatic) from apt's history; then simulate the purge:
# when it would take ANY package outside that list with it (Ubuntu's own meta packages, something you installed later),
# nothing is removed and a note says what would go.
_rd_packages() {
  local line name kind arch native set_list sim extra i
  local -a names=() kinds=() inst=()
  rd_pkgs=(); rd_autos=()
  have dpkg-query || return 0
  native="$(dpkg --print-architecture 2>/dev/null || echo amd64)"
  while read -r name kind; do
    [[ -n $name ]] || continue
    arch="${name##*:}"; if [[ $name == *:* && ( $arch == "$native" || $arch == all ) ]]; then name="${name%:*}"; fi
    names+=("$name"); kinds+=("$kind")
  done < <(python3 -I -c "$APT_SETUP_PKGS_PY" "${RESET_APT_HISTORY_DIR:-/var/log/apt}" 2>/dev/null || true)
  (( ${#names[@]} )) || return 0
  # dpkg-query names Multi-Arch: same packages (most libraries) WITH their architecture (libc6:amd64): compare without it
  # (found by the E2E: every library fell out of the list, and the simulation then refused the removal)
  mapfile -t inst < <(dpkg-query -W -f='${binary:Package} ${db:Status-Abbrev}\n' "${names[@]}" 2>/dev/null \
                      | awk -v a=":$native" '$2 == "ii" { n = $1; sub(a "$", "", n); sub(/:all$/, "", n); print n }' || true)
  set_list=" ${inst[*]} "
  for (( i = 0; i < ${#names[@]}; i++ )); do
    if [[ $set_list == *" ${names[i]} "* ]]; then rd_pkgs+=("${names[i]}"); if [[ ${kinds[i]} == auto ]]; then rd_autos+=("${names[i]}"); fi; fi
  done
  (( ${#rd_pkgs[@]} )) || return 0
  # Ubuntu's base system stays, even where the setup installed it (a container has no systemd until the install pulls
  # it in; found by the E2E, where apt refused to remove the essential systemd-sysv): Essential, Protected, priority
  # required/important, and everything those need (apt-cache depends --recurse over installed packages).
  local -a base=() need=() keep_set=()
  mapfile -t base < <(dpkg-query -W -f='${binary:Package}|${Essential}|${Protected}|${Priority}\n' "${rd_pkgs[@]}" 2>/dev/null \
                      | awk -F'|' -v a=":$native" '$2 == "yes" || $3 == "yes" || $4 == "required" || $4 == "important" { n = $1; sub(a "$", "", n); sub(/:all$/, "", n); print n }' || true)
  if (( ${#base[@]} )); then
    mapfile -t need < <(apt-cache depends --recurse --installed --no-recommends --no-suggests --no-conflicts --no-breaks \
                          --no-replaces --no-enhances "${base[@]}" 2>/dev/null | awk -v a=":$native" '!/^ / && !/^</ { n = $1; sub(a "$", "", n); sub(/:all$/, "", n); print n }' || true)
    set_list=" ${base[*]} ${need[*]} "
    for name in "${rd_pkgs[@]}"; do if [[ $set_list != *" $name "* ]]; then keep_set+=("$name"); fi; done
    notes+=("Packages: $(( ${#rd_pkgs[@]} - ${#keep_set[@]} )) of the ${#rd_pkgs[@]} the setup installed stay, because Ubuntu's base system needs them ($(printf '%s ' "${base[@]:0:6}")...)")
    set_list=" ${keep_set[*]} "
    local -a autos2=()
    for name in "${rd_autos[@]}"; do if [[ $set_list == *" $name "* ]]; then autos2+=("$name"); fi; done
    rd_pkgs=("${keep_set[@]}"); rd_autos=("${autos2[@]}")
    (( ${#rd_pkgs[@]} )) || return 0
  fi
  set_list=" ${rd_pkgs[*]} "
  sim="$(apt-get -s purge "${rd_pkgs[@]}" 2>&1 || true)"
  extra="$(awk '$1 == "Purg" || $1 == "Remv" { print $2 }' <<<"$sim" | while read -r name; do
             [[ $set_list == *" ${name%:*} "* || $set_list == *" $name "* ]] || echo "$name"; done | sort -u | paste -sd' ' || true)"
  if [[ -n $extra ]]; then
    notes+=("Packages: removing the ${#rd_pkgs[@]} the setup installed would ALSO remove: $extra (not installed by the setup). Nothing is removed; remove those yourself first if you really want to")
    rd_pkgs=(); rd_autos=()
  elif ! grep -qE '^(Purg|Remv) ' <<<"$sim"; then
    notes+=("Packages: apt could not simulate removing the ${#rd_pkgs[@]} the setup installed; nothing is removed: $(grep -m1 '^E:' <<<"$sim" || echo 'see apt-get -s purge')")
    rd_pkgs=(); rd_autos=()
  fi
}

# Switches that older versions had: say once that they are gone instead of silently ignoring them.
removed_switches_note() {
  local v
  for v in DISABLE_REPORTING_SERVICES DISABLE_MOTD_NEWS DISABLE_FWUPD_REFRESH DISABLE_APT_NEWS \
           DISABLE_NM_CONNECTIVITY_CHECK SET_GNOME_PRIVACY; do
    if [[ ${!v:-} == 1 ]]; then
      warn "$v no longer exists and is ignored: this setup leaves Ubuntu's own services and privacy settings as Ubuntu ships them. To turn back what an older version switched off: ./setup.sh --reset-defaults"
    fi
  done
}

# True when FILE exists and holds exactly TEXT (the setup's own content, so it is ours to remove).
file_has_text() { [[ -f $1 ]] && cmp -s "$1" <(printf '%s' "$2"); }
# True when FILE (REL below /etc) still holds exactly what this setup wrote there.
etc_is_ours() {
  case "$1" in
    NetworkManager/*) file_has_text "$2" "$NM_CONNECTIVITY_TEXT" ;;
    sysctl.d/*)       file_has_text "$2" "$INOTIFY_CONF_TEXT" ;;
    firefox/*)        cmp -s "$2" "$SCRIPT_DIR/modules/desktop/files/system/firefox-policies.json" ;;
    thunderbird/*)    cmp -s "$2" "$SCRIPT_DIR/modules/desktop/files/system/thunderbird-policies.json" ;;
    *)                return 1 ;;
  esac
}

# Collect what differs from Ubuntu's default into the caller's arrays text/act/notes (and need_sudo).
_rd_collect() {
  local u state v s k cur def g mygroups kv f rel n_own
  local -a keys=()
  text=(); act=(); notes=(); need_sudo=0
  # 1. Ubuntu's services
  if have systemctl; then
    for u in "${UNITS_UBUNTU[@]}"; do
      state="$(systemctl is-enabled "$u" 2>/dev/null || true)"
      case "$state" in
        disabled) _rd_add "switch $u on again (Ubuntu enables it; it is disabled now)" "unit|$u" ;;
        masked)   notes+=("$u is MASKED (this setup never masks): 'sudo systemctl unmask $u' if you want Ubuntu's default") ;;
      esac
    done
  fi
  # 2. APT news (Ubuntu's default: on)
  if have pro; then
    v="$(pro config show apt_news 2>/dev/null | awk '$1 == "apt_news" { print $2 }' || true)"
    if [[ $v == False ]]; then _rd_add "APT news on again ('pro config set apt_news=true'; Ubuntu's default)" aptnews; fi
  fi
  # 3. Files below /etc that this setup wrote (removed only when they still hold exactly the setup's content)
  for kv in "NetworkManager/conf.d/99-no-connectivity-check.conf|NetworkManager's connectivity probe on again" \
            "sysctl.d/60-dev-inotify.conf|Ubuntu's inotify limits, from the next boot" \
            "firefox/policies/policies.json|Firefox without the setup's policy file" \
            "thunderbird/policies/policies.json|Thunderbird without the setup's policy file"; do
    f="$etc/${kv%%|*}"
    [[ -e $f ]] || continue
    if etc_is_ours "${kv%%|*}" "$f"; then _rd_add "remove $f (${kv#*|})" "etc|$f"
    else notes+=("$f exists but is not the setup's file (or was changed): left alone"); fi
  done
  # 4. Wireshark capture for non-root users (Ubuntu's default: off)
  if dpkg -s wireshark-common >/dev/null 2>&1; then
    v="$(debconf-show wireshark-common 2>/dev/null | awk -F': ' '/install-setuid/ { print $2 }' || true)"
    if [[ $v == true ]]; then _rd_add "Wireshark: capture needs root again (debconf answer 'no' + dpkg-reconfigure; Ubuntu's default)" wireshark; fi
  fi
  # 5. Groups
  mygroups=" $(id -nG "$user" 2>/dev/null || true) "
  for g in "${RESET_GROUPS[@]}"; do
    if [[ $mygroups == *" $g "* ]]; then _rd_add "leave group '$g' (Ubuntu does not add users to it; you may have joined it yourself: then answer no)" "group|$g"; fi
  done
  # 6. GNOME settings (reading needs no desktop session, writing does)
  if have gsettings; then
    for s in "${RESET_GSETTINGS[@]}"; do
      read -r s k <<<"$s"
      mapfile -t keys < <(gsettings list-keys "$s" 2>/dev/null || true)
      [[ " ${keys[*]} " == *" $k "* ]] || continue
      cur="$(gsettings get "$s" "$k" 2>/dev/null || true)"
      def="$(GSETTINGS_BACKEND=memory gsettings get "$s" "$k" 2>/dev/null || true)"
      if [[ -n $def && $cur != "$def" ]]; then _rd_add "GNOME $s $k: $cur -> $def (Ubuntu's default)" "gnome|$s|$k|$cur"; fi
    done
  fi
  # 7. Global git defaults this setup sets (only where the value is still exactly the setup's)
  if have git; then
    for kv in "${GIT_DEFAULTS[@]}" "${GIT_DEFAULTS_DELTA[@]}"; do
      cur="$(git config --global --get "${kv%%=*}" 2>/dev/null || true)"
      if [[ $cur == "${kv#*=}" ]]; then _rd_add "git: remove global ${kv%%=*} = ${kv#*=}" "git|${kv%%=*}|${kv#*=}"; fi
    done
    if have git-lfs && [[ "$(git config --global --get filter.lfs.process 2>/dev/null || true)" == "git-lfs filter-process" ]]; then
      _rd_add "git: remove the global Git LFS filter ('git lfs uninstall --skip-repo')" gitlfs
    fi
  fi
  # 8. The block in ~/.bashrc that loads ~/.bashrc.d (only without an /etc/skel/.bashrc; otherwise the shell part below
  #    replaces the whole file with Ubuntu's own)
  if [[ ! -r $skel/.bashrc ]] && grep -qF '# >>> workstation-setup' "$HOME/.bashrc" 2>/dev/null; then
    _rd_add "remove the setup's block from ~/.bashrc (new terminals stop loading ~/.bashrc.d: no aliases, prompt or PATH additions from it; a backup is kept)" bashrc
  fi

  # 9. The shell: Ubuntu's own ~/.bashrc, ~/.profile, ~/.bash_logout (from /etc/skel), and bash as the login shell
  for f in "${RESET_SKEL_FILES[@]}"; do
    [[ -r $skel/$f ]] || continue
    if [[ ! -e $HOME/$f ]]; then _rd_add "~/$f: put back Ubuntu's own copy from $skel (it is missing)" "skel|$f"
    elif ! cmp -s "$HOME/$f" "$skel/$f"; then
      n_own="$(diff "$skel/$f" "$HOME/$f" 2>/dev/null | grep -c '^>' || true)"
      _rd_add "~/$f: replace with Ubuntu's own copy from $skel (yours, with $n_own line(s) Ubuntu's has not, goes to the backup)" "skel|$f"
    fi
  done
  cur="$(getent passwd "$user" 2>/dev/null | cut -d: -f7 || true)"
  if [[ -n $cur && $cur != /bin/bash && $cur != /usr/bin/bash ]]; then
    _rd_add "login shell: $cur -> /bin/bash (Ubuntu's default; from your next login; the $cur package stays installed)" "login|$cur"
  fi
  # 10. Everything the setup can put in your home folder: moved to the backup folder, nothing is deleted
  for rel in "${RESET_HOME_PATHS[@]}"; do
    if [[ -e $HOME/$rel || -L $HOME/$rel ]]; then _rd_add "move ~/$rel to the backup folder (fresh Ubuntu has none)" "move|$rel"; fi
  done
  shopt -s nullglob
  # record files that earlier versions left loose in ~ (and old undo files, renamed by a replay)
  for f in "$HOME"/workstation-setup-*.log "$HOME"/workstation-manifest-*.txt "$HOME"/workstation-undo-*.sh*; do
    _rd_add "move ~/${f#"$HOME"/} to the backup folder (a record file an earlier version left in ~)" "move|${f#"$HOME"/}"
  done
  for f in "$HOME"/.local/opt/node-* "$HOME"/.local/opt/helix-* "$HOME"/.local/opt/nvim-*; do
    _rd_add "move ~/${f#"$HOME"/} to the backup folder" "move|${f#"$HOME"/}"
  done
  for f in "$HOME"/.local/bin/*; do
    [[ -e $f || -L $f ]] || continue
    k="$(readlink "$f" 2>/dev/null || true)"
    if [[ " ${RESET_LOCAL_BIN[*]} " == *" ${f##*/} "* || $k == *.local/opt/* || $k == ../opt/* || $k == *.local/share/uv/* \
          || $k == *lib/node_modules/* || $k == *.cargo/* ]]; then
      _rd_add "move ~/${f#"$HOME"/} to the backup folder (put there by the setup)" "move|${f#"$HOME"/}"
    fi
  done
  shopt -u nullglob
  # 11. The Ubuntu packages the setup installed (from apt's history, simulated first), and the settings of their apps
  _rd_packages
  if (( ${#rd_pkgs[@]} )); then
    _rd_add "remove the ${#rd_pkgs[@]} Ubuntu package(s) the setup installed (purge; read from apt's history; simulated: nothing else goes; listed below)" packages
    for kv in "${RESET_APP_PATHS[@]}"; do
      [[ " ${rd_pkgs[*]} " == *" ${kv%%|*} "* ]] || continue
      for rel in ${kv#*|}; do
        if [[ -e $HOME/$rel ]]; then _rd_add "move ~/$rel to the backup folder (settings of ${kv%%|*}, which is removed)" "move|$rel"; fi
      done
    done
  fi
  # 12. The Nerd Font, LAST: a terminal that uses it shows empty boxes once it is gone
  if [[ -d $HOME/$RESET_FONT_DIR ]]; then
    _rd_add "move the JetBrains Mono Nerd Font (~/$RESET_FONT_DIR) to the backup folder, LAST: a terminal using it shows empty boxes until you open a new one" font
  fi
}

reset_defaults_mode() {
  local user="${USER:-$(id -un)}" etc="${RESET_ETC_DIR:-/etc}" skel="${RESET_SKEL_DIR:-/etc/skel}" n=0 answer v f line
  local backup="$OUT_DIR/reset-backup-$TIMESTAMP" need_sudo=0 done_n=0 n_skip=0 replay_sudo=0
  local -a text=() act=() notes=() undo_files=() replay=() rd_pkgs=() rd_autos=()
  if [[ "$(id -u)" == 0 ]]; then die "Run this as your normal user, not as root"; fi
  _rd_add() { text+=("$1"); act+=("$2"); case "$2" in unit\|*|aptnews|etc\|*|wireshark|group\|*|login\|*|packages) need_sudo=1 ;; esac; }

  # 1. The undo files of earlier runs (the records folder and ~, where earlier versions left them), newest first.
  #    The Nerd Font lines are left out: the sweep below moves the font, last.
  mapfile -t undo_files < <(find "$OUT_DIR" "$HOME" -maxdepth 1 -name 'workstation-undo-*.sh' -printf '%T@ %p\n' 2>/dev/null | sort -nr | cut -d' ' -f2- || true)
  # Undo files of the reset modes themselves (this one and --reset-shell) take back a RESET, not an install: never replayed.
  local -a installs=()
  for f in "${undo_files[@]}"; do
    if ! grep -q '^# mode: reset-' "$f" 2>/dev/null; then installs+=("$f"); fi
  done
  undo_files=("${installs[@]}")
  for f in "${undo_files[@]}"; do
    local -a lines=()
    while IFS= read -r line; do
      case $line in ''|'#'*|'set -x') continue ;; esac
      [[ $line == *fonts/JetBrainsMonoNerdFont* ]] && continue
      lines+=("$line")
    done < "$f"
    for (( n = ${#lines[@]} - 1; n >= 0; n-- )); do replay+=("${lines[n]}"); done
  done
  if printf '%s\n' "${replay[@]}" | grep -q 'sudo '; then replay_sudo=1; fi
  _rd_collect

  section "Reset to Ubuntu's defaults (complete; nothing is installed)"
  if (( ${#replay[@]} )); then
    echo "First, the undo files of earlier runs are replayed, newest first (${#replay[@]} commands; see them with --undo FILE --dry-run):"
    printf '     %s\n' "${undo_files[@]}"
    echo "   They take back what those runs recorded (tools, app settings from their backups, plugin keys, ...). This part"
    echo "   cannot itself be undone; ./setup.sh installs it all again."
    echo
  fi
  n=0
  if (( ${#text[@]} )); then
    echo "Then these differ from Ubuntu's default and are put back (anything the replay already fixed is skipped):"
    for v in "${text[@]}"; do n=$((n + 1)); printf '  %d. %s\n' "$n" "$v"; done
    if (( ${#rd_pkgs[@]} )); then
      echo; echo "  The packages (installed by the setup's earlier runs; reinstalled by --undo):"
      printf '%s\n' "${rd_pkgs[*]}" | fold -s -w 104 | sed 's/^/    /'
    fi
  elif (( ! ${#replay[@]} )); then
    ok "Nothing to do: everything this setup can change is at Ubuntu's default"
  fi
  for v in "${notes[@]}"; do warn "$v"; done
  echo
  echo "Nothing is deleted: files and folders are MOVED to $backup, and ./setup.sh --undo puts them back."
  echo "Packages: only those apt's history shows the setup installed are removed (anything that was already on the"
  echo "machine, and Ubuntu's own packages, stay). Your zsh backup folders and $OUT_DIR stay."
  echo
  (( ${#text[@]} + ${#replay[@]} )) || return 0
  if (( DRY_RUN )); then ok "Dry run: nothing was changed"; return 0; fi
  if (( ! ASSUME_YES )); then
    [[ -t 0 && -t 1 ]] || die "Not a terminal: add --yes to run without asking"
    read -rp "Reset everything listed to Ubuntu's default? [y/N] " answer
    [[ $answer == [yY] ]] || { echo "Nothing was changed."; return 1; }
  fi
  if (( need_sudo || replay_sudo )); then sudo -v || die "sudo is needed for the system settings"; fi

  if (( ${#replay[@]} )); then
    section "Replaying the undo files of earlier runs"
    local failed=0
    for (( n = 0; n < ${#replay[@]}; n++ )); do
      printf '%s[%d/%d]%s %s\n' "$c_blue" "$((n + 1))" "${#replay[@]}" "$c_off" "${replay[n]}"
      if ! PATH="$HOME/.local/bin:$HOME/.cargo/bin:$PATH" bash -c "${replay[n]}" </dev/null; then failed=$((failed + 1)); fi
    done
    # A command that fails here usually takes back something already gone (an earlier --undo); the sweep catches the rest.
    if (( failed )); then log "$failed of ${#replay[@]} replayed command(s) failed (mostly: already undone); the next part catches what is left"; fi
    for f in "${undo_files[@]}"; do mv -- "$f" "$f.done-reset-$TIMESTAMP"; done
    _rd_collect      # the state has changed: put back only what still differs
  fi

  section "Putting back Ubuntu's defaults"
  init_undo_file
  record_undo "# mode: reset-defaults (a later --reset-defaults never replays this file)"
  local a rest x
  for (( x = 0; x < ${#act[@]}; x++ )); do
    a="${act[x]}"; rest="${a#*|}"
    case "$a" in
      unit\|*)
        record_undo "sudo systemctl disable $rest"
        if sudo systemctl enable "$rest" >/dev/null 2>&1; then
          sudo systemctl start "$rest" >/dev/null 2>&1 || true   # best effort (no running systemd in a container)
          ok "Switched $rest on again"; done_n=$((done_n + 1))
        else warn "Could not enable $rest"; n_skip=$((n_skip + 1)); fi ;;
      aptnews)
        record_undo "sudo pro config set apt_news=false"
        if sudo pro config set apt_news=true >/dev/null 2>&1; then ok "APT news on again"; done_n=$((done_n + 1))
        else warn "Could not switch APT news on"; n_skip=$((n_skip + 1)); fi ;;
      etc\|*)
        mkdir -p "$backup"; cp -p -- "$rest" "$backup/${rest//\//_}"
        record_undo "sudo install -D -m 644 $(printf %q "$backup/${rest//\//_}") $(printf %q "$rest")"
        if sudo rm -f -- "$rest"; then
          # only the policies folders were created by the setup; conf.d and sysctl.d belong to their packages
          if [[ $rest == */policies/policies.json ]]; then sudo rmdir --ignore-fail-on-non-empty -- "$(dirname "$rest")" 2>/dev/null || true; fi
          if [[ $rest == */NetworkManager/* ]]; then sudo systemctl reload NetworkManager >/dev/null 2>&1 || true; fi
          ok "Removed $rest"; done_n=$((done_n + 1))
        else warn "Could not remove $rest"; n_skip=$((n_skip + 1)); fi ;;
      wireshark)
        record_undo "echo 'wireshark-common wireshark-common/install-setuid boolean true' | sudo debconf-set-selections && sudo env DEBIAN_FRONTEND=noninteractive dpkg-reconfigure -f noninteractive wireshark-common"
        if echo 'wireshark-common wireshark-common/install-setuid boolean false' | sudo debconf-set-selections \
           && sudo env DEBIAN_FRONTEND=noninteractive dpkg-reconfigure -f noninteractive wireshark-common >/dev/null 2>&1; then
          ok "Wireshark capture needs root again"; done_n=$((done_n + 1))
        else warn "Could not reconfigure wireshark-common"; n_skip=$((n_skip + 1)); fi ;;
      group\|*)
        record_undo "sudo usermod -aG $rest $(printf %q "$user")"
        if sudo gpasswd -d "$user" "$rest" >/dev/null 2>&1; then ok "Left group '$rest' (takes effect at your next login)"; done_n=$((done_n + 1))
        else warn "Could not leave group '$rest'"; n_skip=$((n_skip + 1)); fi ;;
      gnome\|*)
        IFS='|' read -r s k cur <<<"$rest"
        if ! have_desktop_session; then warn "GNOME $s $k: needs your desktop session (run this from a terminal on your desktop)"; n_skip=$((n_skip + 1)); continue; fi
        record_undo "gsettings set $s $k $(printf %q "$cur")"
        if gsettings reset "$s" "$k"; then ok "GNOME $s $k is Ubuntu's default again"; done_n=$((done_n + 1))
        else warn "Could not reset $s $k"; n_skip=$((n_skip + 1)); fi ;;
      git\|*)
        record_undo "git config --global $(printf %q "${rest%%|*}") $(printf %q "${rest#*|}")"
        if git config --global --unset "${rest%%|*}"; then ok "git: removed global ${rest%%|*}"; done_n=$((done_n + 1))
        else warn "Could not remove git ${rest%%|*}"; n_skip=$((n_skip + 1)); fi ;;
      gitlfs)
        record_undo "git lfs install --skip-repo"
        if git lfs uninstall --skip-repo >/dev/null 2>&1; then ok "git: removed the global Git LFS filter"; done_n=$((done_n + 1))
        else warn "Could not remove the Git LFS filter"; n_skip=$((n_skip + 1)); fi ;;
      bashrc)
        mkdir -p "$backup"; cp -p -- "$HOME/.bashrc" "$backup/bashrc"
        record_undo "cp -p $(printf %q "$backup/bashrc") ~/.bashrc"
        if sed -i '/# >>> workstation-setup/,/# <<< workstation-setup <<</d' "$HOME/.bashrc"; then
          ok "Removed the setup's block from ~/.bashrc (new terminals)"; done_n=$((done_n + 1))
        else warn "Could not edit ~/.bashrc"; n_skip=$((n_skip + 1)); fi ;;
      skel\|*)
        if [[ -e $HOME/$rest ]]; then
          mkdir -p "$backup/home"; cp -p -- "$HOME/$rest" "$backup/home/$rest"
          record_undo "cp -p $(printf %q "$backup/home/$rest") ~/$rest"
        else
          record_undo "rm -f ~/$rest"
        fi
        if cp -- "$skel/$rest" "$HOME/$rest"; then ok "~/$rest is Ubuntu's own copy again"; done_n=$((done_n + 1))
        else warn "Could not copy $skel/$rest"; n_skip=$((n_skip + 1)); fi ;;
      login\|*)
        record_undo "sudo usermod -s $(printf %q "$rest") $(printf %q "$user")"
        if sudo usermod -s /bin/bash "$user" >/dev/null 2>&1; then ok "Login shell is /bin/bash again (from your next login)"; done_n=$((done_n + 1))
        else warn "Could not change the login shell"; n_skip=$((n_skip + 1)); fi ;;
      move\|*)
        [[ -e $HOME/$rest || -L $HOME/$rest ]] || continue          # the replay already took it back
        mkdir -p "$(dirname "$backup/home/$rest")"
        record_undo "mkdir -p $(printf %q "$(dirname "$HOME/$rest")") && mv -n $(printf %q "$backup/home/$rest") $(printf %q "$HOME/$rest")"
        if mv -- "$HOME/$rest" "$backup/home/$rest"; then ok "Moved ~/$rest to the backup folder"; done_n=$((done_n + 1))
        else warn "Could not move ~/$rest"; n_skip=$((n_skip + 1)); fi ;;
      packages)
        (( ${#rd_pkgs[@]} )) || continue
        # an undo line runs in a plain shell (no apt_run there): apt's own retries/timeouts and a dpkg lock wait instead
        record_undo "sudo env DEBIAN_FRONTEND=noninteractive apt-get ${APT_NET[*]} -o DPkg::Lock::Timeout=300 install -y --no-remove --no-upgrade ${rd_pkgs[*]}${rd_autos[*]:+ && sudo apt-mark auto ${rd_autos[*]} >/dev/null}"
        log "Removing ${#rd_pkgs[@]} package(s) (this takes a while)"
        if apt_run purge -y "${rd_pkgs[@]}"; then ok "Removed the ${#rd_pkgs[@]} package(s) the setup installed"; done_n=$((done_n + 1))
        else warn "Removing the packages failed (see apt's message above)"; n_skip=$((n_skip + 1)); fi ;;
      font)
        [[ -d $HOME/$RESET_FONT_DIR ]] || continue
        echo; warn "Moving the Nerd Font now: if this window turns into empty boxes, close it and open a new one."
        mkdir -p "$backup/home/.local/share/fonts"
        record_undo "mkdir -p ~/.local/share/fonts && mv -n $(printf %q "$backup/home/$RESET_FONT_DIR") ~/$RESET_FONT_DIR && fc-cache -f >/dev/null 2>&1"
        if mv -- "$HOME/$RESET_FONT_DIR" "$backup/home/$RESET_FONT_DIR"; then
          fc-cache -f >/dev/null 2>&1 || true
          ok "Moved the Nerd Font to the backup folder"; done_n=$((done_n + 1))
        else warn "Could not move the Nerd Font"; n_skip=$((n_skip + 1)); fi ;;
    esac
  done
  echo
  if (( n_skip )); then warn "$n_skip change(s) could not be made (see above)"; fi
  ok "Done: $done_n change(s) back to Ubuntu's default. Open a NEW terminal to see the plain Ubuntu shell."
  echo "Your files are in $backup. Take the reset back (except the replayed undo files) with: ./setup.sh --undo $UNDO_FILE"
}

# --undo: replay an undo file newest-first. The commands are the ones this setup
# recorded itself (see record_undo); all of them are shown before anything runs.
undo_mode() {
  local file="${UNDO_ARG:-}" line i n=0 failed=0 answer
  local -a cmds=() failures=()
  if [[ -z $file ]]; then
    # the records folder first; ~ too, where earlier versions of this setup left them
    file="$(find "$OUT_DIR" "$HOME" -maxdepth 1 -name 'workstation-undo-*.sh' -printf '%T@ %p\n' 2>/dev/null | sort -nr | head -n1 | cut -d' ' -f2- || true)"
  fi
  [[ -n $file && -f $file ]] || die "No undo file found (looked for $OUT_DIR/workstation-undo-*.sh). Give one: ./setup.sh --undo FILE"
  while IFS= read -r line; do
    case $line in ''|'#'*|'set -x') continue ;; esac
    cmds+=("$line")
  done < "$file"
  (( ${#cmds[@]} )) || { ok "$file records no changes: nothing to undo"; return 0; }

  # Newest first. The command that removes the Nerd Font runs LAST: a terminal that is using that font draws every
  # character as an empty box the moment the file is gone, even the text already on screen (found on the user's
  # machine), so everything else, and the summary, is printed while the terminal can still be read.
  local -a plan=() font_plan=()
  for (( i = ${#cmds[@]} - 1; i >= 0; i-- )); do
    if [[ ${cmds[i]} == *fonts/JetBrainsMonoNerdFont* ]]; then font_plan+=("${cmds[i]}"); else plan+=("${cmds[i]}"); fi
  done
  plan+=("${font_plan[@]}")

  section "Undo: $file"
  echo "These ${#plan[@]} commands will run, newest first. Installed APT packages are NOT removed"
  echo "(see 'Undo' in the README for apt history)."
  echo
  for (( i = 0; i < ${#plan[@]}; i++ )); do printf '  %2d. %s\n' "$((i + 1))" "${plan[i]}"; done
  echo
  if (( ${#font_plan[@]} )); then
    warn "The last command removes the JetBrains Mono Nerd Font. A terminal that is using it will then show EMPTY BOXES"
    warn "instead of letters (even the text already on screen). Nothing is broken: close that terminal window and open a"
    warn "new one. If the boxes remain, pick another font in its preferences (Terminator: right-click > Preferences >"
    warn "Profiles > Font; GNOME Terminal: Preferences > your profile > Text)."
    # A terminal profile that names the font itself (the setup never edits terminal profiles, so the undo cannot change
    # it back) keeps asking for the removed font and shows spaced-out or boxed letters: say which one, and how to go back.
    local tcfg="$HOME/.config/terminator/config" named=""
    if [[ -f $tcfg ]]; then named="$(grep -iE '^[[:space:]]*font[[:space:]]*=.*nerd' "$tcfg" | head -n1 | sed 's/^[[:space:]]*//' || true)"; fi
    if [[ -n $named ]]; then
      warn "Your Terminator profile names this font itself ($named). After the undo, go back to Ubuntu's default:"
      warn "right-click > Preferences > Profiles > General > tick 'Use the system fixed width font'."
    fi
    if have dconf; then
      named="$(dconf dump /org/gnome/terminal/legacy/profiles:/ 2>/dev/null | grep -iE '^font=.*nerd' | head -n1 || true)"
      if [[ -n $named ]]; then
        warn "A GNOME Terminal profile names this font itself ($named). After the undo: Preferences > that profile > Text >"
        warn "untick 'Custom font' to use the system font again."
      fi
    fi
    echo
  fi
  if (( DRY_RUN )); then ok "Dry run: nothing was changed"; return 0; fi
  if (( ! ASSUME_YES )); then
    [[ -t 0 && -t 1 ]] || die "Not a terminal: add --yes to run without asking"
    read -rp "Run these commands? [y/N] " answer
    [[ $answer == [yY] ]] || { echo "Nothing was changed."; return 1; }
  fi
  if printf '%s\n' "${cmds[@]}" | grep -q 'sudo '; then sudo -v || die "sudo is needed for some of these commands"; fi
  n=0
  for (( i = 0; i < ${#plan[@]}; i++ )); do
    n=$((n + 1))
    if (( ${#font_plan[@]} && i == ${#plan[@]} - ${#font_plan[@]} )); then
      echo; warn "Removing the Nerd Font now: if this window turns into empty boxes, close it and open a new one."
    fi
    printf '%s[%d/%d]%s %s\n' "$c_blue" "$n" "${#plan[@]}" "$c_off" "${plan[i]}"
    # tools we installed live in ~/.local/bin and ~/.cargo/bin, which a plain shell may not have on PATH
    if ! PATH="$HOME/.local/bin:$HOME/.cargo/bin:$PATH" bash -c "${plan[i]}"; then failed=$((failed + 1)); failures+=("${plan[i]}"); warn "That command failed; continuing"; fi
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

# Earlier versions left the records (undo scripts, manifests, logs) and the cheat sheet loose in your home
# directory. Move them into OUT_DIR (never overwriting anything there). Your existing ~/.bashrc.d/10-workstation.sh is
# never edited, and its old ws-help still looks for ~/WORKSTATION-CHEATSHEET.md, so a link is left there in that case.
migrate_records() {
  local f dest moved=0 old="$HOME/WORKSTATION-CHEATSHEET.md"
  if [[ $OUT_DIR == "$HOME" ]]; then return 0; fi
  mkdir -p "$OUT_DIR"
  for f in "$HOME"/workstation-undo-*.sh "$HOME"/workstation-undo-*.sh.done-* "$HOME"/workstation-manifest-2*.txt "$HOME"/workstation-setup-*.log; do
    if [[ ! -f $f || -L $f ]]; then continue; fi
    dest="$OUT_DIR/${f##*/}"
    if [[ -e $dest ]]; then continue; fi
    if mv "$f" "$dest"; then moved=$((moved + 1)); fi
  done
  if [[ -L $HOME/workstation-manifest-latest.txt ]]; then rm -f "$HOME/workstation-manifest-latest.txt"; fi   # recreated in OUT_DIR
  if [[ -f $old && ! -L $old && ! -e $CHEATSHEET_FILE ]]; then
    if mv "$old" "$CHEATSHEET_FILE"; then moved=$((moved + 1)); fi
  fi
  if (( moved )); then ok "Moved $moved earlier record file(s) from ~ into $OUT_DIR"; fi
  if [[ ! -e $old && ! -L $old ]] && grep -qs 'HOME/WORKSTATION-CHEATSHEET.md' "$HOME/.bashrc.d/10-workstation.sh"; then
    ln -s "$CHEATSHEET_FILE" "$old"
    record_undo "rm -f ~/WORKSTATION-CHEATSHEET.md"
    log "Left a link ~/WORKSTATION-CHEATSHEET.md: your ~/.bashrc.d/10-workstation.sh (an earlier version, never edited by this setup) still looks there. Delete the link when you replace that file."
  fi
}

main() {
  if (( LIST_PROFILES )); then list_profiles; return 0; fi
  if [[ $MODE == undo ]]; then undo_mode; return; fi
  if [[ $MODE == reset-shell ]]; then reset_shell_mode; return; fi
  if [[ $MODE == reset-defaults ]]; then reset_defaults_mode; return; fi
  load_config
  removed_switches_note
  case "$MODE" in
    check)    check_mode; return 0 ;;
    explain)  explain_mode; return 0 ;;
    selftest) mkdir -p "$DATA_DIR"; be_gentle; self_test; return ;;
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
  be_gentle
  migrate_records
  preflight
  remember_profile

  run_steps

  self_test || true
  write_manifest
  summary
}

main
