#!/usr/bin/env bash
# check-all.sh — every check of this repository in one command. Read-only for your
# system: everything that writes runs in a throw-away HOME below /tmp.
#
#   tools/check-all.sh            all checks
#   tools/check-all.sh --quick    static checks only (used by the git hook)
#
# Static:      bash -n and shellcheck on all shell files, JSON/TOML/YAML parse,
#              README <-> script sync (tools/check-readme-sync.sh), the README's
#              bash code blocks parse, '--explain' works for both profiles.
# Functional:  ws-init, ws-doctor, --undo, --reset-shell, manifest-diff, the checksum-verified
#              download helper (including a tamper test), the LibreOffice helper.
# Exit status: 0 = all passed, 1 = at least one check failed.
set -uo pipefail
cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/.." || exit 1

QUICK=0
case "${1:-}" in
  --quick) QUICK=1 ;;
  -h|--help) sed -n '2,/^set -/p' "${BASH_SOURCE[0]}" | sed '$d; s/^# \{0,1\}//'; exit 0 ;;
  "") ;;
  *) echo "unknown option: $1" >&2; exit 2 ;;
esac

if [[ -t 1 ]]; then G=$'\e[32m'; R=$'\e[31m'; B=$'\e[1m'; O=$'\e[0m'; else G=; R=; B=; O=; fi
PASS=0 FAIL=0
section() { printf '\n%s%s%s\n' "$B" "$*" "$O"; }
check() { # check "title" command...
  local title="$1"; shift
  local out rc=0
  out="$("$@" 2>&1)" || rc=$?
  if (( rc == 0 )); then PASS=$((PASS + 1)); printf '  %sok%s    %s\n' "$G" "$O" "$title"
  else FAIL=$((FAIL + 1)); printf '  %sFAIL%s  %s\n' "$R" "$O" "$title"; printf '%s\n' "$out" | tail -n 12 | sed 's/^/          /'; fi
}

REPO="$PWD"
TMP="$(mktemp -d)"
LIB="$REPO/.tmp-harness-setup.sh"      # setup.sh without its last line (git-ignored)
trap 'rm -rf -- "$TMP"; rm -f -- "$LIB"' EXIT

mapfile -t SHELL_FILES < <(
  { echo setup.sh; ls tools/*.sh tools/githooks/* files/home/.local/bin/* files/home/.bashrc.d/*.sh \
      modules/*/module.sh modules/*/files/home/.local/bin/* modules/*/files/home/.bashrc.d/*.sh 2>/dev/null; } | sort -u)

# ---------------------------------------------------------------- static
section "Shell files (${#SHELL_FILES[@]})"
syntax_all() { local f rc=0; for f in "${SHELL_FILES[@]}"; do bash -n "$f" || rc=1; done; return $rc; }
check "bash -n on every shell file" syntax_all
if command -v shellcheck >/dev/null; then
  check "shellcheck on every shell file" shellcheck -x "${SHELL_FILES[@]}"
else
  printf '  skip  shellcheck is not installed (sudo apt install shellcheck)\n'
fi

section "Data files"
parse_data() {
  python3 -I - <<'PY'
import glob, json, sys, tomllib
bad = 0
for f in sorted(set(glob.glob("**/*", recursive=True) + glob.glob("**/.*", recursive=True))):
    if f.startswith(".git/") or f.endswith(".done"): continue
    try:
        if f.endswith(".json"): json.load(open(f))
        elif f.endswith(".toml"): tomllib.load(open(f, "rb"))
        elif f.endswith((".yml", ".yaml")) or f.endswith(".pre-commit-config.yaml") or f.endswith(".clang-format") or f.endswith(".clang-tidy"):
            try:
                import yaml
            except ImportError:
                continue
            yaml.safe_load(open(f))
    except Exception as e:
        print("BAD", f, e); bad += 1
sys.exit(1 if bad else 0)
PY
}
check "JSON, TOML and YAML files parse" parse_data

section "README and script stay in step"
check "tools/check-readme-sync.sh" tools/check-readme-sync.sh
readme_blocks() {
  python3 -I - <<'PY'
import re, subprocess, sys
bad = 0
for i, b in enumerate(re.findall(r"```bash\n(.*?)```", open("README.md").read(), re.S)):
    r = subprocess.run(["bash", "-n"], input=b, text=True, capture_output=True)
    if r.returncode: bad += 1; print("README block", i, r.stderr.strip())
sys.exit(1 if bad else 0)
PY
}
check "every bash block in README.md parses" readme_blocks

section "Script modes"
explain_all() {
  local p
  for p in $(sed -n 's/^.*profiles\/\(.*\)\.conf.*/\1/p' /dev/null) work personal; do
    HOME="$TMP/h-explain" ./setup.sh --explain --profile "$p" | grep -q 'no description yet' && { echo "profile $p: step without description"; return 1; }
    HOME="$TMP/h-explain" ./setup.sh --full --explain --profile "$p" >/dev/null || return 1
    HOME="$TMP/h-explain" ./setup.sh --check --profile "$p" >/dev/null || return 1
  done
}
mkdir -p "$TMP/h-explain"
check "--explain, --full --explain and --check run for every profile" explain_all
check "--list-profiles" ./setup.sh --list-profiles
check "tools/e2e.sh --plan (and it refuses without the disposable flag)" bash -c 'tools/e2e.sh --profile work --plan >/dev/null && ! tools/e2e.sh --profile work >/dev/null 2>&1'

if (( QUICK )); then
  printf '\n%s%d passed, %d failed%s (quick mode: functional checks skipped)\n' "$B" "$PASS" "$FAIL" "$O"
  (( FAIL == 0 )); exit
fi

# ---------------------------------------------------------------- functional
section "Functional checks (in a throw-away HOME)"
export HOME_SAVED="$HOME"

t_ws_init() {
  local d="$TMP/wsinit"; mkdir -p "$d/tpl" "$d/proj"
  cp -r files/templates "$d/tpl/generic"; cp -r modules/embedded/files/templates "$d/tpl/embedded"
  cd "$d/proj" || return 1
  WS_TEMPLATE_DIR="$d/tpl" "$REPO/files/home/.local/bin/ws-init" --embedded >/dev/null || return 1
  test -f cmake/arm-none-eabi.cmake && test -f .editorconfig || return 1
  jq -e '.include == ["cmake/embedded-presets.json"]' CMakePresets.json >/dev/null || return 1
  echo keep > .editorconfig
  # (captured, not piped into 'grep -q': with pipefail the early exit of grep would fail the pipeline)
  local again
  again="$(WS_TEMPLATE_DIR="$d/tpl" "$REPO/files/home/.local/bin/ws-init")"
  grep -q 'skip (exists): .editorconfig' <<<"$again" || return 1
  [[ "$(cat .editorconfig)" == keep ]]
}
check "ws-init: generic + --embedded, patches CMakePresets, never overwrites" t_ws_init

t_doctor() {
  local out rc=0
  out="$(HOME="$TMP/h-doctor" files/home/.local/bin/ws-doctor --quiet 2>&1)" || rc=$?
  (( rc <= 1 )) && grep -q 'ws-doctor summary' <<<"$out"
}
mkdir -p "$TMP/h-doctor"
check "ws-doctor runs on its own and prints its summary" t_doctor

t_undo() {
  local h="$TMP/h-undo"; mkdir -p "$h/s"; touch "$h/s/a" "$h/s/b"
  printf '#!/usr/bin/env bash\nset -x\nrm -f %s/s/a\nrm -f %s/s/b\n' "$h" "$h" > "$h/workstation-undo-1.sh"
  HOME="$h" ./setup.sh --undo --dry-run | grep -q 'Dry run' || return 1
  [[ -e $h/s/a ]] || return 1                       # dry run changed nothing
  HOME="$h" ./setup.sh --undo --yes >/dev/null || return 1
  [[ ! -e $h/s/a && ! -e $h/s/b ]] && compgen -G "$h/workstation-undo-1.sh.done-*" >/dev/null
}
check "--undo: dry run changes nothing, --yes replays and renames the file" t_undo

# --reset-shell, with a fake getent (login shell = zsh), a fake sudo (just logs), a fake id (not root)
# and a fake /etc/skel: zsh files are moved (not deleted), bash files come back, and --undo restores all.
t_reset_shell() {
  local d="$TMP/rs" h skel out
  h="$d/home"; skel="$d/skel"; mkdir -p "$h/.oh-my-zsh" "$skel" "$d/bin"
  echo omz > "$h/.oh-my-zsh/x"; echo z > "$h/.zshrc"; echo hist > "$h/.zsh_history"; echo keep > "$h/.bash_aliases"
  echo b > "$skel/.bashrc"; echo p > "$skel/.profile"
  printf '#!/bin/sh\necho "tester:x:1000:1000::/home/tester:/usr/bin/zsh"\n' > "$d/bin/getent"
  printf '#!/bin/sh\necho "$*" >> "%s/sudo.log"\n' "$d" > "$d/bin/sudo"
  # shellcheck disable=SC2016  # the fake commands must keep their $1 / $* literally
  printf '#!/bin/sh\ncase "$1" in -u) echo 1000;; -un) echo tester;; *) /usr/bin/id "$@";; esac\n' > "$d/bin/id"
  chmod +x "$d"/bin/*
  local -a e=(HOME="$h" USER=tester PATH="$d/bin:$PATH" RESET_SKEL_DIR="$skel")
  out="$(env "${e[@]}" ./setup.sh --reset-shell --dry-run 2>&1)" || return 1
  [[ $out == *'Dry run'* && -e $h/.zshrc && ! -e $h/.bashrc ]] || return 1
  env "${e[@]}" ./setup.sh --reset-shell --yes >/dev/null 2>&1 || return 1
  [[ ! -e $h/.zshrc && ! -e $h/.oh-my-zsh && -e $h/.bashrc && -e $h/.profile && -e $h/.bash_aliases ]] || return 1
  grep -q 'usermod -s /bin/bash tester' "$d/sudo.log" || return 1
  compgen -G "$h/workstation-shell-backup-*/.zshrc" >/dev/null || return 1
  env "${e[@]}" ./setup.sh --undo --yes >/dev/null 2>&1 || return 1
  [[ -e $h/.zshrc && -e $h/.oh-my-zsh/x && ! -e $h/.bashrc && -e $h/.bash_aliases ]] || return 1
  grep -q 'usermod -s /usr/bin/zsh tester' "$d/sudo.log"
}
# The release logic: which Ubuntu releases are supported (24.04 and 26.04 are; nobody has to upgrade), and which
# packages exist only on newer ones. A fake os-release stands in for /etc/os-release.
t_os_check() {
  local d="$TMP/os" bad=0 out
  mkdir -p "$d"
  case_() { # case_ ID VERSION_ID VERSION EXPECT_PROBLEM_REGEX ('' = no problem, supported)
    printf 'ID=%s\nVERSION_ID="%s"\nVERSION="%s"\nPRETTY_NAME="test"\n' "$1" "$2" "$3" > "$d/os-release"
    out="$(OS_RELEASE_FILE="$d/os-release" bash -c 'source <(head -n -1 ./setup.sh); SUPPORTED_UBUNTU="24.04 26.04"; os_check; echo "PROBLEM=$OS_PROBLEM"; echo "VERIFIED=$OS_VERIFIED"' 2>&1)"
    if [[ -z $4 ]]; then
      [[ $out == *"PROBLEM="$'\n'* && $out == *"VERIFIED=1"* ]] || { echo "$1 $2: expected supported, got: $out"; bad=1; }
    else
      grep -q -E "$4" <<<"$out" || { echo "$1 $2: expected /$4/, got: $out"; bad=1; }
    fi
  }
  case_ ubuntu 24.04 "24.04.5 LTS (Noble Numbat)" ''
  case_ ubuntu 26.04 "26.04.1 LTS (Resolute)" ''
  case_ ubuntu 22.04 "22.04.5 LTS (Jammy Jellyfish)" 'older than the oldest'
  case_ ubuntu 28.04 "28.04 LTS (Future)" 'newer than any release'
  case_ ubuntu 25.10 "25.10 (Questing Quokka)" 'not a long-term support'
  case_ debian 12 "12 (bookworm)" 'for Ubuntu'
  # packages that exist only from a newer release on
  printf 'ID=ubuntu\nVERSION_ID="24.04"\nVERSION="24.04 LTS"\n' > "$d/os-release"
  OS_RELEASE_FILE="$d/os-release" bash -c 'source <(head -n -1 ./setup.sh); source ./workstation.conf; ! pkg_applies qemu-system-riscv && pkg_applies qemu-system-misc' >/dev/null 2>&1 || { echo "24.04: qemu-system-riscv must be skipped, qemu-system-misc kept"; bad=1; }
  printf 'ID=ubuntu\nVERSION_ID="26.04"\nVERSION="26.04 LTS"\n' > "$d/os-release"
  OS_RELEASE_FILE="$d/os-release" bash -c 'source <(head -n -1 ./setup.sh); source ./workstation.conf; pkg_applies qemu-system-riscv' >/dev/null 2>&1 || { echo "26.04: qemu-system-riscv must be installed"; bad=1; }
  return $bad
}
# uv, Helix and starship: the newest upstream release wins over the archive's older package (decided by the
# user, like Node.js). The ORDER is the whole point, so it is tested with fakes: which of "release" and "archive"
# runs, what is left alone, and that a fallback after a FAILED download is reported (MISSING_FILE).
t_upstream_first() {
  local d="$TMP/uf" bad=0 out; mkdir -p "$d"
  cat > "$d/driver.sh" <<'DRV'
source <(head -n -1 ./setup.sh)
MISSING_FILE="$UF_NAME.missing"; : > "$MISSING_FILE"
CALLS=""; INSTALLED=0
have() { [[ $INSTALLED == 1 ]]; }
warn() { :; }; ok() { :; }
apt_has() { [[ $ARCHIVE_HAS == 1 ]]; }
apt_install() { CALLS+="archive "; INSTALLED=1; }
upstream() { CALLS+="release "; if [[ $UPSTREAM_OK == 1 ]]; then INSTALLED=1; return 0; fi; return 1; }
UPGRADE=0; ALLOW_CURL_INSTALLERS=1; FROM=0; ARCHIVE_HAS=1; UPSTREAM_OK=1
eval "$UF_SETUP"
install_upstream_first tool pkg upstream "$FROM" tool || true
echo "CALLS=${CALLS% } MISSING=$(wc -l < "$MISSING_FILE")"
DRV
  case_() { # case_ NAME SETUP EXPECTED_CALLS EXPECTED_MISSING_LINES
    out="$(UF_NAME="$d/$1" UF_SETUP="$2" bash "$d/driver.sh" 2>&1 | tail -n1)"
    [[ $out == "CALLS=$3 MISSING=$4" ]] || { echo "$1: expected 'CALLS=$3 MISSING=$4', got '$out'"; bad=1; }
  }
  case_ default      ''                                        'release'         0
  case_ dl-fails     'UPSTREAM_OK=0'                           'release archive' 1
  case_ dl-fails-no-archive 'UPSTREAM_OK=0; ARCHIVE_HAS=0'     'release'         0
  case_ from-archive 'FROM=1'                                  'archive'         0
  case_ from-archive-lacks 'FROM=1; ARCHIVE_HAS=0'             'release'         0
  case_ no-curl      'ALLOW_CURL_INSTALLERS=0'                 'archive'         0
  case_ installed    'INSTALLED=1'                             ''                0
  case_ upgrade      'INSTALLED=1; UPGRADE=1'                  'release'         0
  case_ upgrade-from-archive 'INSTALLED=1; UPGRADE=1; FROM=1'  ''                0
  return $bad
}
# The install functions themselves, against fake releases (a tarball made here, with scripts that print a
# version; nothing is downloaded and no real binary is run): they must install into ~/.local, record the undo
# line BEFORE failing steps, skip when the newest release is already there, and fail (non-zero) on a bad archive.
t_upstream_install() {
  local d="$TMP/ui" bad=0 out; rm -rf "$d"; mkdir -p "$d"
  cat > "$d/driver.sh" <<'DRV'
source <(head -n -1 ./setup.sh)
warn() { :; }; ok() { :; }
A="$(host_arch)"; FETCHES=0
mk() { # mk NAME VERSION: an executable that prints "<first word> <version>"
  printf '#!/bin/sh\necho "%s %s%s"\n' "$1" "$2" "${3:-}"
}
release_tag_of() { echo "$FAKE_TAG"; }
curl() { printf 'abc  lazygit_9.9.9_linux_%s.tar.gz\n' "$([[ $A == aarch64 ]] && echo arm64 || echo x86_64)"; }
helix_version() { echo "$FAKE_HX"; }
fetch_published() { FETCHES=$((FETCHES + 1)); [[ $FAKE_FAIL == 1 ]] && return 1; local t="$STATE_DIR/fake-$FETCHES"; mkdir -p "$t"
  case $1 in
    *uv-*) mkdir -p "$t/uv-$A-unknown-linux-gnu"; mk uv "${FAKE_TAG}" > "$t/uv-$A-unknown-linux-gnu/uv"; cp "$t/uv-$A-unknown-linux-gnu/uv" "$t/uv-$A-unknown-linux-gnu/uvx"; chmod +x "$t"/uv-*/uv*
       tar -czf "$2" -C "$t" "uv-$A-unknown-linux-gnu" ;;
    *rustup-init*) printf '#!/bin/sh\nif [ "$1" = --version ]; then echo "rustup-init 9.9.9 (abc)"; else mkdir -p "$HOME/.cargo/bin"; printf "#!/bin/sh\\necho rustup 9.9.9\\n" > "$HOME/.cargo/bin/rustup"; chmod +x "$HOME/.cargo/bin/rustup"; fi\n' > "$2"; chmod +x "$2" ;;
    *lazygit_*) printf '#!/bin/sh\necho "commit=abc, build date=x, build source=y, version=9.9.9, os=linux, arch=amd64, git version 2.43"\n' > "$t/lazygit"; chmod +x "$t/lazygit"; tar -czf "$2" -C "$t" lazygit ;;
    *starship*) mk starship "${FAKE_TAG#v}" > "$t/starship"; chmod +x "$t/starship"; tar -czf "$2" -C "$t" starship ;;
  esac; }
fetch_verified() { FETCHES=$((FETCHES + 1)); [[ $FAKE_FAIL == 1 ]] && return 1; local t="$STATE_DIR/fake-$FETCHES/helix-$FAKE_HX-$A-linux"; mkdir -p "$t"
  mk helix "$FAKE_HX" " (abc)" > "$t/hx"; chmod +x "$t/hx"; tar -cJf "$2" -C "$STATE_DIR/fake-$FETCHES" "helix-$FAKE_HX-$A-linux"; }
init_undo_file
rc=0; FAKE_FAIL=${FAKE_FAIL:-0}
"$FN" || rc=$?
echo "RC=$rc FETCHES=$FETCHES BIN=$([[ -x $HOME/$BIN ]] && "$HOME/$BIN" --version | head -n1 || echo none) UNDO=$(grep -vc '^#\|^set \|^$' "$UNDO_FILE" || true)"
DRV
  run_() { # run_ NAME FN BIN TAG FAIL  -> prints the driver's result line
    HOME="$d/home-$1" FN="$2" BIN="$3" FAKE_TAG="$4" FAKE_HX="99.9" FAKE_FAIL="$5" bash -c 'mkdir -p "$HOME"; bash "$0"' "$d/driver.sh" 2>&1 | tail -n1
  }
  want_() { [[ $1 == "$2" ]] || { echo "$3: expected '$2', got '$1'"; bad=1; }; }
  out="$(run_ uv uv_install_upstream .local/bin/uv 9.9.9 0)";      want_ "$out" "RC=0 FETCHES=1 BIN=uv 9.9.9 UNDO=1" "uv install"
  out="$(run_ uvx uv_install_upstream .local/bin/uv 9.9.9 1)";     want_ "$out" "RC=1 FETCHES=1 BIN=none UNDO=0" "uv download fails"
  out="$(run_ st starship_install_upstream .local/bin/starship v9.9.9 0)"; want_ "$out" "RC=0 FETCHES=1 BIN=starship 9.9.9 UNDO=1" "starship install"
  out="$(run_ stx starship_install_upstream .local/bin/starship v9.9.9 1)"; want_ "$out" "RC=1 FETCHES=1 BIN=none UNDO=0" "starship download fails"
  out="$(run_ hx helix_install_upstream .local/bin/hx 9.9.9 0)";   want_ "$out" "RC=0 FETCHES=1 BIN=helix 99.9 (abc) UNDO=2" "helix install"
  out="$(run_ hxx helix_install_upstream .local/bin/hx 9.9.9 1)";  want_ "$out" "RC=1 FETCHES=1 BIN=none UNDO=0" "helix download fails"
  out="$(run_ ru rustup_install_upstream .cargo/bin/rustup 9.9.9 0)";  want_ "$out" "RC=0 FETCHES=1 BIN=rustup 9.9.9 UNDO=1" "rustup install"
  out="$(run_ rux rustup_install_upstream .cargo/bin/rustup 9.9.9 1)"; want_ "$out" "RC=1 FETCHES=1 BIN=none UNDO=0" "rustup download fails"
  out="$(run_ lg lazygit_install_upstream .local/bin/lazygit 9.9.9 0)"; want_ "$out" "RC=0 FETCHES=1 BIN=commit=abc, build date=x, build source=y, version=9.9.9, os=linux, arch=amd64, git version 2.43 UNDO=1" "lazygit install"
  out="$(run_ lgx lazygit_install_upstream .local/bin/lazygit 9.9.9 1)"; want_ "$out" "RC=1 FETCHES=1 BIN=none UNDO=0" "lazygit download fails"
  # a second run finds the newest release already there: nothing is fetched, no second undo line
  local name fn bin tag want_prefix
  while read -r name fn bin tag; do
    out="$(HOME="$d/home-$name" FN="$fn" BIN="$bin" FAKE_TAG="$tag" FAKE_HX="99.9" FAKE_FAIL=0 bash "$d/driver.sh" 2>&1 | tail -n1)"
    # rustup is the one that must download first: it reads the version from the checksum-verified rustup-init
    # itself (there is no version file to read), then skips the install when that version is already there.
    want_prefix="RC=0 FETCHES=0"; if [[ $fn == rustup_install_upstream ]]; then want_prefix="RC=0 FETCHES=1"; fi
    [[ $out == "$want_prefix"* && $out == *"UNDO=0" ]] || { echo "$fn again: expected '$want_prefix ... UNDO=0', got '$out'"; bad=1; }
  done <<'LIST'
uv uv_install_upstream .local/bin/uv 9.9.9
st starship_install_upstream .local/bin/starship v9.9.9
hx helix_install_upstream .local/bin/hx 9.9.9
ru rustup_install_upstream .cargo/bin/rustup 9.9.9
lg lazygit_install_upstream .local/bin/lazygit 9.9.9
LIST
  return $bad
}
check "uv/Helix/starship install functions: ~/.local, undo recorded, skip when current, fail cleanly" t_upstream_install
# Earlier versions left the undo scripts, manifests, logs and the cheat sheet loose in ~: the records folder
# (OUT_DIR, ~/workstation-setup) now holds them, and migrate_records moves the old ones (never overwriting).
t_records_folder() {
  local h="$TMP/rec" bad=0 out; rm -rf "$h"; mkdir -p "$h/.bashrc.d" "$h/workstation-setup"
  : > "$h/workstation-undo-20260101-000000.sh"; : > "$h/workstation-undo-20250101-000000.sh.done-20250102-000000"
  : > "$h/workstation-manifest-20260101-000000.txt"; : > "$h/workstation-setup-20260101-000000.log"
  ln -s "$h/workstation-manifest-20260101-000000.txt" "$h/workstation-manifest-latest.txt"
  echo "mine" > "$h/WORKSTATION-CHEATSHEET.md"
  # shellcheck disable=SC2016
  printf '%s\n' 'local f="$HOME/WORKSTATION-CHEATSHEET.md"' > "$h/.bashrc.d/10-workstation.sh"   # an earlier ws-help
  echo "keep" > "$h/workstation-setup/workstation-undo-20260101-000000.sh"                 # must not be overwritten
  out="$(HOME="$h" bash -c 'source <(head -n -1 ./setup.sh); init_undo_file; migrate_records; echo DONE' 2>&1)"
  [[ $out == *DONE* ]] || { echo "migrate_records failed: $out"; return 1; }
  local f
  for f in workstation-undo-20250101-000000.sh.done-20250102-000000 workstation-manifest-20260101-000000.txt workstation-setup-20260101-000000.log WORKSTATION-CHEATSHEET.md; do
    [[ -f $h/workstation-setup/$f && ! -e $h/$f || $f == WORKSTATION-CHEATSHEET.md ]] || { echo "$f was not moved"; bad=1; }
  done
  [[ "$(cat "$h/workstation-setup/workstation-undo-20260101-000000.sh")" == keep ]] || { echo "an existing file in the records folder was overwritten"; bad=1; }
  [[ -f $h/workstation-undo-20260101-000000.sh ]] || { echo "the old undo file that would collide was not left alone"; bad=1; }
  [[ "$(cat "$h/workstation-setup/WORKSTATION-CHEATSHEET.md")" == mine ]] || { echo "the cheat sheet was not moved with its content"; bad=1; }
  [[ ! -e $h/workstation-manifest-latest.txt ]] || { echo "the dangling manifest-latest link was not removed"; bad=1; }
  # the old ws-help still looks in ~: a link is left, and only because the old file is there
  [[ -L $h/WORKSTATION-CHEATSHEET.md ]] || { echo "no compatibility link for the old ws-help"; bad=1; }
  # a clean home gets no link and no loose files
  rm -rf "$h"; mkdir -p "$h"
  HOME="$h" bash -c 'source <(head -n -1 ./setup.sh); init_undo_file; migrate_records' >/dev/null 2>&1
  [[ ! -e $h/WORKSTATION-CHEATSHEET.md ]] || { echo "a clean home must not get a link"; bad=1; }
  [[ -n "$(find "$h/workstation-setup" -maxdepth 1 -name 'workstation-undo-*.sh' 2>/dev/null | head -n1)" ]] || { echo "the undo file is not in the records folder"; bad=1; }
  return $bad
}
check "records (undo, manifest, log, cheat sheet) live in ~/workstation-setup; old loose files are moved, never overwritten" t_records_folder
# Kate's plugin set: only the [Kate Plugins] keys of Kate's session files change (everything else, including what the user
# set, stays), the files are backed up first with an undo record, and a second run changes and records nothing.
t_kate_plugins() {
  local h="$TMP/kp" bad=0 out undo; rm -rf "$h"; mkdir -p "$h/.local/share/kate/sessions"
  printf '%s\n' '[General]' 'Last Session=work' '' '[Kate Plugins]' 'katebuildplugin=false' 'mycustomkey=keepme' '' '[Plugin:lspclientplugin:]' 'AutoHover=true' > "$h/.local/share/kate/sessions/work.katesession"
  cp "$h/.local/share/kate/sessions/work.katesession" "$h/orig"
  undo="$h/undo.sh"
  run_() { KP_TS="$1" HOME="$h" bash -c 'source <(head -n -1 ./setup.sh); source ./workstation.conf; DATA_DIR="$HOME/.local/share/workstation"; TIMESTAMP=$KP_TS; UNDO_FILE="$HOME/undo.sh"; : > "$UNDO_FILE"; pgrep() { return 1; }; kate_plugins' 2>&1; }
  out="$(run_ 20260101-000000)"
  local anon="$h/.local/share/kate/anonymous.katesession" work="$h/.local/share/kate/sessions/work.katesession" k
  for k in katebuildplugin=true kategdbplugin=true lspclientplugin=true compilerexplorer=false katexmlcheckplugin=false; do
    grep -qx "$k" "$anon" || { echo "anonymous session lacks $k"; bad=1; }
    grep -qx "$k" "$work" || { echo "named session lacks $k"; bad=1; }
  done
  grep -qx 'mycustomkey=keepme' "$work" || { echo "a key the user set in [Kate Plugins] was lost"; bad=1; }
  if ! { grep -qx 'Last Session=work' "$work" && grep -qx 'AutoHover=true' "$work"; }; then echo "another group of the session file was damaged"; bad=1; fi
  # the new keys sit inside [Kate Plugins], before the next group
  awk '/^\[/ {g=$0} /^kategdbplugin=true$/ {print g}' "$work" | grep -qx '\[Kate Plugins\]' || { echo "plugin keys landed outside [Kate Plugins]"; bad=1; }
  [[ -f $h/.local/share/workstation/kate-backups/20260101-000000/work.katesession ]] || { echo "no backup of the existing session file"; bad=1; }
  cmp -s "$h/.local/share/workstation/kate-backups/20260101-000000/work.katesession" "$h/orig" || { echo "the backup is not the original"; bad=1; }
  if ! { grep -q "^cp -p .*work.katesession" "$undo" && grep -q "^rm -f .*anonymous.katesession" "$undo"; }; then echo "undo records missing: $(cat "$undo")"; bad=1; fi
  # undo really restores the original
  bash -c "$(grep '^cp -p' "$undo")"
  cmp -s "$work" "$h/orig" || { echo "the undo did not restore the original session file"; bad=1; }
  # idempotent: a second run changes nothing and records nothing
  run_ 20260101-000001 >/dev/null
  out="$(run_ 20260101-000002)"
  [[ $out == *"already set"* ]] || { echo "second run did not report 'already set': $out"; bad=1; }
  if grep -qv '^#\|^set \|^$' "$undo"; then echo "an unchanged run recorded undo commands: $(cat "$undo")"; bad=1; fi
  [[ ! -d $h/.local/share/workstation/kate-backups/20260101-000002 ]] || { echo "an unchanged run made a backup"; bad=1; }
  return $bad
}
check "Kate plugins: only the [Kate Plugins] keys change, backed up with undo, idempotent" t_kate_plugins
# ws-pyformat: Kate's Format plugin only knows autopep8 for Python; our Kate settings send that entry to this script, which must
# hand the FILE to ruff on stdin and print ruff's result (nothing else) on stdout. A fake ruff records how it was called.
t_pyformat() {
  local d="$TMP/pf" bad=0 out; rm -rf "$d"; mkdir -p "$d/bin" "$d/home"
  printf '#!/bin/sh\necho "ARGS:$*"\ncat\n' > "$d/bin/ruff"; chmod +x "$d/bin/ruff"
  printf 'x   =   1\n' > "$d/sample.py"
  out="$(HOME="$d/home" PATH="$d/bin:$PATH" files/home/.local/bin/ws-pyformat "$d/sample.py")"
  [[ $out == *"ARGS:format --quiet --stdin-filename $d/sample.py -"* ]] || { echo "ruff was called wrongly: $out"; bad=1; }
  [[ $out == *"x   =   1"* ]] || { echo "the file was not fed to ruff on stdin: $out"; bad=1; }
  if files/home/.local/bin/ws-pyformat >/dev/null 2>&1; then echo "ws-pyformat without a file must fail"; bad=1; fi
  python3 -I - files/home/.config/kate/formatting/settings.json <<'PY' || bad=1
import json, sys
c = json.load(open(sys.argv[1]))
assert c["formatOnSave"] is False and c["clang-format"]["formatOnSave"] is False, "Kate must not format on save"
assert c["autopep8"]["command"] == ["ws-pyformat"]
PY
  return $bad
}
check "Kate: format on save off, Python formatting goes through ws-pyformat (ruff on stdin)" t_pyformat
# The client half of the basedpyright self-test (files/selftest/lsp/default_level.py), against a MOCK server that behaves like
# basedpyright for the one thing that matters here: strict ("recommended") unless it was told "standard", either by
# didChangeConfiguration (Kate 23.08) or by answering its workspace/configuration request (Kate 25.12). The real server only
# runs in the self-test (CI): this proves the framing, both modes and the exit codes without running a downloaded binary.
t_lsp_default_level() {
  local d="$TMP/lsp" bad=0 rc settings='{"basedpyright": {"typeCheckingMode": "standard"}}'; rm -rf "$d"; mkdir -p "$d/bin"
  cat > "$d/mock.py" <<'PY'
import json, sys
def send(m):
    b = json.dumps(m).encode(); sys.stdout.buffer.write(b"Content-Length: %d\r\n\r\n" % len(b) + b); sys.stdout.buffer.flush()
def read():
    h = b""
    while not h.endswith(b"\r\n\r\n"):
        c = sys.stdin.buffer.read(1)
        if not c: return None
        h += c
    n = int([x for x in h.decode().split("\r\n") if x.lower().startswith("content-length")][0].split(":")[1])
    return json.loads(sys.stdin.buffer.read(n))
mode, wants_cfg, pending = "recommended", False, None
while True:
    m = read()
    if m is None: break
    if m.get("method") == "initialize":
        wants_cfg = bool(m["params"]["capabilities"].get("workspace", {}).get("configuration"))
        send({"jsonrpc": "2.0", "id": m["id"], "result": {"capabilities": {}}})
    elif m.get("method") == "workspace/didChangeConfiguration":
        mode = (m["params"]["settings"].get("basedpyright") or {}).get("typeCheckingMode", mode)
    elif m.get("method") == "textDocument/didOpen":
        uri = m["params"]["textDocument"]["uri"]
        if wants_cfg:
            pending = uri
            send({"jsonrpc": "2.0", "id": 500, "method": "workspace/configuration", "params": {"items": [{"section": "basedpyright"}]}})
        else:
            send({"jsonrpc": "2.0", "method": "textDocument/publishDiagnostics", "params": {"uri": uri, "diagnostics": [] if mode == "standard" else [{"severity": 1, "code": "reportMissingParameterType", "message": "x"}]}})
    elif m.get("id") == 500 and "result" in m:
        mode = (m["result"][0] or {}).get("typeCheckingMode", mode)
        send({"jsonrpc": "2.0", "method": "textDocument/publishDiagnostics", "params": {"uri": pending, "diagnostics": [] if mode == "standard" else [{"severity": 1, "code": "reportMissingParameterType", "message": "x"}]}})
    elif m.get("method") == "exit": break
PY
  printf '#!/bin/sh\nexec python3 -I %s\n' "$d/mock.py" > "$d/bin/basedpyright-langserver"; chmod +x "$d/bin/basedpyright-langserver"
  local mode
  for mode in didchange configuration; do
    rc=0; PATH="$d/bin:$PATH" python3 -I files/selftest/lsp/default_level.py "$mode" "$settings" >/dev/null || rc=$?
    (( rc == 0 )) || { echo "$mode with standard settings: expected quiet (exit 0), got $rc"; bad=1; }
    rc=0; PATH="$d/bin:$PATH" python3 -I files/selftest/lsp/default_level.py "$mode" '{"basedpyright": {"typeCheckingMode": "recommended"}}' >/dev/null || rc=$?
    (( rc == 1 )) || { echo "$mode with recommended settings: expected noisy (exit 1), got $rc"; bad=1; }
  done
  rc=0; PATH="$d/bin:$PATH" python3 -I files/selftest/lsp/default_level.py didchange none >/dev/null || rc=$?
  (( rc == 3 )) || { echo "control without settings: expected strict (exit 3), got $rc"; bad=1; }
  return $bad
}
check "basedpyright self-test client: both Kate ways of passing settings, noisy vs quiet, control (mock server)" t_lsp_default_level
# An older install keeps its older settings files (the setup never overwrites yours), so new defaults never reached it (the quiet basedpyright
# level, found on the real machine). migrate_user_json / migrate_helix_basedpyright add what is MISSING and nothing else, with backup and undo.
t_settings_migrate() {
  local h="$TMP/mig" bad=0 out undo="$TMP/mig/undo.sh"; rm -rf "$h"; mkdir -p "$h/.config/kate/lspclient" "$h/.config/helix"
  # an old Kate file: python entry WITHOUT settings, a server of the user's own, a value the user changed
  cat > "$h/.config/kate/lspclient/settings.json" <<'JSON'
{"servers": {"python": {"command": ["basedpyright-langserver", "--stdio"], "url": "https://example.org/mine"},
             "rust": {"command": ["my-rust-analyzer"]}}}
JSON
  cp "$h/.config/kate/lspclient/settings.json" "$h/kate.orig"
  # an old Helix file with an unrelated setting of the user's
  printf '[language-server.mine]\ncommand = "mine"\n\n[[language]]\nname = "python"\nauto-format = false\n' > "$h/.config/helix/languages.toml"
  cp "$h/.config/helix/languages.toml" "$h/helix.orig"
  run_() { HOME="$h" KM_TS="$1" KM_FILES="$REPO/files" bash -c 'source <(head -n -1 ./setup.sh); FILES="$KM_FILES"; DATA_DIR="$HOME/.local/share/workstation"; TIMESTAMP=$KM_TS; UNDO_FILE="$HOME/undo.sh"; : > "$UNDO_FILE"
    migrate_user_json "$HOME/.config/kate/lspclient/settings.json" "$FILES/home/.config/kate/lspclient/settings.json"; migrate_helix_basedpyright' 2>&1; }
  run_ 20260101-000000 >/dev/null
  python3 -I - "$h/.config/kate/lspclient/settings.json" <<'PY' || bad=1
import json, sys
s = json.load(open(sys.argv[1]))["servers"]
assert s["python"]["settings"]["basedpyright"]["typeCheckingMode"] == "standard", "the quiet level was not added"
assert s["python"]["url"] == "https://example.org/mine", "a value the user set was changed"
assert s["rust"]["command"] == ["my-rust-analyzer"], "a server of the user's own was lost"
assert "cmake" in s and "toml" in s, "missing servers were not added"
PY
  python3 -I - "$h/.config/helix/languages.toml" <<'PY' || bad=1
import sys, tomllib
c = tomllib.load(open(sys.argv[1], "rb"))
assert c["language-server"]["basedpyright"]["config"]["basedpyright"]["typeCheckingMode"] == "standard", "the Helix level was not added"
assert c["language-server"]["mine"]["command"] == "mine" and c["language"][0]["auto-format"] is False, "the user's own Helix settings were damaged"
PY
  [[ -f $h/.local/share/workstation/settings-backups/20260101-000000/.config_kate_lspclient_settings.json || -f $h/.local/share/workstation/settings-backups/20260101-000000/config_kate_lspclient_settings.json ]] \
    || [[ -n "$(find "$h/.local/share/workstation/settings-backups/20260101-000000" -name '*kate*' 2>/dev/null | head -n1)" ]] || { echo "no backup of the Kate file"; bad=1; }
  # undo restores both originals
  while IFS= read -r line; do case $line in cp\ -p*) bash -c "$line" ;; esac; done < "$undo"
  cmp -s "$h/.config/kate/lspclient/settings.json" "$h/kate.orig" || { echo "the undo did not restore the Kate file"; bad=1; }
  cmp -s "$h/.config/helix/languages.toml" "$h/helix.orig" || { echo "the undo did not restore the Helix file"; bad=1; }
  # idempotent: migrate again, then once more: the second time changes nothing and records nothing
  run_ 20260101-000001 >/dev/null
  out="$(run_ 20260101-000002)"
  if grep -qv '^#\|^set \|^$' "$undo"; then echo "an unchanged run recorded undo commands"; bad=1; fi
  # a Helix file where the user chose their own level is left alone
  printf '[language-server.basedpyright.config.basedpyright]\ntypeCheckingMode = "strict"\n' > "$h/.config/helix/languages.toml"; cp "$h/.config/helix/languages.toml" "$h/helix.strict"
  run_ 20260101-000003 >/dev/null
  cmp -s "$h/.config/helix/languages.toml" "$h/helix.strict" || { echo "a level the user chose in Helix was overwritten"; bad=1; }
  return $bad
}
check "settings of an older install: missing defaults are added, yours stay, backup + undo, idempotent" t_settings_migrate
check "uv/Helix/starship: newest upstream release first, archive only as fallback, installed tools left alone" t_upstream_first
check "Ubuntu releases: 24.04 and 26.04 supported, 22.04/non-LTS/other refused, per-release packages" t_os_check
check "--reset-shell: zsh files moved (not deleted), bash restored, login shell changed, --undo restores" t_reset_shell

t_manifest_diff() {
  printf '## Key tools\ngcc 13\n## APT packages\ngit\t1\tamd64\n' > "$TMP/ma"
  printf '## Key tools\ngcc 13\n## APT packages\ngit\t2\tamd64\n' > "$TMP/mb"
  tools/manifest-diff.sh "$TMP/ma" "$TMP/ma" >/dev/null || return 1
  ! tools/manifest-diff.sh "$TMP/ma" "$TMP/mb" >/dev/null
}
check "manifest-diff: identical = 0, different = 1" t_manifest_diff

t_published_checksum() {
  # Uses file:// URLs, so no network. A wrong published checksum must be refused
  # and must not leave the file behind; the right one must be accepted.
  local h="$TMP/h-fp"; mkdir -p "$h"
  head -n -1 setup.sh > "$LIB"
  printf 'payload\n' > "$TMP/pay.bin"
  printf '%s  pay.bin\n' "$(sha256sum "$TMP/pay.bin" | cut -d' ' -f1)" > "$TMP/good.sha"
  printf '%064d  pay.bin\n' 0 > "$TMP/bad.sha"
  HOME="$h" bash -c '
    repo=$1; lib=$2; tmp=$3
    cd "$repo"; set -- --profile work; source "$lib"; set +e
    load_config
    fetch_published "file://$tmp/pay.bin" "$tmp/ok.bin" "file://$tmp/good.sha" pay.bin >/dev/null 2>&1 || exit 10
    [[ -s $tmp/ok.bin ]] || exit 11
    fetch_published "file://$tmp/pay.bin" "$tmp/evil.bin" "file://$tmp/bad.sha" pay.bin >/dev/null 2>&1 && exit 12
    [[ ! -e $tmp/evil.bin ]] || exit 13
    # The project publishes a checksum but it cannot be fetched: refuse (no silent trust-on-first-use) ...
    FETCH_SUMS_TRIES=1 FETCH_SUMS_DELAY=0 fetch_published "file://$tmp/pay.bin" "$tmp/noverify.bin" "file://$tmp/does-not-exist.sha" pay.bin >/dev/null 2>&1 && exit 14
    [[ ! -e $tmp/noverify.bin ]] || exit 15
    # ... unless the lock file pins the SHA-256 of that download
    DOWNLOAD_SHA256["file://$tmp/pay.bin"]="$(sha256sum "$tmp/pay.bin" | cut -d" " -f1)"
    FETCH_SUMS_TRIES=1 FETCH_SUMS_DELAY=0 fetch_published "file://$tmp/pay.bin" "$tmp/pinned.bin" "file://$tmp/does-not-exist.sha" pay.bin >/dev/null 2>&1 || exit 16
    [[ -s $tmp/pinned.bin ]] || exit 17
    exit 0' _ "$REPO" "$LIB" "$TMP"
}
check "fetch_published: right checksum accepted, wrong or unreachable one refused (no silent trust-on-first-use)" t_published_checksum

t_lo_helper() {
  local x="$TMP/lo.xcu" py=modules/desktop/files/lo_update_check.py
  python3 -I "$py" check "$x" && return 1
  python3 -I "$py" set "$x" && python3 -I "$py" check "$x" && python3 -I "$py" set "$x"
  [[ "$(grep -c AutoCheckEnabled "$x")" == 1 ]]
}
check "LibreOffice settings helper: create, check, idempotent" t_lo_helper

section "Result"
printf '%s%d passed, %d failed%s\n' "$B" "$PASS" "$FAIL" "$O"
(( FAIL == 0 ))
