# shellcheck shell=bash
# ~/.bashrc.d/16-aliases.sh — installed by workstation-setup (core)
# Edit freely. setup.sh will not overwrite this file unless run with FORCE_CONFIG=1.
#
# The everyday aliases. They live in their own file, loaded AFTER 15-oh-my-bash.sh, on purpose:
# Oh My Bash (opt-in) defines its own ls/ll/la/l/grep aliases while it loads and would replace
# these (no more eza, no more icons). Files in ~/.bashrc.d load in name order: 10, 15, 16, 20.

command -v batcat  >/dev/null && alias bat='batcat'
command -v fdfind  >/dev/null && alias fd='fdfind'
command -v lazygit >/dev/null && alias lg='lazygit'
if command -v eza >/dev/null; then
  # File icons need a Nerd Font in your TERMINAL (the setup installs JetBrains Mono Nerd Font; with
  # SET_GNOME_FONT=1 it also selects it for GNOME Terminal, otherwise pick it in the terminal's
  # profile settings). Without that font the icons show as empty boxes: set WS_ICONS=0 to switch
  # them off, or WS_ICONS=1 to force them on. Default: on when the font is installed.
  _ws_icons=
  if [[ ${WS_ICONS:-auto} == 1 || ( ${WS_ICONS:-auto} == auto && -d $HOME/.local/share/fonts/JetBrainsMonoNerdFont ) ]]; then
    _ws_icons='--icons=auto'
  fi
  # shellcheck disable=SC2139  # expanding $_ws_icons at definition time is intended
  {
    alias ls="eza --group-directories-first $_ws_icons"
    alias ll="eza -l --git $_ws_icons"
    alias la="eza -la --git --group-directories-first $_ws_icons"
    alias tree="eza --tree $_ws_icons"
  }
  unset _ws_icons
fi
alias grep='grep --color=auto'
