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
#   11 reset-shell     a zsh / Oh My Zsh user: real zsh, login shell zsh, then ./setup.sh --reset-shell
#                      (files moved to a backup folder, login shell back to bash), then --undo (zsh again)
#   12 starship        the real starship install from its release (--full turns Oh My Bash on, which owns
#                      the prompt, so the main install never exercises it): scratch HOME, checks the undo line
#   13 reset-defaults  the full install left Ubuntu's own services exactly as they were; then what an older
#                      version left behind (a disabled motd-news.timer, the inotify file, a git default, the
#                      ~/.bashrc block) is put back by ./setup.sh --reset-defaults, and --undo restores it
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
#                           (default: zellij|difftastic; lazygit is no longer allowed: it comes from its
#                           release, and a fallback to the archive's package is reported as a problem)
# It runs once per supported Ubuntu release (24.04 and the newest LTS; see .github/workflows/e2e.yml).
# Things the test knows about a machine it did not set up itself: if rustup (~/.rustup,
# ~/.cargo/bin/rustup) already exists before the install, it is not counted as a leftover; the CI VM job
# purges the runner's preinstalled `gh` (the no-cloud policy forbids it) and the container job removes the
# image's dpkg excludes (so documentation packages are not stripped). A full run takes about 12 to 22 minutes (the install step 9 to 19).
# Exit status: 0 = every phase passed, 1 = at least one failed.
set -uo pipefail
cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/.." || exit 1

OUT="$HOME/workstation-setup"   # the records folder: undo scripts, manifests, logs, the cheat sheet
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
    5 "shell checks" 6 "idempotent re-install" 7 "manifest" 8 "lock" 9 "undo (--undo --yes, all undo files)" 10 "leftovers" 11 "reset-shell (zsh user, then undo)" 12 "starship (real release, scratch HOME)" \
    13 "reset-defaults (Ubuntu's services untouched; reset, then undo)"
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
ALLOW_MISSING="${E2E_ALLOW_MISSING:-zellij|difftastic}"
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
  local t0=$SECONDS rc=0 t pre=""
  # What was on the machine BEFORE the setup (a runner image may ship uv): such a tool is left alone, by design.
  for t in uv hx helix nvim starship lazygit rustup; do if command -v "$t" >/dev/null 2>&1; then pre+=" $t"; fi; done
  echo "tools already on the machine before the setup:${pre:- (none)}"
  setup > "$LOG/install.log" 2>&1 || rc=$?
  echo "setup.sh exit status $rc after $((SECONDS - t0))s"
  strip < "$LOG/install.log" | grep -E 'Self-test:|All steps completed|Steps that did not' | sed 's/^/  /'
  (( rc == 0 )) || { strip < "$LOG/install.log" | tail -n 30; return 1; }
  # The newest upstream release wins over the archive's older package (uv, Helix, starship): each of them must
  # have been installed by the setup into ~/.local/bin, not taken from Ubuntu. A fallback to the archive after a
  # failed download is written to the "skipped or failed" list, which check_install_log below rejects.
  local bad=0 want="uv lazygit"
  if grep -q 'INSTALL_HELIX=0' <<<"${E2E_SWITCHES:-}"; then :; else want+=" hx"; fi
  if grep -q 'INSTALL_NVIM=0' <<<"${E2E_SWITCHES:-}"; then :; else want+=" nvim"; fi
  for t in $want; do
    if [[ " $pre " == *" $t "* ]]; then echo "(already there before the setup, left alone) $t"; continue; fi
    if [[ -x $HOME/.local/bin/$t ]]; then echo "upstream: $t -> $("$HOME/.local/bin/$t" --version | head -n 1)"
    else echo "NOT UPSTREAM: $t is not in ~/.local/bin (resolves to: $(command -v "$t" || echo nothing))"; bad=1; fi
  done
  # The records live in ONE folder (~/workstation-setup), not loose in ~: nothing of the kind may sit directly in ~.
  local loose; loose="$(find "$HOME" -maxdepth 1 \( -name 'workstation-undo-*' -o -name 'workstation-manifest-*' -o -name 'workstation-setup-*.log' -o -name 'WORKSTATION-CHEATSHEET.md' \) | head -n 5)"
  if [[ -n $loose ]]; then echo "LOOSE RECORD FILES in ~: $loose"; bad=1; fi
  for t in WORKSTATION-CHEATSHEET.md workstation-manifest-latest.txt; do
    if [[ $t == workstation-manifest-latest.txt ]]; then continue; fi    # written by the manifest at the end of the run
    [[ -s $OUT/$t ]] || { echo "missing in $OUT: $t"; bad=1; }
  done
  [[ -n "$(find "$OUT" -maxdepth 1 -name 'workstation-undo-*.sh' -o -maxdepth 1 -name 'workstation-setup-*.log' | head -n1)" ]] || { echo "no undo script or log in $OUT"; bad=1; }
  # rustup lives in ~/.cargo/bin (rustup-init); a runner VM image already ships one, which is left alone.
  if ! grep -q 'INSTALL_RUST=0' <<<"${E2E_SWITCHES:-}"; then
    if [[ " $pre " == *" rustup "* ]]; then echo "(already there before the setup, left alone) rustup"
    elif [[ -x $HOME/.cargo/bin/rustup ]]; then echo "upstream: rustup -> $("$HOME/.cargo/bin/rustup" --version 2>/dev/null | head -n 1)"
    else echo "NOT UPSTREAM: rustup is not in ~/.cargo/bin (resolves to: $(command -v rustup || echo nothing))"; bad=1; fi
  fi
  check_install_log "$LOG/install.log" || bad=1
  return $bad
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
    echo "WSHELP_FILE=$(type ws-help 2>&1 | grep -o "[^ ]*WORKSTATION-CHEATSHEET.md" | head -n1)"
    echo "ALIAS_LS=$(alias ls 2>&1)"; echo "ALIAS_LL=$(alias ll 2>&1)"; echo "ALIAS_LA=$(alias la 2>&1)"; echo "ALIAS_GREP=$(alias grep 2>&1)"
  ' 2>&1 | strip)"
  printf '%s\n' "$out" | grep -E '=|MISSING' | sed 's/^/  /'
  grep -q '^MISSING:' <<<"$out" && bad=1
  # The user is NOT blocked from the network (their decision): the strict lock is opt-in (ENFORCE_OFFLINE_ENV=1) and
  # must not be active after a default install. Checked in a new interactive shell, where the lock would apply.
  grep -q '^UV_OFFLINE=$' <<<"$out" || { echo "uv is blocked from the network in a new shell (UV_OFFLINE is set): the strict lock must be off by default"; bad=1; }
  grep -q '^CARGO_NET_OFFLINE=$' <<<"$out" || { echo "cargo is blocked from the network in a new shell (CARGO_NET_OFFLINE is set)"; bad=1; }
  [[ ! -e $HOME/.bashrc.d/20-offline.sh ]] || { echo "$HOME/.bashrc.d/20-offline.sh was installed although ENFORCE_OFFLINE_ENV is off by default"; bad=1; }
  grep -q '^LAUNCHER=ccache$' <<<"$out" || { echo "ccache launcher not set"; bad=1; }
  grep -q '^EDITOR=hx$' <<<"$out" || { echo "EDITOR is not hx"; bad=1; }
  grep -q '^OSH=.*oh-my-bash' <<<"$out" || { echo "Oh My Bash not loaded (OSH unset)"; bad=1; }
  # The aliases themselves, not just the environment. Oh My Bash (on in --full) defines its own ls/ll/la/grep
  # while it loads; ours (16-aliases.sh) must come after it. This was only found on a real machine.
  if command -v eza >/dev/null; then
    for t in LS LL LA; do
      grep -q "^ALIAS_$t=alias ${t,,}='eza" <<<"$out" || { echo "alias ${t,,} is not eza in a new shell (Oh My Bash replaced it?): $(grep "^ALIAS_$t=" <<<"$out")"; bad=1; }
    done
  fi
  # ws-help reads the cheat sheet from the records folder (a fresh 10-workstation.sh has the new path)
  grep -q '^WSHELP_FILE=.*workstation-setup.*' <<<"$out" || grep -q 'workstation-setup' <<<"$(bash -ic 'type ws-help' 2>&1)" || { echo "ws-help does not look in the records folder"; bad=1; }
  grep -q "^ALIAS_GREP=alias grep='grep --color=auto'$" <<<"$out" || { echo "alias grep is not ours in a new shell: $(grep '^ALIAS_GREP=' <<<"$out")"; bad=1; }
  return $bad
}

ph_idempotent() {
  local rc=0 n f
  setup > "$LOG/install2.log" 2>&1 || rc=$?
  echo "second run: exit status $rc"
  (( rc == 0 )) || { strip < "$LOG/install2.log" | tail -n 25; return 1; }
  check_install_log "$LOG/install2.log" || return 1
  f="$(find "$OUT" -maxdepth 1 -name 'workstation-undo-*.sh' -printf '%T@ %p\n' | sort -nr | head -n1 | cut -d' ' -f2-)"
  n="$(grep -vcE '^(#|set -x|$)' "$f" 2>/dev/null || echo 0)"
  echo "the second run recorded $n undo command(s):"; grep -vE '^(#|set -x|$)' "$f" | sed 's/^/    /' | head -n 12
  (( n <= 15 )) || return 2
}

ph_manifest() {
  local m="$OUT/workstation-manifest-latest.txt" bad=0
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
  grep -q 'UV_VERSION:=' "$lock" || { echo "lock lacks the uv version"; bad=1; }
  grep -q 'LAZYGIT_VERSION:=v' "$lock" || { echo "lock lacks the lazygit version"; bad=1; }
  grep -q 'RUSTUP_VERSION:=' "$lock" || { echo "lock lacks the rustup version"; bad=1; }
  if [[ "$(readlink "$HOME/.local/bin/nvim" 2>/dev/null || true)" == */opt/nvim-v* ]]; then
    grep -q 'NVIM_VERSION:=v' "$lock" || { echo "lock lacks the Neovim version"; bad=1; }
  fi
  if [[ "$(readlink "$HOME/.local/bin/node" 2>/dev/null || true)" == */opt/node-v* ]]; then
    grep -q 'NODE_LTS_VERSION:=v' "$lock" || { echo "lock lacks the Node.js version"; bad=1; }
  fi
  local checked; checked="$(WORKSTATION_LOCK="$lock" setup --check 2>&1 | strip || true)"   # captured: grep -q on a pipe can SIGPIPE under pipefail
  grep -q 'versions pinned' <<<"$checked" || { echo "--check did not load the lock"; bad=1; }
  grep -E 'UV_VERSION|HELIX_VERSION|NVIM_VERSION|STARSHIP_VERSION|RUSTUP_VERSION|LAZYGIT_VERSION|NODE_LTS_VERSION|NERD_FONT_VERSION|OH_MY_BASH_COMMIT|PROBE_RS_VERSION|RUST_TOOLCHAIN' "$lock" | sed 's/^/  /'
  return $bad
}

ph_undo() {
  local n=0 f rc bad=0 seen=" "
  while :; do
    f="$(find "$OUT" -maxdepth 1 -name 'workstation-undo-*.sh' -printf '%T@ %p\n' | sort -nr | head -n1 | cut -d' ' -f2-)"
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
  for p in "$HOME"/.local/bin/{ws-init,ws-doctor,ws-devname,uv,uvx,hx,nvim,probe-rs,cargo-flash,cargo-embed,starship,lazygit} \
           "$HOME/.local/share/workstation" "$HOME/.config/helix" "$HOME/.config/nvim" "$HOME/.config/uv" "$HOME/.config/kate/lspclient/settings.json" "$HOME/.config/kate/formatting/settings.json" "$HOME/.local/bin/ws-pyformat" \
           "$HOME/.local/share/oh-my-bash" "$HOME/.local/share/fonts/JetBrainsMonoNerdFont" "$OUT/WORKSTATION-CHEATSHEET.md" \
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
  # settings outside files: both were left behind by --undo until --reset-defaults found them
  if [[ -z $E2E_PRE_LFS && -n "$(git config --global --get filter.lfs.process 2>/dev/null || true)" ]]; then found+=("the global Git LFS filter in ~/.gitconfig"); fi
  if [[ -z $E2E_PRE_WS ]] && dpkg -s wireshark-common >/dev/null 2>&1 && [[ "$(debconf-show wireshark-common 2>/dev/null | awk -F': ' '/install-setuid/ { print $2 }')" == true ]]; then
    found+=("wireshark-common: non-root capture still on (debconf install-setuid)")
  fi
  if (( ${#found[@]} )); then printf 'LEFT BEHIND: %s\n' "${found[@]}"; bad=1; else echo "nothing left behind (APT packages are not removed by design)"; fi
  bash -ic 'ws-doctor --quiet' 2>&1 | strip | tail -n 2 | sed 's/^/  after undo: /'
  return $bad
}

if [[ -e $HOME/.rustup || -e $HOME/.cargo/bin/rustup ]]; then E2E_PRE_RUSTUP=1; fi
# The state of Ubuntu's own services before anything runs: the setup must never change it (decided by the user).
UBUNTU_UNITS=(apport-autoreport.path apport-autoreport.timer whoopsie.path kerneloops.service motd-news.timer fwupd-refresh.timer)
declare -A E2E_PRE_UNITS=()
# A container image has no systemctl before the install (systemd comes in with the packages): then the states before are
# unknown, and the check below can only require that no unit is disabled or masked (the setup never does either).
# What the image already had is not the setup's to remove (checked in the leftovers phase).
E2E_PRE_LFS=""; E2E_PRE_WS=""
if [[ -n "$(git config --global --get filter.lfs.process 2>/dev/null || true)" ]]; then E2E_PRE_LFS=1; fi
if [[ "$(debconf-show wireshark-common 2>/dev/null | awk -F': ' '/install-setuid/ { print $2 }' || true)" == true ]]; then E2E_PRE_WS=1; fi
E2E_PRE_SYSTEMCTL=0; if command -v systemctl >/dev/null 2>&1; then E2E_PRE_SYSTEMCTL=1; fi
unit_state() { local s; s="$(systemctl is-enabled "$1" 2>/dev/null || true)"; [[ $s == not-found ]] && s=""; echo "$s"; }
for u in "${UBUNTU_UNITS[@]}"; do E2E_PRE_UNITS[$u]="$( (( E2E_PRE_SYSTEMCTL )) && unit_state "$u")"; done
# Is unit U still as it was before the install? (Without a systemctl before: not disabled and not masked.)
unit_as_before() {
  local now; now="$(unit_state "$1")"
  if (( E2E_PRE_SYSTEMCTL )); then [[ $now == "${E2E_PRE_UNITS[$1]}" ]]; else [[ $now != disabled && $now != masked ]]; fi
}

# Last, so it cannot disturb the phases above: someone who comes from zsh. Installs zsh (an APT
# package: it stays, like every package this test installs), pretends to have Oh My Zsh, makes zsh
# the login shell, then checks ./setup.sh --reset-shell and --undo against the REAL getent/usermod,
# and finally puts the login shell back as it was.
ph_reset_shell() {
  local me orig bad=0 got backup
  me="$(id -un)"; orig="$(getent passwd "$me" | cut -d: -f7)"
  sudo apt-get install -y --no-remove --no-upgrade zsh >/dev/null 2>&1 || { echo "could not install zsh"; return 1; }
  mkdir -p "$HOME/.oh-my-zsh"; echo omz > "$HOME/.oh-my-zsh/oh-my-zsh.sh"
  # shellcheck disable=SC2016  # the file must contain $HOME literally
  echo 'export ZSH="$HOME/.oh-my-zsh"' > "$HOME/.zshrc"; echo hist > "$HOME/.zsh_history"
  sudo usermod -s /usr/bin/zsh "$me" || { echo "usermod to zsh failed"; return 1; }
  [[ "$(getent passwd "$me" | cut -d: -f7)" == /usr/bin/zsh ]] || { echo "could not make zsh the login shell"; bad=1; }

  ./setup.sh --reset-shell --dry-run </dev/null >/dev/null 2>&1 || { echo "--reset-shell --dry-run failed"; bad=1; }
  [[ -e $HOME/.zshrc ]] || { echo "--dry-run moved files"; bad=1; }
  ./setup.sh --reset-shell --yes </dev/null > "$LOG/reset-shell.log" 2>&1 || { echo "--reset-shell failed"; strip < "$LOG/reset-shell.log" | tail -n 12; bad=1; }
  got="$(getent passwd "$me" | cut -d: -f7)"
  [[ $got == /bin/bash ]] || { echo "login shell after reset is '$got', not /bin/bash"; bad=1; }
  backup="$(find "$HOME" -maxdepth 1 -name 'workstation-shell-backup-*' -type d | head -n1)"
  [[ -n $backup && -e $backup/.zshrc && -e $backup/.oh-my-zsh/oh-my-zsh.sh && -e $backup/.zsh_history ]] || { echo "zsh files are not in the backup folder"; bad=1; }
  [[ ! -e $HOME/.zshrc && ! -e $HOME/.oh-my-zsh ]] || { echo "zsh files are still in the home directory"; bad=1; }
  [[ -e $HOME/.bashrc ]] || { echo "$HOME/.bashrc is missing after the reset"; bad=1; }
  command -v zsh >/dev/null || { echo "the zsh package was removed (it must stay)"; bad=1; }

  ./setup.sh --undo --yes </dev/null > "$LOG/reset-shell-undo.log" 2>&1 || { echo "--undo of the reset failed"; strip < "$LOG/reset-shell-undo.log" | tail -n 12; bad=1; }
  got="$(getent passwd "$me" | cut -d: -f7)"
  [[ $got == /usr/bin/zsh ]] || { echo "login shell after undo is '$got', not /usr/bin/zsh"; bad=1; }
  [[ -e $HOME/.zshrc && -e $HOME/.oh-my-zsh/oh-my-zsh.sh && ! -d $backup ]] || { echo "undo did not bring the zsh files back"; bad=1; }

  sudo usermod -s "$orig" "$me" || true            # leave the machine's login shell as we found it
  rm -rf "$HOME/.oh-my-zsh" "$HOME/.zshrc" "$HOME/.zsh_history"
  [[ "$(getent passwd "$me" | cut -d: -f7)" == "$orig" ]] || { echo "could not restore the original login shell $orig"; bad=1; }
  (( bad == 0 )) && echo "reset-shell: zsh -> bash -> (undo) zsh worked against the real usermod; original login shell $orig restored"
  return $bad
}

# --full turns Oh My Bash on, and while it is on it owns the prompt, so the main install never installs starship.
# This phase runs the real starship install (real download, real published checksum) the way a default run does,
# in a scratch HOME, and checks that it lands in ~/.local/bin, runs, records its undo line and is skipped the
# second time because the newest release is already there.
ph_starship() {
  local h bad=0 out; h="$(mktemp -d)"
  out="$(HOME="$h" bash -c 'source <(head -n -1 ./setup.sh); init_undo_file
    starship_install_upstream && starship_install_upstream
    echo "VERSION=$("$HOME/.local/bin/starship" --version | head -n1)"; echo "UNDO=$(grep -c "^rm -f ~/.local/bin/starship" "$UNDO_FILE")"' 2>&1 | strip)"
  printf '%s\n' "$out" | tail -n 6
  grep -q '^VERSION=starship [0-9]' <<<"$out" || { echo "starship was not installed from its release"; bad=1; }
  grep -q '^UNDO=1$' <<<"$out" || { echo "expected exactly one undo line"; bad=1; }
  grep -q 'is the newest stable release' <<<"$out" || { echo "the second run did not recognise the installed release"; bad=1; }
  rm -rf "$h"
  return $bad
}

# Ubuntu's own services must be exactly as they were before the full install (the setup never touches them).
# Then the state an OLDER version of the setup could leave behind is made by hand, and ./setup.sh --reset-defaults
# must put it back to Ubuntu's default, against the real systemctl, sudo and git; --undo must restore it; finally
# the machine is left as it was.
ph_reset_defaults() {
  local bad=0 u now f=/etc/sysctl.d/60-dev-inotify.conf sim_unit=0 out
  if (( ! E2E_PRE_SYSTEMCTL )); then echo "(no systemctl before the install, a container: checking that no unit is disabled or masked)"; fi
  for u in "${UBUNTU_UNITS[@]}"; do
    now="$(unit_state "$u")"
    if ! unit_as_before "$u"; then echo "$u was '${E2E_PRE_UNITS[$u]}' before the install and is '$now' now: the setup must not touch Ubuntu's services"; bad=1
    else echo "unchanged by the setup: $u (${now:-not installed})"; fi
  done
  u=motd-news.timer
  if [[ "$(systemctl is-enabled "$u" 2>/dev/null || true)" == enabled ]]; then sudo systemctl disable "$u" >/dev/null 2>&1 && sim_unit=1
  else echo "($u is not enabled here: the unit part is not exercised)"; fi
  if git config --global --get init.defaultBranch >/dev/null; then echo "init.defaultBranch is set before the test (undo should have removed it)"; bad=1; fi
  git config --global init.defaultBranch main
  printf '\n# >>> workstation-setup: load ~/.bashrc.d/*.sh >>>\n# <<< workstation-setup <<<\n' >> "$HOME/.bashrc"
  if [[ -e $f ]]; then echo "$f exists before the test (undo should have removed it)"; bad=1; fi
  printf 'fs.inotify.max_user_watches = 524288\nfs.inotify.max_user_instances = 1024\n' | sudo tee "$f" >/dev/null

  ./setup.sh --reset-defaults --dry-run </dev/null > "$LOG/reset-defaults-dry.log" 2>&1 || { echo "--reset-defaults --dry-run failed"; strip < "$LOG/reset-defaults-dry.log" | tail -n 15; bad=1; }
  out="$(strip < "$LOG/reset-defaults-dry.log")"
  for x in 60-dev-inotify.conf init.defaultBranch "setup's block from ~/.bashrc" 'Dry run'; do
    [[ $out == *"$x"* ]] || { echo "the dry run does not list: $x"; bad=1; }
  done
  if (( sim_unit )) && [[ $out != *"$u on again"* ]]; then echo "the dry run does not list $u"; bad=1; fi
  [[ -e $f ]] || { echo "the dry run removed $f"; bad=1; }
  printf '%s\n' "$out" | sed -n '/These settings differ/,/^$/p' | head -n 20

  ./setup.sh --reset-defaults --yes </dev/null > "$LOG/reset-defaults.log" 2>&1 || { echo "--reset-defaults failed"; strip < "$LOG/reset-defaults.log" | tail -n 15; bad=1; }
  [[ ! -e $f ]] || { echo "$f is still there after the reset"; bad=1; }
  [[ -z "$(git config --global --get init.defaultBranch || true)" ]] || { echo "init.defaultBranch is still set after the reset"; bad=1; }
  if grep -q '# >>> workstation-setup' "$HOME/.bashrc"; then echo "the ~/.bashrc block is still there after the reset"; bad=1; fi
  if (( sim_unit )) && [[ "$(systemctl is-enabled "$u" 2>/dev/null || true)" != enabled ]]; then echo "$u is not enabled after the reset"; bad=1; fi

  ./setup.sh --undo --yes </dev/null > "$LOG/reset-defaults-undo.log" 2>&1 || { echo "--undo of the reset failed"; strip < "$LOG/reset-defaults-undo.log" | tail -n 15; bad=1; }
  [[ -e $f ]] || { echo "undo did not bring $f back"; bad=1; }
  [[ "$(git config --global --get init.defaultBranch || true)" == main ]] || { echo "undo did not bring init.defaultBranch back"; bad=1; }
  grep -q '# >>> workstation-setup' "$HOME/.bashrc" || { echo "undo did not bring the ~/.bashrc block back"; bad=1; }
  if (( sim_unit )) && [[ "$(systemctl is-enabled "$u" 2>/dev/null || true)" != disabled ]]; then echo "undo did not disable $u again"; bad=1; fi

  # leave the machine as it was
  if (( sim_unit )); then sudo systemctl enable "$u" >/dev/null 2>&1 || true; fi
  git config --global --unset init.defaultBranch || true
  sed -i '/# >>> workstation-setup/,/# <<< workstation-setup <<</d' "$HOME/.bashrc"
  sudo rm -f "$f"
  for u in "${UBUNTU_UNITS[@]}"; do
    if ! unit_as_before "$u"; then echo "after the test $u is '$(unit_state "$u")', it was '${E2E_PRE_UNITS[$u]}'"; bad=1; fi
  done
  (( bad == 0 )) && echo "reset-defaults: Ubuntu's services untouched by the install; reset and undo worked against the real systemctl, sudo and git"
  return $bad
}

echo; echo "Running 13 phases (this takes a while: it is a full install)"
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
run_phase reset-shell    ph_reset_shell
run_phase starship       ph_starship
run_phase reset-defaults ph_reset_defaults

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
