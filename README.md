# workstation-setup: manual setup guide

A step-by-step guide to set up a development workstation on the **latest
Ubuntu LTS release**, by hand, without running any setup script. It does
exactly what `setup.sh` in this repository does, in the same order, so you
can read, understand and control every change from start to finish. If you
would rather automate it, see [Automated route](#automated-route) at the end.

What you get: C/C++/Rust/Python toolchains, the Helix editor with language
servers, git tooling, static analysis, offline documentation and a
comfortable bash. Two optional parts: the **embedded** part (ARM and RISC-V
cross compilers, QEMU, debug probes, serial and CAN tools, verification
tools) and the **desktop** part (everyday apps with their background
network features switched off). **No installed tool contacts the internet by
itself after installation.**

## Contents

- [Rules this guide follows](#rules-this-guide-follows)
- [How to use this guide](#how-to-use-this-guide)
- [Part A. Preparation](#part-a-preparation): A1 check the system, A2 helpers, A3 package lists, A4 (no system upgrade), A5 tuning, A6 privacy
- [Part B. Core](#part-b-core-always): B1 CLI tools ... B13 desktop settings
- [Part C. Optional parts](#part-c-optional-parts): C1 embedded, C2 desktop
- [Part D. Offline caches and lock-down](#part-d-offline-caches-and-lock-down)
- [Part E. Verify](#part-e-verify)
- [Part F. Record, pin and undo](#part-f-record-pin-and-undo)
- [Automated route](#automated-route)

## Rules this guide follows

These are the rules the script enforces. Follow them by hand and your
machine ends up in the same state.

1. **No cloud.** Downloading *while you set up* is fine. Afterwards no tool
   contacts external services: no telemetry, update checks, online lookups
   or implicit downloads. Cloud-connected tools (`gh`, snaps, schema-fetching
   JSON/YAML language servers) are never installed. For apps that are
   networked by nature (browser, mail): traffic *you* direct to a
   destination *you* chose is fine; anything automatic or in the background
   is not.
2. **Don't break Ubuntu.**
   - Every `apt-get install` uses `--no-remove` (if APT wants to uninstall
     something to resolve a conflict, it aborts instead) and `--no-upgrade`
     (packages that are already installed are not upgraded). This guide
     never runs `apt upgrade`: keeping the system up to date is Ubuntu's own
     business (Software Updater, unattended-upgrades), not part of this setup.
   - Never edit a file that belongs to a package (it would cause conffile
     prompts that block unattended security updates). Add *new* files
     (drop-ins) instead, and never overwrite an existing one.
   - Disable services, never mask them. Do not touch kernel, boot,
     coreutils or APT sources.
3. **Everything reversible.** Each section ends with an **Undo** line. The
   helpers in A2 also append the undo commands for the files you create to
   `~/workstation-undo.sh`.
4. **Latest stable, long-term-supported versions.** Latest Ubuntu LTS; for
   software with an LTS line the newest LTS; otherwise the newest stable
   release. Never betas, release candidates or nightlies.
5. **Verify what you download outside APT.** Download to a file, look at it
   (installer scripts are text: read them), record its SHA-256, and only
   then run it. See [A2](#a2-helpers).

## How to use this guide

- Run everything as your **normal user**. `sudo` appears only where shown.
- Open a terminal in the root of this repository (the folder with this
  README). Several steps copy files from it into your home directory.
- Commands are meant to be pasted a block at a time, in order. Each section
  names the script step it mirrors, e.g. *mirrors `step "Base CLI tools"`,
  function `base_cli` in `setup.sh`*, so you can read the code next to the
  text.
- **Which parts do I do?** Parts A, B, D and E are the core and are
  always done. Part C is optional: C1 is the **work** profile (embedded and
  flight-software tooling), C2 is the **personal** profile (everyday
  desktop apps). Do either, both or neither. Inside a section, lines marked
  *(optional)* correspond to a switch in `workstation.conf`.
- Some tools may be absent from your Ubuntu release's archive. The
  `apt_install` helper in A2 skips and tells you about missing packages,
  like the script does.
- Do the steps in order. In particular, **D4 (lock-down) comes last** on
  purpose: it makes your shell refuse downloads, which would break the
  downloads in the earlier steps.

---

# Part A. Preparation

## A1. Check the system

*Mirrors `os_check` / `preflight`.*

```bash
. /etc/os-release
echo "$PRETTY_NAME"      # must be Ubuntu
echo "$VERSION"          # must contain "LTS"
uname -m                 # x86_64 expected; other architectures lack some packages
```

You need an Ubuntu **LTS** release, and it should be the **latest** LTS.
After A3 installs `distro-info` you can check this offline:

```bash
ubuntu-distro-info --lts           # codename of the latest LTS
echo "$VERSION_CODENAME"           # yours: the two must be equal
```

If yours is older, upgrade first (`sudo do-release-upgrade`; LTS-to-LTS
upgrades are offered once the new release's first point release is out).
Also make sure you can use `sudo`, and run this guide from a logged-in
desktop session (A6 and B13 change GNOME settings).

## A2. Helpers

*Mirrors the helper functions in `setup.sh`: `apt_install`, `write_config`/
`install_file`, `install_system_file`, `fetch_verified`, `record_undo`.*

Save these helpers in a file and load them in **every terminal** you use for
this guide. They are small enough to read in a minute.

```bash
cat > ~/ws-manual-helpers.sh <<'EOF'
# Source this file:  . ~/ws-manual-helpers.sh   (run from the repository root first: export WS=$PWD)
export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$PATH"
WS="${WS:-$PWD}"
UNDO="$HOME/workstation-undo.sh"
[ -e "$UNDO" ] || { printf '#!/usr/bin/env bash\n# Undo commands, newest last. REVIEW before running; run lines in reverse order.\n' > "$UNDO"; chmod +x "$UNDO"; }
record_undo() { printf '%s\n' "$*" >> "$UNDO"; }

# apt_install PKG...  installs what exists in the archive, skips the rest. Never removes packages.
apt_install() {
  local ok=() p
  for p in "$@"; do
    if apt-cache policy "$p" 2>/dev/null | grep -q 'Candidate: [^(]'; then ok+=("$p")
    else echo "not in archive, skipping: $p"; fi
  done
  if [ "${#ok[@]}" -gt 0 ]; then
    sudo env DEBIAN_FRONTEND=noninteractive apt-get install -y --no-remove --no-upgrade "${ok[@]}"
  fi
}

# put SOURCE DEST [MODE]  copies a file into place. NEVER overwrites an existing file.
put() {
  local src=$1 dest=$2 mode=${3:-644}
  mkdir -p "$(dirname "$dest")"
  if [ -e "$dest" ]; then
    if cmp -s "$src" "$dest"; then echo "unchanged: $dest"; else echo "EXISTS, kept (yours differs): $dest"; fi
    return 0
  fi
  cp "$src" "$dest" && chmod "$mode" "$dest" && echo "wrote: $dest" && record_undo "rm -f '$dest'"
}

# put_system SOURCE DEST  installs a NEW file as root (e.g. below /etc). NEVER overwrites.
put_system() {
  local src=$1 dest=$2
  if [ -e "$dest" ]; then echo "exists, left untouched: $dest"; return 0; fi
  sudo install -D -m 644 "$src" "$dest" && echo "installed: $dest" && record_undo "sudo rm -f '$dest'"
}

# download URL FILE  downloads, prints the SHA-256 and records it. Look at the file, then run it.
download() {
  curl -fsSL --retry 3 --connect-timeout 20 "$1" -o "$2" || return 1
  mkdir -p ~/.local/share/workstation
  sha256sum "$2" | tee -a ~/.local/share/workstation/download-hashes.txt
  echo "$1" >> ~/.local/share/workstation/download-hashes.txt
}

# git_set KEY VALUE  sets a global git option only if it is not set yet.
git_set() {
  git config --global --get "$1" >/dev/null && return 0
  git config --global "$1" "$2" && record_undo "git config --global --unset $1"
}
EOF
export WS="$PWD"
. ~/ws-manual-helpers.sh
```

Notes:

- `apt_install` is the only way this guide installs from APT. `--no-remove`
  means APT may never uninstall anything, `--no-upgrade` means it does not
  upgrade packages you already have.
- `put` never overwrites. If you already have, say, a `~/.inputrc`, you keep
  it and `put` tells you; merge by hand if you want the new settings.
- `download` records the SHA-256 of what you downloaded. Compare it with the
  publisher's value if your process requires it; keep
  `~/.local/share/workstation/download-hashes.txt` as your record.
- `ws-manual-helpers.sh` and `workstation-undo.sh` are your own records;
  keep them.

## A3. Package lists and prerequisites

*Mirrors `preflight` (the `apt-get update` and prerequisites part).*

```bash
sudo apt-get update
apt_install curl ca-certificates gnupg distro-info
```

Undo: nothing (these are tiny and usually present already).

## A4. System upgrade: deliberately not part of this guide

Nothing to do here. An earlier version of the script ran `apt-get upgrade`
at this point; it no longer does, because upgrading every installed package
changes the machine far beyond "install what I asked for". Keep the system
current the way you normally do (Software Updater, `unattended-upgrades`,
or `sudo apt upgrade` when *you* decide to).

Installing the packages below may still pull in newer versions of libraries
they depend on; that is how APT resolves dependencies and cannot be avoided.
`apt_install` only prevents upgrades of packages that are already installed
and merely named. To see what an install would change before doing it:
`apt-get install -s --no-remove --no-upgrade <packages>`.

## A5. System tuning

*Mirrors `step "System tuning"`, function `system_tuning`.*

Large source trees (clangd, rust-analyzer, file watchers) need more inotify
watches. This is a **new** drop-in file; nothing existing is modified.

```bash
f=/etc/sysctl.d/60-dev-inotify.conf
if [ ! -e "$f" ]; then
  printf 'fs.inotify.max_user_watches = 524288\nfs.inotify.max_user_instances = 1024\n' | sudo tee "$f" >/dev/null
  sudo sysctl -p "$f"
  record_undo "sudo rm -f $f"
fi
```

Undo: `sudo rm -f /etc/sysctl.d/60-dev-inotify.conf`.

## A6. Privacy hardening at OS level

*Mirrors `step "Privacy hardening"`, function `privacy_hardening`
(switch `HARDEN_PRIVACY`). Skip the whole section to keep Ubuntu's defaults.*

Only services are **disabled** (not masked, not removed) and new drop-in
files are added, so updates keep working.

```bash
# Crash/problem reporting, kernel oops reports, MOTD news, firmware refresh timer
for u in apport.service apport-autoreport.path apport-autoreport.timer \
         whoopsie.service whoopsie.path kerneloops.service \
         motd-news.timer fwupd-refresh.timer; do
  if [ "$(systemctl is-enabled "$u" 2>/dev/null)" = enabled ]; then
    sudo systemctl disable --now "$u" && record_undo "sudo systemctl enable --now $u"
  fi
done

# APT news (messages fetched from Canonical when you run apt)
if command -v pro >/dev/null && sudo pro config set apt_news=false; then
  record_undo "sudo pro config set apt_news=true"
fi

# NetworkManager's periodic connectivity probe: new drop-in file
f=/etc/NetworkManager/conf.d/99-no-connectivity-check.conf
if [ -d /etc/NetworkManager/conf.d ] && [ ! -e "$f" ]; then
  printf '[connectivity]\nenabled=false\n' | sudo tee "$f" >/dev/null
  sudo systemctl reload NetworkManager
  record_undo "sudo rm -f $f && sudo systemctl reload NetworkManager"
fi
```

GNOME-level privacy settings (location, automatic time zone, problem
reports, web search in the Activities overview) are in [B13](#b13-desktop-gnome-settings).

Undo: the `record_undo` lines above; the commands are in `~/workstation-undo.sh`.

---

# Part B. Core (always)

## B1. Base command-line tools

*Mirrors `step "Base CLI tools"`, function `base_cli`.*

```bash
apt_install \
  git git-lfs wget unzip zip p7zip-full xz-utils zstd rsync tree file \
  distro-info htop btop jq yq ripgrep fd-find bat eza zoxide fzf direnv \
  tealdeer hyperfine entr just tmux bash-completion shellcheck shfmt \
  yamllint git-delta lazygit moreutils pv ncdu libxml2-utils \
  fonts-jetbrains-mono
```

`gh`/`glab` are deliberately **not** in the list: they talk to cloud forges.
(On Ubuntu `bat` runs as `batcat` and `fd-find` as `fdfind`; the shell
setup in B10 adds the familiar aliases.)

`tealdeer` provides `tldr`. Fetch its example pages **once** now and turn
automatic updates off:

```bash
put "$WS/files/home/.config/tealdeer/config.toml" ~/.config/tealdeer/config.toml
tldr --update          # the only time it downloads
```

Undo: the `rm` lines from `put`; packages via `apt` history (see [Undo](#undo)).

## B2. C/C++ toolchain *(optional: `INSTALL_CPP`)*

*Mirrors `step "C/C++ toolchain"`, function `cpp_toolchain`.*

```bash
apt_install \
  build-essential cmake cmake-curses-gui ninja-build meson pkg-config \
  ccache mold gdb clang clangd clang-format clang-tidy clang-tools lld \
  llvm lldb valgrind cppcheck iwyu bear lcov gcovr strace ltrace \
  linux-tools-common linux-tools-generic libgtest-dev libgmock-dev \
  cpputest catch2 doxygen graphviz pandoc
put "$WS/files/home/.gdbinit" ~/.gdbinit
```

## B3. GUI tools *(optional: `INSTALL_GUI_TOOLS`)*

*Mirrors `step "GUI tools"`, function `gui_tools`.*

```bash
apt_install meld
```

## B4. Python tools *(optional: `INSTALL_PYTHON`)*

*Mirrors `step "Python tools"`, functions `python_tools`, `ensure_uv`,
`uv_tool_install`.*

```bash
apt_install python3-dev python3-venv
```

**uv** (fast Python package/tool manager). Prefer the Ubuntu archive:

```bash
command -v uv || apt_install uv
```

If `uv` is still missing, use the official installer. Download it, **read
it**, note its SHA-256, then run it. `UV_NO_MODIFY_PATH=1` stops it editing
your shell startup files (B10 handles PATH).

```bash
command -v uv || {
  download https://astral.sh/uv/install.sh /tmp/uv-install.sh
  less /tmp/uv-install.sh
  UV_NO_MODIFY_PATH=1 sh /tmp/uv-install.sh
  record_undo "rm -f ~/.local/bin/uv ~/.local/bin/uvx"
}
```

Never let uv download Python interpreters on its own (the system Python is
used):

```bash
put "$WS/files/home/.config/uv/uv.toml" ~/.config/uv/uv.toml
export UV_PYTHON_DOWNLOADS=never
```

Python developer tools (linter/formatter, type checker and language
server, pre-commit and its hooks, CMake language server):

```bash
for t in ruff basedpyright pre-commit pre-commit-hooks cmake-language-server; do
  uv tool install "$t"
done
```

To reinstall an exact version later: `uv tool install --reinstall "ruff==X.Y.Z"`.

Undo: `uv tool uninstall <name>` for each tool; `rm -f ~/.local/bin/uv ~/.local/bin/uvx`.

## B5. Rust toolchain *(optional: `INSTALL_RUST`)*

*Mirrors `step "Rust toolchain"`, function `rust_toolchain`.*

**rustup**: from the archive if available, else the official installer
(download, read, record checksum, run). `--default-toolchain none`
installs only rustup itself; `--no-modify-path` leaves your shell files alone.

```bash
command -v rustup || apt_install rustup
command -v rustup || {
  download https://sh.rustup.rs /tmp/rustup-init.sh
  less /tmp/rustup-init.sh
  sh /tmp/rustup-init.sh -y --no-modify-path --default-toolchain none
  record_undo "rustup self uninstall -y"
}

# no automatic self-update of rustup
rustup set auto-self-update disable && record_undo "rustup set auto-self-update enable"

# newest stable release (Rust has no LTS line) and the components used by the editor/CI
rustup toolchain install stable --profile default
rustup default stable
rustup component add rust-analyzer rust-src llvm-tools rust-docs
```

*(optional: `INSTALL_CARGO_TOOLS`)* Cargo tools are compiled from source and
take several minutes. They need a few development libraries:

```bash
apt_install libssl-dev pkg-config
cargo install --locked taplo-cli
```

`--locked` makes cargo use the exact dependency versions the tool's authors
tested. Pin a tool with `cargo install --locked taplo-cli@X.Y.Z`.

Undo: `cargo uninstall <name>`; `rustup self uninstall`.

## B6. Offline documentation *(optional: `INSTALL_OFFLINE_DOCS`)*

*Mirrors `step "Offline documentation"`, function `offline_docs`.*

```bash
apt_install \
  cppreference-doc-en-html python3-doc cmake-doc manpages-dev \
  manpages-posix manpages-posix-dev glibc-doc gdb-doc
sudo mandb -q
```

You now have, without internet: C/C++ reference (cppreference), Python,
CMake, POSIX and glibc manuals (`man 3 printf`, `man 3posix pthread_create`),
the GDB manual (`info gdb`) and, via rustup, the Rust docs (`rustup doc`).

## B7. Bash language server *(optional: `INSTALL_BASH_LSP`)*

*Mirrors `step "Bash language server"`, function `bash_lsp`.*

Installed with npm into your home directory (no root). npm is told not to
contact the registry for update notices, funding messages or audits.

```bash
apt_install nodejs npm
npm config set prefix "$HOME/.local"
npm config set update-notifier false
npm config set fund false
npm config set audit false
record_undo "npm config delete prefix; npm config delete update-notifier; npm config delete fund; npm config delete audit"
npm install -g bash-language-server
```

Undo: `npm rm -g <name>` and the `npm config delete ...` line.

## B8. Helix editor *(optional: `INSTALL_HELIX`)*

*Mirrors `step "Helix editor"`, function `helix_setup`.*

Never from a snap (snapd auto-refreshes from the online Snap Store). Use
the archive if it has Helix:

```bash
command -v hx || command -v helix || apt_install helix
```

Otherwise install the newest **stable** release from the project's
GitHub releases page (`https://github.com/helix-editor/helix/releases`,
the one marked "Latest", never a pre-release). Replace `VERSION` with the
tag, e.g. the one shown on that page:

```bash
VERSION=...        # the tag of the latest stable release
command -v hx || command -v helix || {
  name="helix-${VERSION}-x86_64-linux"
  download "https://github.com/helix-editor/helix/releases/download/${VERSION}/${name}.tar.xz" /tmp/helix.tar.xz
  mkdir -p ~/.local/opt ~/.local/bin
  tar -xJf /tmp/helix.tar.xz -C ~/.local/opt
  ln -sf ~/.local/opt/"$name"/hx ~/.local/bin/hx     # hx finds its 'runtime' directory next to the real binary
  record_undo "rm -rf ~/.local/opt/$name ~/.local/bin/hx"
}
```

Configuration. `languages.toml` does two important things: it disables the
JSON and YAML language servers (their defaults download schemas from the
internet; highlighting still works, validate with `jq`/`yamllint`), and it
stops C/C++ auto-formatting on save so legacy code does not produce huge
diffs.

```bash
put "$WS/files/home/.config/helix/config.toml"    ~/.config/helix/config.toml
put "$WS/files/home/.config/helix/languages.toml" ~/.config/helix/languages.toml
hx --health            # shows which language servers are found
```

## B9. Containers *(optional: `INSTALL_PODMAN`, `INSTALL_DOCKER`)*

*Mirrors `step "Containers"`, function `containers`.*

```bash
apt_install podman distrobox
```

*(optional, off by default: `INSTALL_DOCKER`)* Docker Engine rewrites
firewall rules, which can interfere with VPNs, and the `docker` group is
equivalent to root. Only if you really need it:

```bash
apt_install docker.io docker-compose-v2 docker-buildx
sudo usermod -aG docker "$USER" && record_undo "sudo gpasswd -d $USER docker"
```

Images and the "never pull implicitly" setting come later, in
[D3](#d3-container-images-and-pull-policy).

## B10. Shell (bash)

*Mirrors `step "Shell (bash) setup"`, function `shell_setup`.*

**Loader.** A small block in `~/.bashrc` that sources `~/.bashrc.d/*.sh`.
This is the only edit to a file that Ubuntu created for you (your own
`~/.bashrc`, not a package-owned file under `/etc`).

```bash
mkdir -p ~/.bashrc.d
if ! grep -q 'bashrc.d' ~/.bashrc; then
  cat >> ~/.bashrc <<'EOF'

# >>> workstation-setup: load ~/.bashrc.d/*.sh >>>
if [ -d "$HOME/.bashrc.d" ]; then
  for f in "$HOME"/.bashrc.d/*.sh; do [ -r "$f" ] && . "$f"; done
  unset f
fi
# <<< workstation-setup <<<
EOF
  record_undo "sed -i '/# >>> workstation-setup/,/# <<< workstation-setup <<</d' ~/.bashrc"
fi
```

**Files.** `10-workstation.sh` sets PATH, history, aliases, `fzf`/`zoxide`/
`direnv`/`starship` integration, the offline-documentation shortcuts
(`cppref`, `pydocs`, ...) and `ws-help`. `.inputrc` adds history search on
the arrow keys. `ws-init` copies project starter files (B12). Read them
before installing.

```bash
less "$WS/files/home/.bashrc.d/10-workstation.sh"
put "$WS/files/home/.bashrc.d/10-workstation.sh" ~/.bashrc.d/10-workstation.sh
put "$WS/files/home/.inputrc"                    ~/.inputrc
put "$WS/files/home/.local/bin/ws-init"          ~/.local/bin/ws-init 755
```

(`20-offline.sh`, the runtime no-cloud lock, is installed last, in
[D4](#d4-enforce-the-offline-environment).)

**Prompt (starship)** *(optional: `INSTALL_STARSHIP`)*. Archive first,
otherwise the official installer (download, read, record checksum, run):

```bash
command -v starship || apt_install starship
command -v starship || {
  download https://starship.rs/install.sh /tmp/starship-install.sh
  less /tmp/starship-install.sh
  sh /tmp/starship-install.sh -y -b ~/.local/bin
  record_undo "rm -f ~/.local/bin/starship"
}
# plain-text symbols: no special "Nerd Font" needed
if command -v starship >/dev/null && [ ! -e ~/.config/starship.toml ]; then
  starship preset plain-text-symbols -o ~/.config/starship.toml && record_undo "rm -f ~/.config/starship.toml"
fi
```

**Cheat sheet.** `ws-help` shows `~/WORKSTATION-CHEATSHEET.md`. It is
assembled from the core part, one part for each optional part you install
(C1/C2), and the maintenance part. Do this now for the core and **repeat
it after C1/C2** with their parts added (the commented lines):

```bash
{
  cat "$WS/files/cheatsheet/00-core.md"
  # echo; cat "$WS/modules/embedded/files/cheatsheet.md"    # after C1
  # echo; cat "$WS/modules/desktop/files/cheatsheet.md"     # after C2
  echo; cat "$WS/files/cheatsheet/99-maintenance.md"
} > ~/WORKSTATION-CHEATSHEET.md
```

(The maintenance part describes `setup.sh` commands; they are optional for
you. See [Part F](#part-f-record-pin-and-undo) for the manual equivalents.)

## B11. Git

*Mirrors `step "Git setup"`, function `git_setup`.*

Sets sensible defaults **only where you have not set a value yourself**,
and the helpers record how to undo each one.

```bash
git_set init.defaultBranch main
git_set pull.rebase true
git_set rerere.enabled true
git_set fetch.prune true
git_set push.autoSetupRemote true
git_set merge.conflictStyle zdiff3
git_set diff.colorMoved default
if command -v delta >/dev/null; then
  git_set core.pager delta
  git_set interactive.diffFilter "delta --color-only"
  git_set delta.navigate true
  git_set delta.line-numbers true
fi
command -v git-lfs >/dev/null && git lfs install --skip-repo
# your identity, if not set yet:
#   git config --global user.name  "Your Name"
#   git config --global user.email "you@example.org"
```

`lazygit` checks GitHub for new versions by default. Turn that off:

```bash
put "$WS/files/home/.config/lazygit/config.yml" ~/.config/lazygit/config.yml
```

## B12. Project starter files

*Mirrors `step "Project templates"`, function `project_templates`, and the
`ws-init` script.*

These are reference copies that `ws-init` copies into your projects
(`.editorconfig`, `.clang-format`, `.clang-tidy`, `.clangd`, an
**offline-only** pre-commit config, `ruff.toml`, host CMake presets). They
live in `~/.local/share/workstation/templates/generic/`:

```bash
mkdir -p ~/.local/share/workstation/templates
cp -r "$WS/files/templates/." ~/.local/share/workstation/templates/generic/   # refreshing is safe: these are copies
record_undo "rm -rf ~/.local/share/workstation/templates"
```

Use in a project: `cd my-project && ws-init && pre-commit install`.
`ws-init` never overwrites an existing file; `ws-init --list` shows which
starter-file sets are installed.

## B13. Desktop (GNOME) settings

*Mirrors `step "Desktop settings"`, function `desktop_tweaks`. Needs a
logged-in GNOME session. Each `gset` prints and records the previous value.*

```bash
gset() {   # gset SCHEMA KEY VALUE
  local old; old="$(gsettings get "$1" "$2")" || return 0
  gsettings set "$1" "$2" "$3" && record_undo "gsettings set $1 $2 $(printf %q "$old")"
}
# Ubuntu's default monospace font is small; the terminal follows this setting
gset org.gnome.desktop.interface monospace-font-name 'JetBrains Mono 11'
# privacy (skip this block to keep GNOME's defaults; switch HARDEN_PRIVACY)
gset org.gnome.system.location enabled false
gset org.gnome.desktop.datetime automatic-timezone false
gset org.gnome.desktop.privacy report-technical-problems false
gset org.gnome.desktop.privacy send-software-usage-stats false
# no web / Snap Store search in the Activities overview (installed apps still found)
gset org.gnome.desktop.search-providers disable-external true
```

Leave **GNOME Online Accounts** (Settings > Online Accounts) empty. Accounts
there (Google, Microsoft, Nextcloud, ...) sync in the background.

---

# Part C. Optional parts

## C1. Embedded part (work profile)

*Mirrors the `embedded` module, `modules/embedded/module.sh` and
`module.conf`, step by step: `step "Embedded toolchain"`, `step "Wireshark"`,
`step "Verification tools"`, `step "Embedded GUI tools"`,
`step "Embedded helpers and templates"`, `step "SPICE generic kernels"`.*

**Toolchains, emulators, probes, serial and CAN tools:**

```bash
apt_install \
  gcc-arm-none-eabi binutils-arm-none-eabi libnewlib-arm-none-eabi \
  libstdc++-arm-none-eabi-newlib gcc-riscv64-unknown-elf \
  picolibc-riscv64-unknown-elf gdb-multiarch openocd stlink-tools \
  dfu-util srecord can-utils sigrok-cli qemu-system-arm qemu-system-misc \
  qemu-system-sparc qemu-user-static qemu-utils tio picocom minicom \
  libudev-dev
```

Serial ports and USB debug probes without `sudo` need two groups. They take
effect at your next login:

```bash
for g in dialout plugdev; do
  getent group "$g" >/dev/null || continue
  id -nG "$USER" | grep -qw "$g" && continue
  sudo usermod -aG "$g" "$USER" && record_undo "sudo gpasswd -d $USER $g"
done
```

**Wireshark** *(optional: `INSTALL_WIRESHARK`)*, with capture for members of
the `wireshark` group instead of root:

```bash
echo "wireshark-common wireshark-common/install-setuid boolean true" | sudo debconf-set-selections
apt_install wireshark
sudo env DEBIAN_FRONTEND=noninteractive dpkg-reconfigure -f noninteractive wireshark-common
record_undo "sudo dpkg-reconfigure wireshark-common   # answer 'No' to disallow non-root capture"
sudo usermod -aG wireshark "$USER" && record_undo "sudo gpasswd -d $USER wireshark"
```

**Verification tools** *(optional: `INSTALL_VERIFICATION`)*:

```bash
apt_install cbmc flawfinder afl++
for t in lizard codespell; do uv tool install "$t"; done
# (optional, large: INSTALL_FRAMA_C)   apt_install frama-c
# (optional: INSTALL_FPRIME_BOOTSTRAP) uv tool install fprime-bootstrap
```

**Logic analyzer GUI** *(optional: `INSTALL_GUI_TOOLS`)*: `apt_install pulseview`

**Rust for bare-metal targets and probes** (needs B5 and the libraries
installed above):

```bash
rustup target add thumbv6m-none-eabi thumbv7m-none-eabi thumbv7em-none-eabihf riscv32imac-unknown-none-elf
cargo install --locked cargo-binutils flip-link probe-rs-tools        # compiles; slow (INSTALL_CARGO_TOOLS)
```

**Helpers and starter files.** `30-embedded.sh` adds `serial` and `vcan-up`.
`ws-devname` gives USB serial adapters stable names (`/dev/ws/<name>`) by
writing a udev rule (it validates the device strings before doing so, because
they end up in a root-owned file).

```bash
put "$WS/modules/embedded/files/home/.bashrc.d/30-embedded.sh" ~/.bashrc.d/30-embedded.sh
put "$WS/modules/embedded/files/home/.local/bin/ws-devname"    ~/.local/bin/ws-devname 755
mkdir -p ~/.local/share/workstation/templates/embedded
cp -r "$WS/modules/embedded/files/templates/." ~/.local/share/workstation/templates/embedded/
```

Use in a project: `ws-init --embedded` (generic files plus CMake cross
toolchain files and ARM/RISC-V presets).

Re-do the cheat sheet command in B10 with the `embedded` line enabled.

**SPICE generic kernels** *(optional: `INSTALL_SPICE_KERNELS`, about 35 MB)*:

```bash
base=https://naif.jpl.nasa.gov/pub/naif/generic_kernels
dir=~/.local/share/workstation/spice; mkdir -p "$dir"
for f in lsk/naif0012.tls pck/pck00011.tpc pck/gm_de440.tpc spk/planets/de440s.bsp; do
  [ -s "$dir/${f##*/}" ] || download "$base/$f" "$dir/${f##*/}"
done
cat > "$dir/generic.tm" <<EOF
KPL/MK
Generic SPICE kernels.
Python:  import spiceypy; spiceypy.furnsh("$dir/generic.tm")

\begindata
  PATH_VALUES     = ( '$dir' )
  PATH_SYMBOLS    = ( 'K' )
  KERNELS_TO_LOAD = ( '\$K/naif0012.tls'
                      '\$K/pck00011.tpc'
                      '\$K/gm_de440.tpc'
                      '\$K/de440s.bsp' )
\begintext
EOF
```

**OpenOCD** listens on *all* network interfaces by default (ports 3333,
4444, 6666). Always start it with `-c "bindto 127.0.0.1"` (see the cheat
sheet).

## C2. Desktop part (personal profile)

*Mirrors the `desktop` module, `modules/desktop/module.sh` and `module.conf`,
step by step: `step "Desktop apps"`, `step "Desktop languages"`,
`step "Desktop app settings (no network)"`, `step "Browser and mail policies"`.*

Rules: Debian packages from the Ubuntu archive only (**no snaps, no
Flatpak/Flathub**: online stores with background refresh), and every app has
its automatic network features switched off through **new** files. Install
only the apps you want.

```bash
apt_install libreoffice-writer libreoffice-calc libreoffice-impress libreoffice-draw libreoffice-math libreoffice-gnome libreoffice-help-en-us      # LibreOffice (usually preinstalled)
apt_install keepassxc                         # offline password manager
apt_install vlc                              # media player
apt_install gimp gimp-help-en                       # image editor + offline help
apt_install inkscape                         # vector graphics
apt_install deja-dup                         # backups
```

**Languages** (dictionaries, LibreOffice language packs, help). Ubuntu can
list the right packages offline for each language code:

```bash
for lang in de fr; do                                  # your languages
  apt_install $(check-language-support -l "$lang")
done
```

**Switch off each app's background network features:**

*LibreOffice: no online update check.* Either in the app (Tools > Options >
LibreOffice > Online Update > untick "Check for updates automatically"), or
with the helper this repo ships (it merges one setting into your profile
and keeps everything else; close LibreOffice first):

```bash
x=~/.config/libreoffice/4/user/registrymodifications.xcu
mkdir -p "$(dirname "$x")"; [ -f "$x" ] && cp -a "$x" "$x.bak" && record_undo "mv -f '$x.bak' '$x'"
python3 -I "$WS/modules/desktop/files/lo_update_check.py" set "$x"
python3 -I "$WS/modules/desktop/files/lo_update_check.py" check "$x" && echo "update check is off"
```

*KeePassXC (no update check, no third-party icon downloads) and VLC (no
metadata or album-art lookups, no first-run network dialog):*

```bash
put "$WS/modules/desktop/files/home/.config/keepassxc/keepassxc.ini" ~/.config/keepassxc/keepassxc.ini
put "$WS/modules/desktop/files/home/.config/vlc/vlcrc"               ~/.config/vlc/vlcrc
```

(If you already had these files, `put` keeps them: add the settings from the
repository copies by hand.)

*GIMP: no update check.* The settings directory is named after the version:

```bash
v=$(gimp --version | awk '{print $NF}'); d=~/.config/GIMP/$(echo "$v" | cut -d. -f1,2)
mkdir -p "$d"; touch "$d/gimprc"
grep -q '^(check-updates no)' "$d/gimprc" || { cp -a "$d/gimprc" "$d/gimprc.bak"; echo '(check-updates no)' >> "$d/gimprc"; record_undo "mv -f '$d/gimprc.bak' '$d/gimprc'"; }
```

*Déjà Dup: backups to a local folder or external disk only, never a cloud
service:*

```bash
gsettings range org.gnome.DejaDup backend      # lists the allowed values
gset org.gnome.DejaDup backend local           # use 'file' if 'local' is not listed
```

*Inkscape* has no automatic network features.

**Firefox and Thunderbird.** On Ubuntu both are *snaps*, so this guide does
not install them. If you use them, policy files switch off telemetry,
studies, Pocket, accounts, updates, sponsored content, captive-portal
probes and Safe Browsing. **Safe Browsing is disabled because it contacts
Google in the background; be careful with downloads and links.** The files
are installed only if no policy file exists yet:

```bash
put_system "$WS/modules/desktop/files/system/firefox-policies.json"     /etc/firefox/policies/policies.json
put_system "$WS/modules/desktop/files/system/thunderbird-policies.json" /etc/thunderbird/policies/policies.json
```

After the first start, open `about:policies` in Firefox and check that the
policies are active (whether the snap honours files in `/etc` is not
guaranteed). The snaps still refresh themselves from the Snap Store through
`snapd`; whether to keep them is your (or your IT's) decision.

Re-do the cheat sheet command in B10 with the `desktop` line enabled.

---

# Part D. Offline caches and lock-down

Everything below is **downloaded now, used offline later**. After D4,
`uv`, `pip`, `cargo` and `podman` work only from these local caches.

## D1. Python wheelhouse *(optional: `CACHE_PYTHON`)*

*Mirrors `step "Offline cache: Python wheels"`, function `cache_python`.*

```bash
wh=~/.local/share/workstation/wheelhouse; mkdir -p "$wh"
UV_PYTHON_DOWNLOADS=never uv venv --quiet --python /usr/bin/python3 /tmp/pydl
uv pip install --quiet --python /tmp/pydl/bin/python pip
dl() { /tmp/pydl/bin/python -m pip download --quiet --disable-pip-version-check --only-binary=:all: --dest "$wh" "$@"; }
dl pip setuptools wheel
PYPKGS="pytest pytest-cov hypothesis numpy scipy matplotlib pandas pyyaml jsonschema lxml jinja2 ipython rich"
# embedded part (C1) adds:   PYPKGS="$PYPKGS pyserial python-can spacepackets crc"
for p in $PYPKGS; do dl "$p" && echo "cached $p" || echo "no wheel for $p"; done
record_undo "rm -rf '$wh'"
rm -rf /tmp/pydl
```

Later, `uv pip install numpy pytest` is served from this folder. Packages
you add to the list are available offline too.

## D2. Rust crate cache *(optional: `CACHE_RUST`)*

*Mirrors `step "Offline cache: Rust crates"`, function `cache_rust`.*

Cargo downloads the crates for a throw-away project into its normal cache,
`~/.cargo/registry`. Later `cargo add`/`cargo build` work offline from it.

```bash
proj=~/.local/share/workstation/rust-offline-cache; mkdir -p "$proj/src"
printf '#![no_std]\n' > "$proj/src/lib.rs"
CRATES="bitflags crc serde thiserror anyhow clap proptest"
# embedded part (C1) adds:   CRATES="$CRATES heapless cortex-m cortex-m-rt embedded-hal nb critical-section defmt defmt-rtt panic-halt panic-probe postcard"
{
  printf '[package]\nname = "workstation-offline-cache"\nversion = "0.0.0"\nedition = "2021"\npublish = false\n\n[dependencies]\n'
  for c in $CRATES; do printf '%s = "*"\n' "$c"; done
} > "$proj/Cargo.toml"
(cd "$proj" && cargo fetch)
```

`Cargo.lock` in that folder records the exact crate versions (see
[Part F](#part-f-record-pin-and-undo)).

## D3. Container images and pull policy *(optional: `CACHE_CONTAINER_IMAGES`)*

*Mirrors `step "Offline cache: container images"`, function `cache_images`.*

`ubuntu:latest` is always the newest Ubuntu LTS. Add other or older images
only as deliberate exceptions.

```bash
podman pull docker.io/library/ubuntu:latest
record_undo "podman rmi docker.io/library/ubuntu:latest"
```

From now on, never pull images implicitly (a `podman run`/`distrobox create`
that names a missing image fails instead of downloading; an explicit
`podman pull` still works):

```bash
put "$WS/files/home/.config/containers/containers.conf" ~/.config/containers/containers.conf
podman info >/dev/null || { echo "podman rejects the file: remove it again"; rm -f ~/.config/containers/containers.conf; }
```

## D4. Enforce the offline environment

*Mirrors `files/home/.bashrc.d/20-offline.sh` (switch `ENFORCE_OFFLINE_ENV`).
The script installs it early but clears these variables for its own run; by
hand, install it **last**.*

```bash
less "$WS/files/home/.bashrc.d/20-offline.sh"
put  "$WS/files/home/.bashrc.d/20-offline.sh" ~/.bashrc.d/20-offline.sh
```

It exports `UV_OFFLINE=1`, `PIP_NO_INDEX=1`, `CARGO_NET_OFFLINE=true` and
points uv/pip at the wheelhouse. To fetch something deliberately (for
example from an internal mirror approved by your IT), override for one
command only: `UV_OFFLINE=0 uv add <pkg>` or `CARGO_NET_OFFLINE=false cargo update`.
Remove the file to switch the enforcement off.

---

# Part E. Verify

*Mirrors `./setup.sh --self-test`.* **Log out and back in first**, so group
memberships, PATH and the shell setup are active, then open a new terminal.
Run the checks for the parts you installed; each should succeed without
errors.

**Core toolchains**

```bash
cd "$(mktemp -d)"
printf '#include <stdio.h>\nint main(void){puts("C OK");return 0;}\n' > a.c && gcc -std=c17 -Wall -Wextra -Werror a.c -o a && ./a
printf '#include <iostream>\nint main(){std::cout<<"C++ OK\\n";}\n' > b.cpp && clang++ -std=c++20 -Wall -Wextra -Werror b.cpp -o b && ./b
printf 'int main(void){volatile int *p=__builtin_malloc(16); p[4]=1; return 0;}\n' > c.c
gcc -g -fsanitize=address,undefined c.c -o c; ./c 2>&1 | grep -q heap-buffer-overflow && echo "sanitizer OK"
printf 'fn main(){println!("Rust OK");}\n' > m.rs && rustc --edition 2021 m.rs && ./m
```

**Starter files and presets.** In a scratch folder, `ws-init` should add
files, a second run should only print `skip (exists)`, and the host preset
should build (use `files/selftest/presets/*` as the project):

```bash
d=$(mktemp -d) && cd "$d" && cp -r "$WS/files/selftest/presets/." . && ws-init
cmake --preset host-debug && cmake --build --preset host-debug && ctest --preset host-debug
```

**Language servers and editor**

```bash
for s in clangd rust-analyzer ruff basedpyright-langserver cmake-language-server taplo bash-language-server; do
  command -v "$s" >/dev/null && echo "ok  $s" || echo "MISSING $s"
done
hx --health c cpp python rust
printf '%s\n' -std=c11 > compile_flags.txt; echo 'int main(void){return 0;}' > x.c; clangd --check=x.c
```

**Python and Rust offline.** These must work *without* network:

```bash
cd "$(mktemp -d)" && uv venv --python /usr/bin/python3 venv && uv pip install --python venv/bin/python pytest
cargo new --vcs none --lib t && cd t && cargo add anyhow && cargo build
pre-commit --version        # hooks are all local (no remote repositories)
```

**Containers**

```bash
podman images
podman run --rm --network=none docker.io/library/ubuntu:latest true && echo "container OK"
```

**Embedded part (C1)**

```bash
id -nG | tr ' ' '\n' | grep -E 'dialout|plugdev|wireshark'     # groups active after re-login
arm-none-eabi-gcc --version | head -1; riscv64-unknown-elf-gcc --version | head -1
gdb-multiarch -batch -ex 'set architecture' 2>&1 | grep -E 'armv7e-m|riscv:rv64'
openocd --version 2>&1 | head -1
for t in thumbv6m-none-eabi thumbv7m-none-eabi thumbv7em-none-eabihf riscv32imac-unknown-none-elf; do
  printf '#![no_std]\npub fn f(a:u32)->u32{a}\n' > /tmp/l.rs && rustc --edition 2021 --crate-type lib --target "$t" --emit obj -o /tmp/l.o /tmp/l.rs && echo "ok $t"
done
# bare-metal programs under QEMU (semihosting) - see the sources in modules/embedded/files/selftest/
arm-none-eabi-gcc -mcpu=cortex-m3 -mthumb -O1 -ffreestanding -nostdlib \
  -T "$WS/modules/embedded/files/selftest/arm/lm3s6965.ld" "$WS/modules/embedded/files/selftest/arm/semihost.c" -o /tmp/arm.elf
timeout 30 qemu-system-arm -M lm3s6965evb -nographic -monitor none -serial none \
  -semihosting-config enable=on,target=native -kernel /tmp/arm.elf </dev/null | grep "ARM Cortex-M self-test OK"
```

**Desktop part (C2).** Re-run the `check` helper for LibreOffice and look at
the files you installed:

```bash
python3 -I "$WS/modules/desktop/files/lo_update_check.py" check ~/.config/libreoffice/4/user/registrymodifications.xcu && echo "LibreOffice update check off"
grep -H '^CheckForUpdates=false\|^IconDownloadFallback=false' ~/.config/keepassxc/keepassxc.ini
grep -H '^metadata-network-access=0\|^qt-privacy-ask=0' ~/.config/vlc/vlcrc
gsettings get org.gnome.DejaDup backend              # 'local', 'file' or 'drive'
python3 -c 'import json;p=json.load(open("/etc/firefox/policies/policies.json"))["policies"];print(p["DisableTelemetry"],p["DisableAppUpdate"])'
```

**The no-cloud checklist.** Every line must come out as stated.

```bash
command -v gh                                                  # prints nothing: GitHub CLI not installed
grep 'method: never'          ~/.config/lazygit/config.yml     # lazygit never checks for updates
grep 'python-downloads = "never"' ~/.config/uv/uv.toml         # uv never downloads Pythons
grep 'auto_update = false'    ~/.config/tealdeer/config.toml   # tldr never self-updates
npm config get update-notifier                                 # false
grep 'pull_policy = "never"'  ~/.config/containers/containers.conf
env | grep -E '^(UV_OFFLINE|PIP_NO_INDEX|CARGO_NET_OFFLINE)='  # all three set (D4)
grep -Eq 'repo:[[:space:]]*https?://' ~/.local/share/workstation/templates/generic/.pre-commit-config.yaml || echo "pre-commit template: local hooks only"
python3 -I - <<'EOF'
import tomllib, os
l = {x["name"]: x for x in tomllib.load(open(os.path.expanduser("~/.config/helix/languages.toml"), "rb"))["language"]}
print("json/yaml language servers disabled:", all(l[n].get("language-servers") == [] for n in ("json", "yaml")))
EOF
systemctl is-enabled apport.service whoopsie.service motd-news.timer fwupd-refresh.timer 2>&1   # none "enabled" (A6)
ls ~/.config/goa-1.0/accounts.conf 2>&1                        # should not exist (no online accounts)
```

## Still network-connected (OS level)

These are outside this guide. Discuss them with your IT if the machine must
be fully isolated; they should point at internal infrastructure:

- `apt` and `unattended-upgrades`: use an internal Ubuntu mirror.
- `snapd` (Firefox, Thunderbird, App Center): a Snap Store proxy, or remove/hold snaps.
- `chrony` time sync (NTS, Ubuntu servers): an internal NTP server.
- Ubuntu Insights is opt-in: decline any consent prompt.

---

# Part F. Record, pin and undo

## Record what you installed (manifest)

*Mirrors `./setup.sh --manifest`.* The exact state of the machine, as a
file you can keep and `diff` against another machine:

```bash
m=~/workstation-manifest-$(date +%Y%m%d).txt
{
  echo "# Manifest $(date -u)"; . /etc/os-release; echo "$PRETTY_NAME, kernel $(uname -r)"
  echo "## Tools"; for t in gcc g++ clang clangd cmake ninja gdb python3 uv ruff rustc cargo rust-analyzer hx node npm podman git; do
    command -v "$t" >/dev/null && printf '%-18s %s\n' "$t" "$("$t" --version 2>&1 | head -n1)"; done
  echo "## Rust";   rustup show active-toolchain; cargo install --list
  echo "## uv tools"; uv tool list
  echo "## npm globals"; npm ls -g --depth=0
  echo "## Wheelhouse"; (cd ~/.local/share/workstation/wheelhouse && sha256sum -- *.whl)
  echo "## Rust crate cache lock"; sha256sum ~/.local/share/workstation/rust-offline-cache/Cargo.lock
  echo "## Container images"; podman images --digests
  echo "## Downloads outside APT"; sort -u ~/.local/share/workstation/download-hashes.txt
  echo "## APT packages"; dpkg-query -W -f='${Package}\t${Version}\t${Architecture}\n' | sort
} > "$m" 2>&1
ln -sf "$m" ~/workstation-manifest-latest.txt
```

## Pin versions for reproducibility (optional)

*Mirrors `./setup.sh --lock`.* Without pins, a repeat of this guide on
another day installs whatever is newest then. To get identical machines,
write down the versions from your manifest and use them next time:

| Tool | Install a pinned version |
|---|---|
| Rust | `rustup toolchain install 1.NN.N` (version from `rustc --version`) |
| uv tools | `uv tool install --reinstall "ruff==X.Y.Z"` (versions from `uv tool list`) |
| cargo tools | `cargo install --locked taplo-cli@X.Y.Z` (from `cargo install --list`) |
| npm tools | `npm install -g bash-language-server@X.Y.Z` (from `npm ls -g`) |
| Python wheels | `dl "numpy==X.Y.Z"` in D1 (versions from the wheelhouse file names) |
| Rust crates | copy the saved `Cargo.lock` into the cache project before `cargo fetch --locked` (D2) |
| Container images | `podman pull docker.io/library/ubuntu@sha256:DIGEST` and `podman tag` it back to `ubuntu:latest` |
| Downloaded installers/tarballs | compare the SHA-256 in `download-hashes.txt` with the recorded value; refuse if it differs |

APT packages are deliberately **not** pinned: that would block Ubuntu
security updates. The manifest records them instead.

To move to newer versions deliberately: install the newest versions (drop
the pins), run Part E, then record a new manifest.

## Undo

Each section above ended with its undo. In general:

- **Files you created with `put`/`put_system`**, **gsettings**, **git
  settings**, **services**, **npm config**, **groups**: `~/workstation-undo.sh`
  contains one command per change, newest last. Read it, then run the
  lines you want, **newest first** (copy single lines rather than running
  the whole file).
- **Packages from APT**: use APT's history on newer APT (`apt history-list`,
  then `sudo apt history-undo <ID>`); with older APT, read
  `/var/log/apt/history.log` for what was installed.
- **Tools in your home directory**: `uv tool uninstall <name>`,
  `cargo uninstall <name>`, `npm rm -g <name>`, `rustup self uninstall`.
- **Cache folders**: `rm -rf ~/.local/share/workstation` (templates,
  wheelhouse, crate cache, hashes) and `~/.cargo/registry` for downloaded crates.
- **Switch the offline lock off** without uninstalling anything:
  `rm ~/.bashrc.d/20-offline.sh`.

---

# Automated route

Everything in this guide is also available as one script with a dry-run
mode, a self-test and a lock file: see [docs/script-reference.md](docs/script-reference.md).

```bash
sudo apt update
./setup.sh --profile work --check     # or: --profile personal. Changes nothing.
./setup.sh --profile work
```

The guide and the script are kept in step: `tools/check-readme-sync.sh`
verifies that every package, tool and config file the script knows about is
mentioned here. If you find a difference between this guide and the script,
the script's behaviour is the reference and the guide has a bug; please
report it.

If you distrust the script, a good way to use it is `./setup.sh --check`
(it never changes anything) and to compare its report with what you did by
hand; the manifest of a manual run and of a scripted run should match.

## Not included

Vendor or licensed tools: Gaisler toolchains for LEON (BCC/RCC), RTEMS
(build with the RTEMS Source Builder, ideally in a Distrobox container),
VxWorks, SEGGER J-Link software, Renode, MISRA rule texts for cppcheck.
Browsers and mail clients are not installed by this guide (on Ubuntu they
are snaps).
