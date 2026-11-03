# shellcheck shell=bash
# shellcheck disable=SC2034  # OSH_THEME, completions, aliases, plugins are read by oh-my-bash.sh
# ~/.bashrc.d/15-oh-my-bash.sh — installed by workstation-setup (opt-in: INSTALL_OH_MY_BASH)
# Edit freely. setup.sh will not overwrite this file unless run with FORCE_CONFIG=1.
#
# Oh My Bash, loaded from a pinned clone in ~/.local/share/oh-my-bash. Its own
# installer is deliberately NOT used: it would replace your ~/.bashrc.
# While this file exists the starship prompt (10-workstation.sh) is not started,
# because both want to own the prompt.

# No cloud: never check GitHub for updates by itself. To update on purpose,
# re-run ./setup.sh --upgrade (and --lock to pin the new commit).
export DISABLE_AUTO_UPDATE=true

export OSH="$HOME/.local/share/oh-my-bash"
OSH_THEME="font"            # see the choices:  ls ~/.local/share/oh-my-bash/themes

# Add wisely: every entry slows down shell startup.
completions=(git ssh)
aliases=(general)
plugins=(git bashmarks)

if [[ -r $OSH/oh-my-bash.sh ]]; then
  # shellcheck source=/dev/null
  source "$OSH/oh-my-bash.sh"
fi
