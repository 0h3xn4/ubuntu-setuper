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
    exit 0' _ "$REPO" "$LIB" "$TMP"
}
check "fetch_published accepts the right checksum and refuses a wrong one" t_published_checksum

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
