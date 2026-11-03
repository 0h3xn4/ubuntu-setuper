# shellcheck shell=bash
# ~/.bashrc.d/10-workstation.sh — installed by workstation-setup (core)
# Edit freely. setup.sh will not overwrite this file unless run with
# FORCE_CONFIG=1.

# --- PATH ---
for d in "$HOME/.local/bin" "$HOME/.cargo/bin"; do
  if [[ -d $d && ":$PATH:" != *":$d:"* ]]; then PATH="$d:$PATH"; fi
done
export PATH
unset d

# --- Opt out of telemetry in any tool that honors the convention ---
export DO_NOT_TRACK=1
export UV_PYTHON_DOWNLOADS=never

# --- Editor (Helix may be installed as hx or helix) ---
for c in hx helix; do
  if command -v "$c" >/dev/null; then
    export EDITOR="$c" VISUAL="$c"
    # shellcheck disable=SC2139  # expanding $c at definition time is intended
    [[ $c != hx ]] && alias hx="$c"
    break
  fi
done
unset c

# --- History: large, deduplicated, written immediately ---
HISTSIZE=100000
HISTFILESIZE=200000
HISTCONTROL=ignoreboth:erasedups
HISTTIMEFORMAT='%F %T  '
shopt -s histappend
PROMPT_COMMAND="history -a${PROMPT_COMMAND:+; $PROMPT_COMMAND}"

# --- Shell behavior ---
shopt -s autocd cdspell globstar checkwinsize

# --- Better tools under familiar names ---
command -v batcat  >/dev/null && alias bat='batcat'
command -v fdfind  >/dev/null && alias fd='fdfind'
command -v lazygit >/dev/null && alias lg='lazygit'
if command -v eza >/dev/null; then
  alias ls='eza --group-directories-first'
  alias ll='eza -la --git --group-directories-first'
  alias tree='eza --tree'
fi
alias grep='grep --color=auto'

# --- Build defaults ---
# Every CMake project writes compile_commands.json, so clangd understands it.
export CMAKE_EXPORT_COMPILE_COMMANDS=ON
# CMAKE_GENERATOR=Ninja is deliberately NOT set globally: some projects
# (e.g. ones with a top-level Makefile wrapper) expect Make-based build trees.
# Uncomment for faster rebuilds via ccache:
# export CMAKE_C_COMPILER_LAUNCHER=ccache CMAKE_CXX_COMPILER_LAUNCHER=ccache

# --- Integrations ---
if command -v fzf >/dev/null; then
  if fzf --bash >/dev/null 2>&1; then
    eval "$(fzf --bash)"        # Ctrl-R history, Ctrl-T files, Alt-C dirs
  elif [[ -r /usr/share/doc/fzf/examples/key-bindings.bash ]]; then
    # shellcheck source=/dev/null
    . /usr/share/doc/fzf/examples/key-bindings.bash
  fi
fi
command -v zoxide   >/dev/null && eval "$(zoxide init bash)"   # z <part-of-dir>
command -v direnv   >/dev/null && eval "$(direnv hook bash)"
command -v starship >/dev/null && eval "$(starship init bash)"

# --- Offline documentation (installed locally, no internet needed) ---
_opendoc() {
  local f
  for f in "$@"; do
    if [[ -r $f ]]; then xdg-open "$f" >/dev/null 2>&1 & return 0; fi
  done
  echo "Documentation not found. Is the package installed?"; return 1
}
cppref()    { _opendoc /usr/share/cppreference/doc/html/en/index.html /usr/share/cppreference/doc/html/index.html; }
pydocs()    { _opendoc /usr/share/doc/python3/html/index.html /usr/share/doc/python3.*/html/index.html; }
cmakedocs() { _opendoc /usr/share/doc/cmake-data/html/index.html /usr/share/doc/cmake/html/index.html; }
rustdocs()  { rustup doc --std; }
# Also offline:  man 3 printf (C library), man 3posix pthread_create (POSIX),
#                tldr <command> (examples), info gdb (GDB manual)

# Show the workstation cheat sheet (works offline).
ws-help() {
  local f="$HOME/WORKSTATION-CHEATSHEET.md"
  [[ -r $f ]] || { echo "Cheat sheet not found: $f"; return 1; }
  if command -v batcat >/dev/null; then
    batcat --paging=always --language=md "$f"
  else
    less "$f"
  fi
}
