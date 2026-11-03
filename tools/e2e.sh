#!/usr/bin/env bash
# e2e.sh — full end-to-end test of the setup on a DISPOSABLE Ubuntu machine.
#
#   tools/e2e.sh --profile work|personal --i-know-this-machine-is-disposable
#   tools/e2e.sh --profile work --plan        show what it would do, change nothing
#
# It runs the whole life cycle of one profile, as a normal user with sudo, and
# checks the result of every phase:
#
#    1 explain+check   --explain and --check against the real package archive
#    2 install         the FULL setup (--full: every opt-in system change ON)
#    3 self-test       ./setup.sh --self-test --full
#    4 doctor          ws-doctor in a brand-new interactive shell
#    5 shell           the shell setup works: PATH, offline lock, ccache, editor, Oh My Bash
#    6 idempotent      the install a second time: still succeeds, no failed steps
#    7 manifest        --manifest and tools/manifest-diff.sh
#    8 lock            --lock into a scratch file, then --check loads the pins
#    9 undo            ./setup.sh --undo --yes (every undo file, newest first)
#   10 leftovers       nothing the setup created is left behind (except APT packages)
#
# DANGER: this installs software, changes services, groups, /etc and your shell
# files, then undoes what it can. Run it only in a throw-away VM or container.
# It refuses to run as root, or without --i-know-this-machine-is-disposable.
#
# Environment:
#   E2E_LOG_DIR             where logs and summary.md go (default ~/e2e-logs)
#   E2E_SWITCHES            extra setup switches, e.g. "CACHE_CONTAINER_IMAGES=0 INSTALL_RUST=0"
#   E2E_ALLOW_FAILED_STEPS  regex of step names that may fail in this environment
#                           (e.g. "System tuning" in a container without sysctl access)
#   E2E_ALLOW_MISSING       regex of packages allowed to be missing from the archive
#                           (default: lazygit|zellij|difftastic)
# Things the test knows about a machine it did not set up itself: if rustup (~/.rustup,
# ~/.cargo/bin/rustup) already exists before the install, it is not counted as a leftover; the CI VM job
# purges the runner's preinstalled `gh` (the no-cloud policy forbids it) and the container job removes the
# image's dpkg excludes (so documentation packages are not stripped). A full run takes ~15 minutes.
# Exit status: 0 = every phase passed, 1 = at least one failed.
set -uo pipefail
cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/.." || exit 1

PROFILE="" DISPOSABLE="${E2E_DISPOSABLE:-0}" PLAN=0 LOG="${E2E_LOG_DIR:-$HOME/e2e-logs}"
usage() { sed -n '2,/^set -/p' "${BASH_SOURCE[0]}" | sed '$d; s/^# \{0,1\}//'; }
while (( $# )); do
  case "$1" in
    --profile) PROFILE="${2:-}"; shift ;;
    --profile=*) PROFILE="${1#*=}" ;;
    --i-know-this-machine-is-disposable) DISPOSABLE=1 ;;
    --plan) PLAN=1 ;;
    --log-dir) LOG="${2:-}"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "e2e.sh: unknown option $1" >&2; usage >&2; exit 2 ;;
  esac
  shift
done
[[ $PROFILE =~ ^[a-z0-9][a-z0-9_-]*$ && -f profiles/$PROFILE.conf ]] \
  || { echo "e2e.sh: give --profile NAME (one of: $(find profiles -name '*.conf' -printf '%f\n' | sed 's/\.conf$//' | sort | paste -sd' '))" >&2; exit 2; }

if (( PLAN )); then
  echo "Plan for profile '$PROFILE' (nothing is run):"
  printf '  %2d. %s\n' 1 "explain+check" 2 "install (--full)" 3 "self-test" 4 "doctor (fresh interactive shell)" \
    5 "shell checks" 6 "idempotent re-install" 7 "manifest" 8 "lock" 9 "undo (--undo --yes, all undo files)" 10 "leftovers"
  exit 0
fi

# ------------------------------------------------------------------ safety
if [[ $DISPOSABLE != 1 ]]; then
  echo "e2e.sh installs software and changes system settings, then undoes what it can." >&2
  echo "Run it only on a disposable machine and say so with --i-know-this-machine-is-disposable." >&2
  exit 2
fi
if [[ $EUID -eq 0 ]]; then echo "e2e.sh: run as a normal user with sudo, not as root (setup.sh refuses root too)." >&2; exit 2; fi
# shellcheck disable=SC1091
. /etc/os-release
[[ ${ID:-} == ubuntu ]] || { echo "e2e.sh: this is for Ubuntu, found ${PRETTY_NAME:-unknown}" >&2; exit 2; }
sudo -n true 2>/dev/null || { echo "e2e.sh: needs passwordless sudo (a disposable machine)." >&2; exit 2; }

mkdir -p "$LOG"
read -ra SW <<<"${E2E_SWITCHES:-}"
ALLOW_FAILED="${E2E_ALLOW_FAILED_STEPS:-^\$}"
ALLOW_MISSING="${E2E_ALLOW_MISSING:-lazygit|zellij|difftastic}"
strip() { sed 's/\x1b\[[0-9;]*m//g'; }
# setup.sh with the profile, --full and the extra switches; never interactive
setup() { env "${SW[@]}" ./setup.sh --profile "$PROFILE" --full "$@" </dev/null; }

RESULTS=() FAILS=0 DETAILS=""
record() { # record STATUS PHASE SECONDS DETAIL
  RESULTS+=("$1|$2|$3")
  if [[ $1 == FAIL ]]; then FAILS=$((FAILS + 1)); DETAILS+=$'\n'"---- $2 ----"$'\n'"$4"$'\n'; fi
  printf '  %-5s %-16s %4ss\n' "$1" "$2" "$3"
}
run_phase() { # run_phase NAME FUNCTION   (the function prints its details; return 1 = fail, 2 = warn)
  local name="$1" fn="$2" start out rc
  start=$SECONDS
  echo; echo "=== phase: $name"
  out="$("$fn" 2>&1)"; rc=$?
  printf '%s\n' "$out" | tail -n 40
  case $rc in
    0) record PASS "$name" $((SECONDS - start)) "" ;;
    2) record WARN "$name" $((SECONDS - start)) "" ;;
    *) record FAIL "$name" $((SECONDS - start)) "$(printf '%s\n' "$out" | tail -n 60)" ;;
  esac
}

# parse the lists setup.sh prints at the end of an install
failed_steps()   { strip < "$1" | awk '/Steps that did not fully complete/ { f = 1; next } f && /^     - / { sub(/^     - /, ""); print; next } f { f = 0 }'; }
missing_things() { strip < "$1" | awk '/Packages\/tools that were skipped or failed/ { f = 1; next } f && /^     - / { sub(/^     - /, ""); print; next } f { f = 0 }'; }
check_install_log() { # check_install_log LOGFILE -> prints problems, returns 1 if any
  local log="$1" bad=0 s m
  while IFS= read -r s; do
    if [[ -n $s ]] && ! grep -Eq "$ALLOW_FAILED" <<<"$s"; then echo "FAILED STEP: $s"; bad=1; else [[ -n $s ]] && echo "(allowed) failed step: $s"; fi
  done < <(failed_steps "$log")
  while IFS= read -r m; do
    if [[ -n $m ]] && ! grep -Eq "^($ALLOW_MISSING)( |$)" <<<"$m"; then echo "UNEXPECTED MISSING: $m"; bad=1; else [[ -n $m ]] && echo "(allowed) missing: $m"; fi
  done < <(missing_things "$log")
  return $bad
}

# ------------------------------------------------------------------ phases
echo "E2E profile=$PROFILE  user=$(id -un)  $(. /etc/os-release; echo "$PRETTY_NAME")  kernel $(uname -r)"
echo "switches: ${E2E_SWITCHES:-(none)}   allowed failed steps: $ALLOW_FAILED"
df -h "$HOME" | tail -n 1 | sed 's/^/disk: /'

ph_explain_check() {
  local bad=0 out
  setup --explain > "$LOG/explain.log" 2>&1 || { echo "--explain failed"; tail -n 5 "$LOG/explain.log"; return 1; }
  if strip < "$LOG/explain.log" | grep -q 'no description yet'; then echo "a step has no description"; bad=1; fi
  setup --check > "$LOG/check.log" 2>&1 || { echo "--check failed"; tail -n 8 "$LOG/check.log"; return 1; }
  out="$(strip < "$LOG/check.log" | grep 'NOT AVAILABLE' | sed 's/^ *//')"
  while IFS= read -r line; do
    [[ -z $line ]] && continue
    if grep -Eq "^($ALLOW_MISSING) " <<<"$line"; then echo "(allowed) $line"; else echo "UNEXPECTED: $line"; bad=1; fi
  done <<<"$out"
  strip < "$LOG/check.log" | grep -E 'Simulation|conflict|installed, [0-9]+ to install' | sed 's/^/  /'
  if strip < "$LOG/check.log" | grep -q 'Simulation found a conflict'; then echo "apt simulation found a conflict"; bad=1; fi
  return $bad
}

ph_install() {
  local t0=$SECONDS rc=0
  setup > "$LOG/install.log" 2>&1 || rc=$?
  echo "setup.sh exit status $rc after $((SECONDS - t0))s"
  strip < "$LOG/install.log" | grep -E 'Self-test:|All steps completed|Steps that did not' | sed 's/^/  /'
  (( rc == 0 )) || { strip < "$LOG/install.log" | tail -n 30; return 1; }
  check_install_log "$LOG/install.log"
}

ph_selftest() {
  local rc=0
  setup --self-test > "$LOG/selftest.log" 2>&1 || rc=$?
  strip < "$LOG/selftest.log" | grep -E 'PASS|FAIL|WARN|SKIP|Self-test:' | sed 's/^/  /' | grep -E 'FAIL|WARN|Self-test:'
  strip < "$LOG/selftest.log" | grep -A8 'FAIL' | head -n 40
  # A skipped test proves nothing. The RISC-V QEMU test was silently skipped on 26.04 because RISC-V
  # emulation moved out of qemu-system-misc into its own package: treat that skip as a failure.
  local skipped; skipped="$(strip < "$LOG/selftest.log" | grep -E 'SKIP.*RISC-V' || true)"
  if [[ -n $skipped ]]; then echo "UNEXPECTED SKIP: $skipped"; rc=1; fi
  return $rc
}

ph_doctor() {
  local rc=0
  bash -ic 'ws-doctor' > "$LOG/doctor.log" 2>&1 || rc=$?
  strip < "$LOG/doctor.log" | grep -E 'FAIL|warn|summary' | sed 's/^/  /'
  return $rc
}

ph_shell() {
  local out bad=0
  out="$(bash -ic '
    echo "UV_OFFLINE=$UV_OFFLINE"; echo "CARGO_NET_OFFLINE=$CARGO_NET_OFFLINE"
    echo "LAUNCHER=$CMAKE_C_COMPILER_LAUNCHER"; echo "EDITOR=$EDITOR"; echo "OSH=${OSH:-}"; echo "PS1_SET=${PS1:+yes}"
    for t in ws-init ws-doctor uv hx cargo rustc ruff clangd cmake; do command -v "$t" >/dev/null && echo "have:$t" || echo "MISSING:$t"; done
  ' 2>&1 | strip)"
  printf '%s\n' "$out" | grep -E '=|MISSING' | sed 's/^/  /'
  grep -q '^MISSING:' <<<"$out" && bad=1
  grep -q '^UV_OFFLINE=1$' <<<"$out" || { echo "offline lock not active (UV_OFFLINE)"; bad=1; }
  grep -q '^CARGO_NET_OFFLINE=true$' <<<"$out" || { echo "offline lock not active (CARGO_NET_OFFLINE)"; bad=1; }
  grep -q '^LAUNCHER=ccache$' <<<"$out" || { echo "ccache launcher not set"; bad=1; }
  grep -q '^EDITOR=hx$' <<<"$out" || { echo "EDITOR is not hx"; bad=1; }
  grep -q '^OSH=.*oh-my-bash' <<<"$out" || { echo "Oh My Bash not loaded (OSH unset)"; bad=1; }
  return $bad
}

ph_idempotent() {
  local rc=0 n f
  setup > "$LOG/install2.log" 2>&1 || rc=$?
  echo "second run: exit status $rc"
  (( rc == 0 )) || { strip < "$LOG/install2.log" | tail -n 25; return 1; }
  check_install_log "$LOG/install2.log" || return 1
  f="$(find "$HOME" -maxdepth 1 -name 'workstation-undo-*.sh' -printf '%T@ %p\n' | sort -nr | head -n1 | cut -d' ' -f2-)"
  n="$(grep -vcE '^(#|set -x|$)' "$f" 2>/dev/null || echo 0)"
  echo "the second run recorded $n undo command(s):"; grep -vE '^(#|set -x|$)' "$f" | sed 's/^/    /' | head -n 12
  (( n <= 15 )) || return 2
}

ph_manifest() {
  local m="$HOME/workstation-manifest-latest.txt" bad=0
  setup --manifest > "$LOG/manifest.log" 2>&1 || { tail -n 8 "$LOG/manifest.log"; return 1; }
  [[ -s $m ]] || { echo "no manifest at $m"; return 1; }
  echo "manifest: $(wc -l < "$m") lines"
  for sec in '## Machine' '## Key tools' '## APT packages' '## Self-test'; do grep -q "^$sec" "$m" || { echo "manifest lacks section: $sec"; bad=1; }; done
  tools/manifest-diff.sh "$m" "$m" >/dev/null || { echo "manifest-diff reports differences between a file and itself"; bad=1; }
  return $bad
}

ph_lock() {
  local lock="$HOME/e2e.lock" bad=0
  WORKSTATION_LOCK="$lock" setup --lock > "$LOG/lock.log" 2>&1 || { tail -n 8 "$LOG/lock.log"; return 1; }
  [[ -s $lock ]] || { echo "no lock file written"; return 1; }
  grep -c '^  \["' "$lock" | sed 's/^/pins written: /'
  grep -q 'declare -gA UV_PINS' "$lock" || { echo "lock lacks UV_PINS"; bad=1; }
  grep -q 'RUST_TOOLCHAIN:=' "$lock" || { echo "lock lacks the Rust toolchain version"; bad=1; }
  if [[ "$(readlink "$HOME/.local/bin/node" 2>/dev/null || true)" == */opt/node-v* ]]; then
    grep -q 'NODE_LTS_VERSION:=v' "$lock" || { echo "lock lacks the Node.js version"; bad=1; }
  fi
  local checked; checked="$(WORKSTATION_LOCK="$lock" setup --check 2>&1 | strip || true)"   # captured: grep -q on a pipe can SIGPIPE under pipefail
  grep -q 'versions pinned' <<<"$checked" || { echo "--check did not load the lock"; bad=1; }
  grep -E 'UV_VERSION|HELIX_VERSION|NODE_LTS_VERSION|NERD_FONT_VERSION|OH_MY_BASH_COMMIT|PROBE_RS_VERSION|RUST_TOOLCHAIN' "$lock" | sed 's/^/  /'
  return $bad
}

ph_undo() {
  local n=0 f rc bad=0 seen=" "
  while :; do
    f="$(find "$HOME" -maxdepth 1 -name 'workstation-undo-*.sh' -printf '%T@ %p\n' | sort -nr | head -n1 | cut -d' ' -f2-)"
    [[ -n $f ]] || break
    [[ $seen == *" $f "* ]] && { echo "undo file $f was not consumed"; bad=1; break; }
    seen+="$f "
    n=$((n + 1)); rc=0
    setup --undo --yes > "$LOG/undo-$n.log" 2>&1 || rc=$?
    strip < "$LOG/undo-$n.log" | grep -E 'Undone|failed|command\(s\)' | sed "s|^|  undo $n: |"
    (( rc == 0 )) || { echo "--undo $n exited $rc"; strip < "$LOG/undo-$n.log" | tail -n 15; bad=1; break; }
    (( n < 8 )) || break
  done
  echo "$n undo file(s) replayed"
  return $bad
}

ph_leftovers() {
  local p bad=0 found=()
  # A runner image may already ship rustup: what existed before the install is not ours to remove.
  local -a skip=()
  if [[ -n ${E2E_PRE_RUSTUP:-} ]]; then skip=("$HOME/.rustup" "$HOME/.cargo/bin/rustup"); fi
  for p in "$HOME"/.local/bin/{ws-init,ws-doctor,ws-devname,uv,uvx,hx,probe-rs,cargo-flash,cargo-embed,starship,lazygit} \
           "$HOME/.local/share/workstation" "$HOME/.config/helix" "$HOME/.config/uv" "$HOME/.config/kate/lspclient/settings.json" \
           "$HOME/.local/share/oh-my-bash" "$HOME/.local/share/fonts/JetBrainsMonoNerdFont" "$HOME/WORKSTATION-CHEATSHEET.md" \
           "$HOME/.inputrc" "$HOME/.cargo/bin/rustup" "$HOME/.rustup" "$HOME/.local/opt" "$HOME"/.local/bin/{node,npm,npx} /etc/sysctl.d/60-dev-inotify.conf \
           /etc/firefox/policies/policies.json /etc/thunderbird/policies/policies.json; do
    if [[ " ${skip[*]} " == *" $p "* ]]; then continue; fi
    if [[ -d $p ]]; then
      # an empty directory is not a leftover (undo removes the files it created, not the folders)
      [[ -n "$(find "$p" -type f -print -quit 2>/dev/null)" ]] && found+=("$p")
    elif [[ -e $p ]]; then
      found+=("$p")
    fi
  done
  compgen -G "$HOME/.bashrc.d/*.sh" >/dev/null && found+=("$(compgen -G "$HOME/.bashrc.d/*.sh" | paste -sd' ')")
  grep -q 'workstation-setup: load' "$HOME/.bashrc" 2>/dev/null && found+=("loader block in ~/.bashrc")
  if (( ${#found[@]} )); then printf 'LEFT BEHIND: %s\n' "${found[@]}"; bad=1; else echo "nothing left behind (APT packages are not removed by design)"; fi
  bash -ic 'ws-doctor --quiet' 2>&1 | strip | tail -n 2 | sed 's/^/  after undo: /'
  return $bad
}

if [[ -e $HOME/.rustup || -e $HOME/.cargo/bin/rustup ]]; then E2E_PRE_RUSTUP=1; fi

echo; echo "Running 10 phases (this takes a while: it is a full install)"
run_phase "explain+check" ph_explain_check
run_phase install        ph_install
run_phase self-test      ph_selftest
run_phase doctor         ph_doctor
run_phase shell          ph_shell
run_phase idempotent     ph_idempotent
run_phase manifest       ph_manifest
run_phase lock           ph_lock
run_phase undo           ph_undo
run_phase leftovers      ph_leftovers

# ------------------------------------------------------------------ summary
{
  echo "# E2E result: profile $PROFILE on $(. /etc/os-release; echo "$PRETTY_NAME")"
  echo; echo "| Phase | Result | Seconds |"; echo "|---|---|---|"
  for r in "${RESULTS[@]}"; do IFS='|' read -r st ph sec <<<"$r"; echo "| $ph | $st | $sec |"; done
  if (( FAILS )); then echo; echo '```'; printf '%s\n' "$DETAILS"; echo '```'; fi
} > "$LOG/summary.md"

echo; echo "================ E2E SUMMARY (profile $PROFILE) ================"
for r in "${RESULTS[@]}"; do IFS='|' read -r st ph sec <<<"$r"; printf '  %-5s %-16s %4ss\n' "$st" "$ph" "$sec"; done
if (( FAILS )); then echo; echo "FAILED PHASES: $FAILS"; printf '%s\n' "$DETAILS"; fi
echo "logs: $LOG"
(( FAILS == 0 ))
