# workstation-setup: manual setup guide

A step-by-step guide to set up a development workstation on the **latest
Ubuntu LTS release**, by hand, without running any setup script. It does
exactly what `setup.sh` in this repository does, in the same order, so you
can read, understand and control every change from start to finish. If you
would rather automate it, see [Automated route](#automated-route) at the end.

What you get: C/C++/Rust/Python toolchains, the Helix editor (terminal) and
Kate (graphical) with language servers, git tooling, static analysis, offline documentation and a
comfortable bash. Two optional parts: the **embedded** part (ARM and RISC-V
cross compilers, QEMU, debug probes, serial and CAN tools, verification
tools) and the **desktop** part (everyday apps with their background
network features switched off). **No installed tool contacts the internet by
itself after installation.**

**By default this setup does not change Ubuntu itself.** It installs packages
from the Ubuntu archive and writes new files in your home directory. Every
change to the system or to your login files (`/etc` drop-ins, services,
groups, GNOME settings, `~/.bashrc`, global git config) is **opt-in**: off
unless you choose it, with one switch each. [The big picture](#the-big-picture)
lists them all.

## Contents

- [The big picture](#the-big-picture): what ends up where, when the network is used, what is opt-in
- [How well tested is this?](#how-well-tested-is-this)
- [Rules this guide follows](#rules-this-guide-follows)
- [How to use this guide](#how-to-use-this-guide)
- [Part A. Preparation](#part-a-preparation): A1 check the system, A2 helpers, A3 package lists, A4 (no system upgrade), A5 tuning *(opt-in)*, A6 privacy *(opt-in)*, A7 coming from zsh *(only if you use zsh)*
- [Part B. Core](#part-b-core-always): B1 CLI tools ... B13 desktop settings, B14 Nerd Font, B15 Oh My Bash *(opt-in)*, B16 Kate
- [Part C. Optional parts](#part-c-optional-parts): C1 embedded, C2 desktop
- [Part D. Offline caches and lock-down](#part-d-offline-caches-and-lock-down)
- [Part E. Verify](#part-e-verify)
- [Part F. Record, pin and undo](#part-f-record-pin-and-undo)
- [Troubleshooting](#troubleshooting)
- [Automated route](#automated-route)

## The big picture

Read this section first. It answers "what does all of this do to my
machine?" before the step-by-step part shows how.

### The flow

```
 A Prepare ───► B Core ───────► C Optional parts ──► D Offline caches ──► E Verify ──► F Record
 check OS       CLI tools        C1 embedded (work)    download now,        self-test    manifest,
 helpers        C/C++, Python    C2 desktop (personal) use offline later    no-cloud     pin, undo
 package lists  Rust, Helix      (do either, both,     then lock the dev    checklist
                containers,      or neither)           package managers
                shell, git                             (last)
```

### Three zones: what gets changed

| Zone | What happens there | Needs `sudo`? |
|---|---|---|
| **1. Packages** | Programs from the Ubuntu archive are installed with `apt`. Nothing is removed, nothing already installed is upgraded, no repositories or PPAs are added, no snaps or Flatpaks. (APT may still pull newer versions of the *libraries* a new program needs; that is how dependencies work.) | yes, for `apt` |
| **2. Your home directory** | A few tools from official installers or `cargo`/`npm`/`uv` (uv, rustup, Rust tools, Helix if not in the archive, starship), new config files and helper commands, starter files for projects, the offline caches (Python wheels, Rust crates, container images), a cheat sheet, and an undo script. All below `~`, all new files (an existing file of yours is never overwritten). | no |
| **3. The system itself** | **Nothing by default.** Only the opt-in changes in the table below, and only the ones you switch on. | yes, per change |

### Opt-in changes to the system and to your login files

All **off by default**. Each has one switch in `workstation.conf` (or a
profile, or the environment for one run: `TUNE_INOTIFY=1 ./setup.sh`). In
this guide each one sits in a clearly marked **[opt-in]** section: do it
only if you want it. The script lists them with their state:
`./setup.sh --explain`.

| Switch | What it does | Where this guide covers it | Undo |
|---|---|---|---|
| `TUNE_INOTIFY` | New file `/etc/sysctl.d/60-dev-inotify.conf`: more file watches, so language servers cope with big source trees | [A5](#a5-system-tuning) | delete the file |
| `DISABLE_REPORTING_SERVICES` | Disables crash and problem reporting: `apport`, `whoopsie`, `kerneloops` | [A6](#a6-privacy-hardening-at-os-level) | `systemctl enable` |
| `DISABLE_MOTD_NEWS` | Disables `motd-news.timer` (news fetched at login) | A6 | `systemctl enable` |
| `DISABLE_FWUPD_REFRESH` | Disables `fwupd-refresh.timer` (firmware metadata refresh) | A6 | `systemctl enable` |
| `DISABLE_APT_NEWS` | `pro config set apt_news=false` (messages apt fetches from Canonical) | A6 | `pro config set apt_news=true` |
| `DISABLE_NM_CONNECTIVITY_CHECK` | New file in `/etc/NetworkManager/conf.d/`: no periodic connectivity probe | A6 | delete the file |
| `SET_GNOME_FONT` | GNOME monospace font: JetBrainsMono Nerd Font Mono 11 (JetBrains Mono 11 without B14) | [B13](#b13-desktop-gnome-settings) | `gsettings set` back |
| `SET_GNOME_PRIVACY` | GNOME: no location, no automatic time zone, no problem reports, no usage stats, no web search in Activities | B13 | `gsettings set` back |
| `JOIN_DOCKER_GROUP` | Adds you to group `docker` (equivalent to root; only if you install Docker) | [B9](#b9-containers-optional-install_podman-install_docker) | `gpasswd -d` |
| `ENABLE_SHELL_LOADER` | Appends one marked block to `~/.bashrc` that loads `~/.bashrc.d` (aliases, PATH, prompt, offline lock) | [B10](#b10-shell-bash) | delete the block |
| `SET_GIT_DEFAULTS` | Global git defaults, only options you have not set | [B11](#b11-git) | `git config --unset` |
| `INSTALL_OH_MY_BASH` | Oh My Bash from one pinned commit, loaded from `~/.bashrc.d` with its update check off; replaces the starship prompt (not a system change, but opt-in) | [B15](#b15-oh-my-bash-opt-in-install_oh_my_bash-off-by-default) | delete the clone and the file |
| `JOIN_SERIAL_GROUPS` | *(embedded)* adds you to groups `dialout`, `plugdev`: serial ports and debug probes without `sudo` | [C1](#c1-embedded-part-work-and-personal-profiles) | `gpasswd -d` |
| `JOIN_WIRESHARK_GROUP` | *(embedded)* lets group `wireshark` capture without root (debconf answer, group) | C1 | `dpkg-reconfigure`, `gpasswd -d` |
| `DESKTOP_BROWSER_POLICIES` | *(desktop)* new policy files below `/etc/firefox` and `/etc/thunderbird` | [C2](#c2-desktop-part-personal-profile) | delete the files |

In the script, the privacy changes (A6) run *after* all package installs, because installing a
package can switch its timer back on; the guide lists A6 early only to keep the opt-in sections together.

**The full setup.** To do all of them: in this guide, do every section marked
**[opt-in]** (A5, all five blocks of A6, the Docker group in B9, the loader in
B10, the git defaults in B11, both parts of B13, the groups and Wireshark
group in C1, and the policy files in C2). With the script it is one option:
`./setup.sh --profile work --full` (or `FULL_SETUP=1`). `--full` switches on
every opt-in change, except any switch you set yourself
(`SET_GNOME_FONT=0 ./setup.sh --full` keeps the font alone). It shows the
list and asks for confirmation first when run in a terminal. `--full` does
not install optional software (Docker, Frama-C, SPICE, ...): those are
separate switches.

If you skip them, everything is still installed and works; you just
use `sudo` where those changes would have avoided it. **One consequence
to know about:** without the shell loader (`ENABLE_SHELL_LOADER`), the new
shell setup is installed but not active: `~/.cargo/bin` is not on your
`PATH` and the offline lock for `uv`/`pip`/`cargo` does not apply to your
shell until you load `~/.bashrc.d` yourself (B10 shows the one line).

### Where things end up in your home directory

| Path | Contents |
|---|---|
| `~/.local/bin` | `uv`, `ws-init`, `ws-devname`, `hx` (Helix, if not from the archive), `node`/`npm`/`npx` (links into `~/.local/opt`), npm tools |
| `~/.local/opt` | Node.js (the newest LTS release, one folder per version; `node`, `npm`, `npx` are linked from `~/.local/bin`), Helix release tarball, if used |
| `~/.local/share/fonts` | JetBrains Mono Nerd Font (32 font files), installed for your user only |
| `~/.local/share/oh-my-bash` | Oh My Bash, one pinned commit (only if you chose it) |
| `~/.config/kate` | Kate's language-server settings |
| `~/.cargo`, `~/.rustup` | Rust toolchain, cargo tools, downloaded crates |
| `~/.config/...` | helix, lazygit, tealdeer, uv, containers, starship (and the desktop apps' settings) |
| `~/.bashrc.d` | shell setup files (`10-workstation.sh`, `15-oh-my-bash.sh`, `20-offline.sh`, `30-embedded.sh`) |
| `~/.local/share/workstation` | project starter files, Python wheelhouse, Rust crate cache, download checksums, SPICE kernels |
| `~/WORKSTATION-CHEATSHEET.md` | the cheat sheet (`ws-help`) |
| `~/workstation-undo.sh`, `~/workstation-manifest-*.txt` | your undo commands, the record of what was installed |

### When the network is used

- **While you set up (allowed):** `apt`; the release downloads for `uv`,
  `rustup`, `starship`, `lazygit` and `probe-rs` (checked against the
  checksums those projects publish), the Node.js LTS tarball from nodejs.org
  (checked against its `SHASUMS256.txt`) and the Helix release, only if the archive
  lacks it; `uv tool install`, `cargo install`, `npm install`; `tldr --update`
  once; the Nerd Font release from GitHub and, if you choose, the Oh My
  Bash clone from GitHub; the three offline caches (PyPI, crates.io, the
  container registry) and, if you choose, the SPICE kernels.
- **Afterwards (not allowed unless you ask):** nothing connects by itself.
  Update checks, telemetry and online lookups of the installed tools are
  switched off, and `uv`, `pip`, `cargo` and `podman` work only from the
  local caches. Parts of Ubuntu itself (apt, snapd, time sync) are outside
  this guide; see [Still network-connected](#still-network-connected-os-level).

### What it never does

Remove a package. Upgrade the system or any package you already have. Edit a
file that belongs to a package. Overwrite an existing file. Mask a service.
Add an APT repository or PPA. Install a snap or Flatpak. Touch the kernel,
boot, coreutils or APT sources. Create accounts or sign in anywhere.

### Coming from zsh?

This setup is for bash. If you use zsh or Oh My Zsh, run `./setup.sh --reset-shell` first (or do
[A7](#a7-coming-from-zsh-or-oh-my-zsh-only-if-you-use-zsh) by hand): it moves your zsh files into a
backup folder (nothing is deleted), makes bash your login shell again and records everything for
`./setup.sh --undo`.

### See it before you do it

If you also have the script: `./setup.sh --profile work --explain` prints this
whole picture for your profile, step by step, and changes nothing;
`./setup.sh --profile work --check` adds package names and versions. Add
`--full` to either to see the full setup instead of the default one. Afterwards,
`ws-doctor` (installed by the setup, also by [B10](#b10-shell-bash)) checks the result in
seconds, without network.

---

## How well tested is this?

Be skeptical, and check for yourself; this is what has and has not been verified
(newest facts first; the details and dates are in `CHANGELOG.md` and `CLAUDE.md`).

- **Full end-to-end test on Ubuntu 26.04.1 LTS (in CI, `tools/e2e.sh`):** the
  *whole* life cycle of both profiles passes in all four jobs (a GitHub runner VM
  and an `ubuntu:latest` container, each for `work` and `personal`; `personal`
  includes the embedded part): `--check` against the real archive, a full `--full`
  install as a normal user with `sudo` (the install step took 9 to 19 minutes, depending on the runner), the self-test (33 and 36
  checks passed, 0 failed, on the VM for `work` and `personal`; 32 and 35 in the
  container), `ws-doctor` in a fresh shell, an idempotent second run, manifest,
  lock (it pins Node.js too), `--undo` of every undo file, and a check that
  nothing the setup created is left behind (APT packages stay by design).
  **Node.js 26 (the newest LTS) from nodejs.org is installed and used in all four
  jobs**, and the ARM and RISC-V programs run in QEMU. The checks that are skipped
  are skipped on purpose (SPICE kernels are off by default; image caching is off in
  a container, which cannot run podman; the VM run covers the rest). It took six
  runs to get here: the bugs found are in `CHANGELOG.md` (package names that
  changed on 26.04, undo gaps, service handling in containers, an ordering problem
  in the privacy step), and one was only visible by reading a green run's log: a
  RISC-V test that had been *skipped* because 26.04 moved RISC-V emulation into its
  own package (`qemu-system-riscv`). The E2E test now fails on such a skip. No
  desktop session was involved in any of this.
- **Earlier, smaller real install on the newest Ubuntu LTS (CI, `ubuntu:latest`):** a reduced
  install of both profiles worked, as a normal user with `sudo`. Its self-test
  passed 20 checks (compilers, sanitizers, CMake, GoogleTest, clangd, ruff and
  basedpyright via uv, Helix, pre-commit offline, ccache, ARM cross builds,
  OpenOCD, `ws-devname`, ...) and **failed 1**, which turned out to be a mistake
  in the test, not in the setup: QEMU 10 prints the program's semihosting
  output on *stderr*, and the check only read stdout (QEMU's exit status was 0,
  as expected). The test now reads both streams (confirmed later by the full
  run above). The same run confirmed that `ws-doctor` finds the tools installed in
  `~/.local/bin` without the shell loader.
- **Package names:** all checked against the real Ubuntu 24.04 and 26.04
  archives. Only `lazygit` (24.04 only), `zellij` and `difftastic` are missing
  (the guide and script have a fallback for lazygit and skip the others).
  26.04 renamed or split three packages, which the lists now use: `7zip` (was
  `p7zip-full`), `qemu-user` + `qemu-user-binfmt` (was `qemu-user-static`) and
  `qemu-system-riscv` (split from `qemu-system-misc`; on 24.04 it does not exist and
  the setup just reports it as not available, because `qemu-system-misc` still has RISC-V there).
- **Downloads:** the checksum checks for uv, rustup, starship, lazygit, probe-rs
  and the Nerd Font were run against the real files, including a deliberately
  wrong checksum, which is refused.
- **Not yet verified:** the desktop apps' settings (written
  from documentation, not from running each app), the Firefox/Thunderbird policy
  files (do they apply to the snaps? check `about:policies`), the GNOME
  settings (`SET_GNOME_FONT`, `SET_GNOME_PRIVACY`) and how the icons look in a
  real terminal, and everything on a real desktop. Also not run yet: the lock files
(`locks/`) are not committed, so version pinning has been tested (the lock phase of
the E2E test) but no real pins exist.

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
   - **Changes to the system itself are opt-in**: off unless you switch
     them on (table above). By default only `apt` installs and new files in
     your home directory.
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
5. **Verify what you download outside APT.** Where the project publishes a
   checksum (uv, rustup, starship, Nerd Fonts, probe-rs, lazygit) the guide
   compares the download with *that* checksum and refuses a mismatch. For the
   rest it downloads to a file, records its SHA-256 and lets you read it
   before running it. See [A2](#a2-helpers).

## How to use this guide

- Run everything as your **normal user**. `sudo` appears only where shown.
- Open a terminal in the root of this repository (the folder with this
  README). Several steps copy files from it into your home directory.
- Commands are meant to be pasted a block at a time, in order. Each section
  names the script step it mirrors, e.g. *mirrors `step "Base CLI tools"`,
  function `base_cli` in `setup.sh`*, so you can read the code next to the
  text.
- **Which parts do I do?** Parts A, B, D and E are the core and are
  always done. Part C is optional: C1 is embedded and flight-software tooling
  (in both the **work** and the **personal** profile), C2 is everyday desktop
  apps (the **personal** profile). Do either, both or neither. Inside a section, lines marked
  *(optional)* correspond to a switch in `workstation.conf`.
- **Sections marked [opt-in]** change the system or your login files. Skip
  them unless you want that change; the heading names the switch the script
  uses for the same thing (all are listed in [the big picture](#the-big-picture)).
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

# download_verified URL SUMS_URL NAME FILE  downloads, then compares with the checksum the PROJECT publishes.
#   NAME = the file name to look for inside SUMS_URL (empty if that file holds a single hash).
#   A mismatch (or a missing checksum) deletes the download and fails.
download_verified() {
  local url=$1 sums=$2 name=$3 out=$4 expected actual
  curl -fsSL --retry 3 --connect-timeout 20 "$url" -o "$out" || return 1
  if [ -n "$name" ]; then
    expected=$(curl -fsSL "$sums" | awk -v n="$name" '{f=$2; sub(/^\*/,"",f); sub(/^\.\//,"",f); if (f==n) {print $1; exit}}')
  else
    expected=$(curl -fsSL "$sums" | awk 'NR==1 {print $1}')
  fi
  actual=$(sha256sum "$out" | cut -d' ' -f1)
  if [ -z "$expected" ] || [ "$expected" != "$actual" ]; then
    echo "CHECKSUM MISMATCH or no published checksum: $url"; rm -f "$out"; return 1
  fi
  echo "checksum verified (published by the project): $url"
  mkdir -p ~/.local/share/workstation
  echo "$url $actual published" >> ~/.local/share/workstation/download-hashes.txt
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
- `download_verified` is used wherever the project publishes a checksum; it
  refuses a mismatch. `download` is for the rest (for example the Helix
  tarball): it records the SHA-256 of what you downloaded, so compare it
  with the publisher's value if your process requires it; keep
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

> **[opt-in: `TUNE_INOTIFY`]** Skip this section to leave the system's
> kernel settings alone.

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

> **[opt-in: `DISABLE_REPORTING_SERVICES`, `DISABLE_MOTD_NEWS`,
> `DISABLE_FWUPD_REFRESH`, `DISABLE_APT_NEWS`,
> `DISABLE_NM_CONNECTIVITY_CHECK`]** Five independent switches: do only the
> blocks you want. Skip the whole section to keep Ubuntu's defaults.

*Mirrors `step "Privacy hardening"`, function `privacy_hardening`.*

> **Order matters:** the script runs this step *after* all package installs (end of
> Part C), because installing a package can switch its timer back on (a dependency
> pulled in `motd-news.timer` in the end-to-end test). In this manual, do A6 after
> Parts B and C, or re-check with `systemctl is-enabled` afterwards.

Only services are **disabled** (not masked, not removed) and new drop-in
files are added, so updates keep working. These are Ubuntu's own background
features (reports, news, probes), not tools of this setup, which is why they
are your choice.

```bash
# DISABLE_REPORTING_SERVICES: crash/problem reporting, kernel oops reports
for u in apport.service apport-autoreport.path apport-autoreport.timer \
         whoopsie.service whoopsie.path kerneloops.service; do
  if [ "$(systemctl is-enabled "$u" 2>/dev/null)" = enabled ]; then
    sudo systemctl disable "$u" && record_undo "sudo systemctl enable $u"
    sudo systemctl stop "$u" || true     # best effort: a container has no running systemd
  fi
done

# DISABLE_MOTD_NEWS: news fetched at login
u=motd-news.timer
if [ "$(systemctl is-enabled "$u" 2>/dev/null)" = enabled ]; then
  sudo systemctl disable "$u" && record_undo "sudo systemctl enable $u"
  sudo systemctl stop "$u" || true
fi

# DISABLE_FWUPD_REFRESH: periodic firmware metadata refresh
u=fwupd-refresh.timer
if [ "$(systemctl is-enabled "$u" 2>/dev/null)" = enabled ]; then
  sudo systemctl disable "$u" && record_undo "sudo systemctl enable $u"
  sudo systemctl stop "$u" || true
fi

# DISABLE_APT_NEWS: messages fetched from Canonical when you run apt
if command -v pro >/dev/null && sudo pro config set apt_news=false; then
  record_undo "sudo pro config set apt_news=true"
fi

# DISABLE_NM_CONNECTIVITY_CHECK: NetworkManager's periodic connectivity probe (new drop-in file)
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

## A7. Coming from zsh or Oh My Zsh *(only if you use zsh)*

*Mirrors `./setup.sh --reset-shell`, function `reset_shell_mode`.*

Everything in this guide is for **bash**: the aliases, the prompt, the history settings, the
`fzf`/`zoxide`/`direnv`/`starship` hooks and above all the offline lock for `uv`, `pip` and `cargo`
(D4) live in `~/.bashrc.d` and are loaded by `~/.bashrc`. A zsh session never reads them, so in zsh
the tools are installed but the shell experience and **the offline protection are missing**.
If you use zsh (often with Oh My Zsh) and want this setup, the simplest honest route is to go back
to bash first. This section is that "factory reset" for the shell. **Nothing is deleted**: your zsh
files are *moved* into a backup folder, and every step is recorded for undo. Do it once, before
Part B; skip it if you already use bash.

```bash
# 1. Move the zsh files (Oh My Zsh included) into a timestamped backup folder, never delete them
backup=~/workstation-shell-backup-$(date +%Y%m%d-%H%M%S); mkdir -p "$backup"
record_undo "rmdir --ignore-fail-on-non-empty '$backup'"            # recorded first, so undone last
shopt -s nullglob
for f in ~/.oh-my-zsh ~/.zshrc ~/.zshenv ~/.zprofile ~/.zlogin ~/.zlogout ~/.zsh_history \
         ~/.zshrc.pre-oh-my-zsh ~/.p10k.zsh ~/.zsh ~/.zsh_sessions ~/.zcompdump*; do
  [ -e "$f" ] || [ -L "$f" ] || continue                              # a symlink (dotfile manager) is moved as a link
  record_undo "mv -n '$backup/${f##*/}' '$f'"
  mv -- "$f" "$backup/"
done
shopt -u nullglob

# 2. Bash needs ~/.bashrc and ~/.profile: copy the Ubuntu defaults only if they are missing
for f in .bashrc .profile; do
  [ -e ~/$f ] || { cp /etc/skel/$f ~/$f && record_undo "rm -f ~/$f"; }
done

# 3. Login shell back to bash (a system change: it edits your entry in /etc/passwd, with sudo)
old=$(getent passwd "$USER" | cut -d: -f7)
case "$old" in
  */zsh) record_undo "sudo usermod -s $old $USER"; sudo usermod -s /bin/bash "$USER" ;;
esac
```

The login shell changes at your **next login** (open terminals keep running zsh); log out and in
again. The **zsh package is not removed** (this guide never removes packages); if you want it gone
as well: `sudo apt remove zsh` (other accounts that use zsh would lose their login shell). Not
touched: terminal profiles that start `/usr/bin/zsh` explicitly (change that in the terminal's
settings), and a custom `ZDOTDIR`. Your files stay in the backup folder until you delete it yourself.

With the script it is one command that lists everything first and asks:
`./setup.sh --reset-shell` (`--dry-run` only lists, `--yes` skips the question). Take it back with
`./setup.sh --undo` (it is the newest undo file). Oh My Zsh's own update checks, by the way, are
the kind of automatic network traffic this setup avoids; after the reset there is no Oh My Zsh.

---

# Part B. Core (always)

## B1. Base command-line tools

*Mirrors `step "Base CLI tools"`, function `base_cli`.*

```bash
apt_install \
  git git-lfs wget unzip zip 7zip xz-utils zstd rsync tree file \
  distro-info htop btop jq yq ripgrep fd-find bat eza zoxide fzf direnv \
  tealdeer hyperfine entr just tmux bash-completion shellcheck shfmt \
  yamllint git-delta lazygit moreutils pv ncdu libxml2-utils \
  fonts-jetbrains-mono wl-clipboard xclip
```

`gh`/`glab` are deliberately **not** in the list: they talk to cloud forges.
(On Ubuntu `bat` runs as `batcat` and `fd-find` as `fdfind`; the shell
setup in B10 adds the familiar aliases.)

`wl-clipboard` (Wayland) and `xclip` (X11) are what Helix uses to reach the
system clipboard (`Space y` / `Space p`).

**lazygit** is not in every Ubuntu release (it is missing in 24.04). If
`apt_install` reported it as not in the archive, take it from the project's
release, checked against the `checksums.txt` the project publishes:

```bash
command -v lazygit || {
  base=https://github.com/jesseduffield/lazygit/releases/latest/download
  arch=x86_64; [ "$(uname -m)" = aarch64 ] && arch=arm64
  asset=$(curl -fsSL "$base/checksums.txt" | awk -v a="_linux_$arch.tar.gz" 'index($2,a) {print $2; exit}')
  download_verified "$base/$asset" "$base/checksums.txt" "$asset" "/tmp/$asset"
  mkdir -p ~/.local/bin && tar -xzf "/tmp/$asset" -C ~/.local/bin lazygit
  record_undo "rm -f ~/.local/bin/lazygit"
}
```

**Extra terminal tools** *(optional: `INSTALL_NICE_TO_HAVE`; mirrors
`step "Extra terminal tools"`)*: zellij (a beginner-friendlier terminal
multiplexer than tmux) and difftastic (structural diffs). They are not in
every Ubuntu release; `apt_install` skips what is missing.

```bash
apt_install zellij difftastic
```

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

If `uv` is still missing, take the release tarball and let `download_verified`
check it against the `.sha256` that astral publishes next to it. (This is
used instead of the installer script, which would also edit your shell
startup files.) To pin a version use `.../releases/download/<version>` as
`base`.

```bash
command -v uv || {
  arch=$(uname -m)                                                  # x86_64 or aarch64
  base=https://github.com/astral-sh/uv/releases/latest/download
  asset=uv-$arch-unknown-linux-gnu.tar.gz
  download_verified "$base/$asset" "$base/$asset.sha256" "$asset" "/tmp/$asset"
  tar -xzf "/tmp/$asset" -C /tmp
  mkdir -p ~/.local/bin
  install -m 755 "/tmp/uv-$arch-unknown-linux-gnu/uv" "/tmp/uv-$arch-unknown-linux-gnu/uvx" -t ~/.local/bin
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
  uv tool list | grep -q "^$t " || { uv tool install "$t" && record_undo "uv tool uninstall $t"; }
done
```

To reinstall an exact version later: `uv tool install --reinstall "ruff==X.Y.Z"`.

Undo: `uv tool uninstall <name>` for each tool; `rm -f ~/.local/bin/uv ~/.local/bin/uvx`.

## B5. Rust toolchain *(optional: `INSTALL_RUST`)*

*Mirrors `step "Rust toolchain"`, function `rust_toolchain`.*

**rustup**: from the archive if available, else `rustup-init` itself, checked
against the `.sha256` the Rust project publishes (instead of the
`sh.rustup.rs` script that downloads it). `--default-toolchain none`
installs only rustup itself; `--no-modify-path` leaves your shell files alone.

```bash
command -v rustup || apt_install rustup
command -v rustup || {
  url=https://static.rust-lang.org/rustup/dist/$(uname -m)-unknown-linux-gnu/rustup-init
  download_verified "$url" "$url.sha256" rustup-init /tmp/rustup-init
  chmod +x /tmp/rustup-init
  /tmp/rustup-init -y --no-modify-path --default-toolchain none
  record_undo "rustup self uninstall -y"
}

# What we add to ~/.rustup is undone too (the archive's rustup has no "self uninstall"). Decide
# this BEFORE 'rustup set ...', which already creates ~/.rustup/settings.toml:
[ -e ~/.rustup ] || record_undo "rm -rf ~/.rustup"
rustup toolchain list | grep -q '^stable' || record_undo "rustup toolchain uninstall stable"

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
for c in taplo-cli cargo-nextest; do
  cargo install --list | grep -q "^$c v" || record_undo "cargo uninstall $c"
done
cargo install --locked taplo-cli cargo-nextest
```

`--locked` makes cargo use the exact dependency versions the tool's authors
tested. Pin a tool with `cargo install --locked taplo-cli@X.Y.Z`.

Undo: `cargo uninstall <name>`; `rustup toolchain uninstall stable`; `rustup self uninstall`
if you installed rustup with `rustup-init` (the archive's rustup has no such command).

## B6. Offline documentation *(optional: `INSTALL_OFFLINE_DOCS`)*

*Mirrors `step "Offline documentation"`, function `offline_docs`.*

```bash
apt_install \
  cppreference-doc-en-html python3-doc cmake-doc manpages-dev \
  manpages-posix manpages-posix-dev glibc-doc gdb-doc
```

You now have, without internet: C/C++ reference (cppreference), Python,
CMake, POSIX and glibc manuals (`man 3 printf`, `man 3posix pthread_create`),
the GDB manual (`info gdb`) and, via rustup, the Rust docs (`rustup doc`).

## B7. Bash language server *(optional: `INSTALL_BASH_LSP`)*

*Mirrors `step "Bash language server"`, function `bash_lsp`.*

Installed with npm into your home directory (no root). npm is told not to
contact the registry for update notices, funding messages or audits.

**Node.js itself: the newest LTS release from nodejs.org, not the archive's.** Ubuntu's
`nodejs` is older than the newest upstream LTS; this setup prefers the newest LTS (your
decision) without adding an APT repository (no NodeSource): the project's own tarball is
unpacked in your home directory and checked against the `SHASUMS256.txt` the project publishes.
The project's index marks which release is the newest LTS (its "lts" field):

```bash
v=$(curl -fsSL https://nodejs.org/dist/index.json | python3 -I -c 'import json, sys
for r in json.load(sys.stdin):
    if r.get("lts"):
        print(r["version"]); break')
echo "newest LTS: $v"
case "$(uname -m)" in x86_64) a=x64 ;; aarch64) a=arm64 ;; esac
asset=node-$v-linux-$a.tar.xz; base=https://nodejs.org/dist/$v
download_verified "$base/$asset" "$base/SHASUMS256.txt" "$asset" "/tmp/$asset"
mkdir -p ~/.local/opt ~/.local/bin
[ -e ~/.local/opt/node-$v ] || record_undo "rm -rf ~/.local/opt/node-$v"
mkdir -p ~/.local/opt/node-$v && tar -xJf "/tmp/$asset" -C ~/.local/opt/node-$v --strip-components=1
# Link what the release ships (newer ones no longer include corepack). If one of these names
# already exists in ~/.local/bin and is not yours, stop and look at it first: never replace it.
for t in node npm npx corepack; do
  [ -e ~/.local/opt/node-$v/bin/$t ] || continue
  [ -e ~/.local/bin/$t ] || [ -L ~/.local/bin/$t ] || record_undo "rm -f ~/.local/bin/$t"
  ln -sfn ../opt/node-$v/bin/$t ~/.local/bin/$t
done
hash -r; node --version
```

To pin a version, set `v=v26.13.0` (any release listed on nodejs.org) instead of the lookup.
If you prefer Ubuntu's own (older, but Ubuntu-supported) Node.js, skip the block above and run
`apt_install nodejs npm`; the script does this with `NODE_FROM_ARCHIVE=1`, and also as a
fallback if the download fails.

Then the language server:

```bash
npm config set prefix "$HOME/.local"
npm config set update-notifier false
npm config set fund false
npm config set audit false
record_undo "npm config delete prefix; npm config delete update-notifier; npm config delete fund; npm config delete audit"
[ -e ~/.local/lib/node_modules/bash-language-server ] || record_undo "npm uninstall -g bash-language-server"
npm install -g bash-language-server
```

Undo: `npm rm -g <name>`, the `npm config delete ...` line, and
`rm -rf ~/.local/opt/node-<version>` plus the links `~/.local/bin/{node,npm,npx,corepack}`.

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

Whenever podman is installed, it must never pull images by itself. (The script does
this here, in the "Containers" step; the same file is also used by D3.) The guard
removes the file again only if podman worked before it and fails after it; a plain
container where podman cannot run at all says nothing about the file.

```bash
f=~/.config/containers/containers.conf
ok=0; podman info >/dev/null 2>&1 && ok=1
put "$WS/files/home/.config/containers/containers.conf" "$f"
if [ "$ok" = 1 ] && ! podman info >/dev/null 2>&1; then
  echo "podman rejects the file: removing it again"; rm -f "$f"
fi
```

*(optional, off by default: `INSTALL_DOCKER`)* Docker Engine rewrites
firewall rules, which can interfere with VPNs. Only if you really need it:

```bash
apt_install docker.io docker-compose-v2 docker-buildx
```

> **[opt-in: `JOIN_DOCKER_GROUP`]** The `docker` group is equivalent to
> root. Without it you run `sudo docker ...`. To join it anyway:
> `sudo usermod -aG docker "$USER" && record_undo "sudo gpasswd -d $USER docker"`

Images and the "never pull implicitly" setting come later, in
[D3](#d3-container-images-and-pull-policy).

## B10. Shell (bash)

*Mirrors `step "Shell (bash) setup"`, function `shell_setup`.*

**Loader** *(opt-in: `ENABLE_SHELL_LOADER`)*. A small block in `~/.bashrc`
that sources `~/.bashrc.d/*.sh`. This is the only edit to a file that Ubuntu
created for you (your own `~/.bashrc`, not a package-owned file under
`/etc`). **If you skip it**, you still install the files below, but nothing
loads them: add this line to `~/.bashrc` yourself when you are ready (or load
them by hand with `. ~/.bashrc.d/10-workstation.sh`):
`for f in "$HOME"/.bashrc.d/*.sh; do [ -r "$f" ] && . "$f"; done; unset f`.
Until then `~/.cargo/bin` is not on your `PATH`, and the aliases, prompt and
offline lock are not active.

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
put "$WS/files/home/.local/bin/ws-doctor"        ~/.local/bin/ws-doctor 755
```

(`20-offline.sh`, the runtime no-cloud lock, is installed last, in
[D4](#d4-enforce-the-offline-environment).)

**Prompt (starship)** *(optional: `INSTALL_STARSHIP`; skip it if you use
Oh My Bash, [B15](#b15-oh-my-bash-opt-in-install_oh_my_bash-off-by-default))*.
Archive first, otherwise the project's release tarball, checked against the
`.sha256` it publishes:

```bash
command -v starship || apt_install starship
command -v starship || {
  asset=starship-$(uname -m)-unknown-linux-gnu.tar.gz
  base=https://github.com/starship/starship/releases/latest/download
  download_verified "$base/$asset" "$base/$asset.sha256" "" "/tmp/$asset"
  mkdir -p ~/.local/bin && tar -xzf "/tmp/$asset" -C ~/.local/bin starship
  record_undo "rm -f ~/.local/bin/starship"
}
# plain-text symbols need no special font. If your terminal uses the Nerd Font
# (B14 + B13), you can use 'nerd-font-symbols' instead for icons.
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

> **[opt-in: `SET_GIT_DEFAULTS`]** The block below changes your global git
> configuration. Skip it to leave `~/.gitconfig` alone. Your identity
> (`user.name`/`user.email`) is never touched by this guide.

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
```

(Your identity, if not set yet: `git config --global user.name "Your Name"`
and `git config --global user.email "you@example.org"`.)

`lazygit` checks GitHub for new versions by default. Turn that off (always
done; it is a new file in `~/.config`, not part of the opt-in above):

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

> **[opt-in: `SET_GNOME_FONT`, `SET_GNOME_PRIVACY`]** Two independent
> switches: the font line, and the privacy block. Skip this section to keep
> GNOME's defaults.

*Mirrors `step "Desktop settings"`, function `desktop_tweaks`. Needs a
logged-in GNOME session. Each `gset` prints and records the previous value.*

```bash
gset() {   # gset SCHEMA KEY VALUE
  local old; old="$(gsettings get "$1" "$2")" || return 0
  gsettings set "$1" "$2" "$3" && record_undo "gsettings set $1 $2 $(printf %q "$old")"
}
# SET_GNOME_FONT: Ubuntu's default monospace font is small; the terminal follows this setting
gset org.gnome.desktop.interface monospace-font-name 'JetBrainsMono Nerd Font Mono 11'   # needs B14; else 'JetBrains Mono 11'
# SET_GNOME_PRIVACY
gset org.gnome.system.location enabled false
gset org.gnome.desktop.datetime automatic-timezone false
gset org.gnome.desktop.privacy report-technical-problems false
gset org.gnome.desktop.privacy send-software-usage-stats false
# no web / Snap Store search in the Activities overview (installed apps still found)
gset org.gnome.desktop.search-providers disable-external true
```

Leave **GNOME Online Accounts** (Settings > Online Accounts) empty. Accounts
there (Google, Microsoft, Nextcloud, ...) sync in the background.

## B14. JetBrains Mono Nerd Font *(optional: `INSTALL_NERD_FONT`, default on)*

*Mirrors `step "JetBrains Mono Nerd Font"`, function `nerd_font`.*

JetBrains Mono with icon glyphs added, so prompts and themes can show icons.
It is not in the Ubuntu archive, so it comes from the project's GitHub
release. It is installed for **your user only** (no system font directory).
The script runs this right after B1; the order does not matter.

**File icons in `ls`/`ll`.** `10-workstation.sh` gives `eza` (installed in B1) file
icons (`--icons=auto`) whenever this font's directory exists, so `ll` looks like
a long listing with a folder/file-type icon per entry. The icons only render if your
**terminal** uses the font: GNOME Terminal > Preferences > your profile > Custom font >
*JetBrainsMono Nerd Font Mono* (or `SET_GNOME_FONT=1`, B13). If you see empty boxes,
set `WS_ICONS=0` (e.g. in `~/.bashrc.d/30-local.sh`) to switch the icons off; `WS_ICONS=1` forces them on.

Find the newest **stable** tag on `https://github.com/ryanoasis/nerd-fonts/releases`
(the one marked "Latest") and use it as `VERSION`:

```bash
apt_install fontconfig          # provides fc-cache; normally already present on Ubuntu Desktop
VERSION=...                     # e.g. the tag of the latest stable release
base=https://github.com/ryanoasis/nerd-fonts/releases/download/${VERSION}
# checked against SHA-256.txt, which the project publishes with every release
download_verified "$base/JetBrainsMono.tar.xz" "$base/SHA-256.txt" JetBrainsMono.tar.xz /tmp/jbm-nerd.tar.xz
d=~/.local/share/fonts/JetBrainsMonoNerdFont; mkdir -p "$d"
# only the two ligature families; skips the "NL" (no ligatures) and "Propo" variants
tar -xJf /tmp/jbm-nerd.tar.xz -C "$d" --wildcards 'JetBrainsMonoNerdFont-*.ttf' 'JetBrainsMonoNerdFontMono-*.ttf'
echo "$VERSION" > "$d/.version"
fc-cache -f "$d"
record_undo "rm -rf '$d' && fc-cache -f"
fc-list : family | grep 'JetBrainsMono Nerd Font Mono'      # should list the font
```

To **use** it, pick the family **JetBrainsMono Nerd Font Mono** as your
terminal font (the "Mono" variant keeps icons single-width, which is right for
terminals): in GNOME Terminal under Preferences > your profile > Custom font,
or system-wide with the opt-in font setting in [B13](#b13-desktop-gnome-settings).

Undo: `rm -rf ~/.local/share/fonts/JetBrainsMonoNerdFont && fc-cache -f`.

## B15. Oh My Bash *(opt-in: `INSTALL_OH_MY_BASH`, off by default)*

*Mirrors `step "Oh My Bash"`, function `oh_my_bash`, and
`files/home/.bashrc.d/15-oh-my-bash.sh`.*

Oh My Bash is a bash framework with themes, aliases and plugins. **Do not use
its own installer**: it moves your `~/.bashrc` away and replaces it with its
template, and it turns on a check of GitHub for updates every 13 days. This
guide instead fetches **one pinned commit** and loads it from a file in
`~/.bashrc.d`, with the update check switched off, so your `~/.bashrc` is not
touched (beyond the optional loader of [B10](#b10-shell-bash), which this
needs). Oh My Bash and the starship prompt both want to own the prompt, so
the guide's `10-workstation.sh` skips starship whenever
`~/.bashrc.d/15-oh-my-bash.sh` exists. Choose one: if you do this section,
you can skip the starship part of B10.

```bash
repo=https://github.com/ohmybash/oh-my-bash.git
commit=$(git ls-remote "$repo" HEAD | awk 'NR==1 { print $1 }')
echo "$commit"                      # write this down: it is your pin (Oh My Bash has no stable releases)
d=~/.local/share/oh-my-bash
mkdir -p "$d" && git init -q "$d" && git -C "$d" remote add origin "$repo"
git -C "$d" fetch --depth=1 origin "$commit" && git -C "$d" checkout -q --detach FETCH_HEAD
record_undo "rm -rf '$d'"
less "$d/oh-my-bash.sh"             # read what you are about to load
less "$WS/files/home/.bashrc.d/15-oh-my-bash.sh"
put "$WS/files/home/.bashrc.d/15-oh-my-bash.sh" ~/.bashrc.d/15-oh-my-bash.sh
```

The file sets `DISABLE_AUTO_UPDATE=true` (no cloud), the theme, and a short
list of completions, aliases and plugins; edit them there. To update on
purpose later, repeat the `fetch`/`checkout` with a newer commit.

Undo: `rm -rf ~/.local/share/oh-my-bash ~/.bashrc.d/15-oh-my-bash.sh`.

## B16. Kate editor *(optional: `INSTALL_KATE`, default on)*

*Mirrors `step "Kate editor"`, function `kate_setup`.*

Kate is the KDE text editor, a graphical editor next to Helix. It is
installed as a Debian package from the Ubuntu archive (not a snap or
Flatpak), and being a KDE program it brings in a set of KDE libraries. Skip
this section on a machine without a desktop. In Kate's build files (checked in
its repository) I found no telemetry or update-check dependency; only use its
"download"/"get new" buttons if you accept an online request. The script runs
this after Helix; the order does not matter.

```bash
apt_install kate
put "$WS/files/home/.config/kate/lspclient/settings.json" ~/.config/kate/lspclient/settings.json
```

The settings file points Kate's built-in language-server client at the same
local servers Helix uses: basedpyright and ruff (Python), cmake-language-server,
taplo (TOML). Kate merges it over its own defaults, which already cover
clangd, rust-analyzer and bash-language-server. Kate's defaults for JSON and
YAML would use `vscode-json-languageserver` and `yaml-language-server`, which
download schemas from the internet; they are not installed, so they are not
used. Keep it that way:

```bash
for s in vscode-json-languageserver yaml-language-server; do command -v "$s" && echo "REMOVE $s: it fetches schemas online"; done
```

Undo: `rm ~/.config/kate/lspclient/settings.json`; the package via APT history.

---

# Part C. Optional parts

## C1. Embedded part (work and personal profiles)

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
  dfu-util srecord can-utils sigrok-cli qemu-system-arm qemu-system-misc qemu-system-riscv \
  qemu-system-sparc qemu-user qemu-user-binfmt qemu-utils tio picocom minicom \
  libudev-dev
```

> **[opt-in: `JOIN_SERIAL_GROUPS`]** Serial ports and USB debug probes
> without `sudo` need two groups. Without them, use `sudo`. Group
> membership takes effect at your next login:

```bash
for g in dialout plugdev; do
  getent group "$g" >/dev/null || continue
  id -nG "$USER" | grep -qw "$g" && continue
  sudo usermod -aG "$g" "$USER" && record_undo "sudo gpasswd -d $USER $g"
done
```

**Wireshark** *(optional: `INSTALL_WIRESHARK`)*:

```bash
apt_install wireshark
```

> **[opt-in: `JOIN_WIRESHARK_GROUP`]** Capture for members of the `wireshark`
> group instead of root. Without it, capture needs `sudo`. This sets a debconf
> answer, reconfigures the package and adds you to the group:

```bash
echo "wireshark-common wireshark-common/install-setuid boolean true" | sudo debconf-set-selections
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
cargo install --locked cargo-binutils flip-link        # compiles; slow (INSTALL_CARGO_TOOLS)
```

**probe-rs** *(mirrors `step "probe-rs (prebuilt)"`; switch `PROBE_RS_PREBUILT`,
default on)*. Compiling it takes 10+ minutes, so take the project's own
release instead, checked against the `.sha256` it publishes (to pin a version
use `.../releases/download/<tag>` as `base`). If you prefer to compile it:
`cargo install --locked probe-rs-tools`.

```bash
asset=probe-rs-tools-$(uname -m)-unknown-linux-gnu.tar.xz
base=https://github.com/probe-rs/probe-rs/releases/latest/download
download_verified "$base/$asset" "$base/$asset.sha256" "$asset" "/tmp/$asset"
tar -xJf "/tmp/$asset" -C /tmp
mkdir -p ~/.local/bin
install -m 755 "/tmp/${asset%.tar.xz}"/{probe-rs,cargo-embed,cargo-flash} -t ~/.local/bin
record_undo "rm -f ~/.local/bin/probe-rs ~/.local/bin/cargo-embed ~/.local/bin/cargo-flash"
```

If `probe-rs list` does not see your probe, it may need udev rules that give
your user access to it (a system file below `/etc/udev/rules.d`: your
decision; the probe-rs documentation has the file).

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

**Firefox and Thunderbird** *(opt-in: `DESKTOP_BROWSER_POLICIES`; new files
below `/etc`)*. On Ubuntu both are *snaps*, so this guide does not install
them. If you use them, policy files switch off telemetry,
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
record_undo "if podman image exists docker.io/library/ubuntu:latest; then podman rmi docker.io/library/ubuntu:latest; fi"
```

The "never pull images implicitly" file (`containers.conf`) is installed in
[B9](#b9-containers-optional-install_podman-install_docker), whenever podman is, not only
when you cache images. A `podman run`/`distrobox create` that names a missing image then
fails instead of downloading; an explicit `podman pull` (as above) still works. If you
skipped B9, run its `containers.conf` block now.

## D4. Enforce the offline environment

*Mirrors `files/home/.bashrc.d/20-offline.sh` (switch `ENFORCE_OFFLINE_ENV`).
The script installs it early but clears these variables for its own run; by
hand, install it **last**.*

```bash
less "$WS/files/home/.bashrc.d/20-offline.sh"
put  "$WS/files/home/.bashrc.d/20-offline.sh" ~/.bashrc.d/20-offline.sh
```

It exports `UV_OFFLINE=1`, `PIP_NO_INDEX=1`, `CARGO_NET_OFFLINE=true` and
points uv/pip at the wheelhouse. It only takes effect in shells that load
`~/.bashrc.d`, i.e. after the loader from [B10](#b10-shell-bash)
(opt-in `ENABLE_SHELL_LOADER`) is in place. To fetch something deliberately (for
example from an internal mirror approved by your IT), override for one
command only: `UV_OFFLINE=0 uv add <pkg>` or `CARGO_NET_OFFLINE=false cargo update`.
Remove the file to switch the enforcement off.

---

# Part E. Verify

*Mirrors `./setup.sh --self-test`.* **Log out and back in first**, so group
memberships, PATH and the shell setup are active, then open a new terminal.
Run the checks for the parts you installed; each should succeed without
errors.

**Quick look first:** `ws-doctor` (read-only, offline) lists missing tools,
missing language servers, shell-setup problems and no-cloud settings that are
off, with one line each. It also looks in `~/.local/bin` and `~/.cargo/bin`
when the shell loader is not active, and tells you if those are not on `PATH`.
The checks below go deeper (they build and run things).

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
id -nG | tr ' ' '\n' | grep -E 'dialout|plugdev|wireshark'     # only if you chose JOIN_SERIAL_GROUPS / JOIN_WIRESHARK_GROUP
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
  -semihosting-config enable=on,target=native -kernel /tmp/arm.elf </dev/null > /tmp/qemu.txt 2>&1
echo "QEMU exit status: $?    (0 expected: the program ends with SYS_EXIT / ApplicationExit)"
cat /tmp/qemu.txt                                    # expect: ARM Cortex-M self-test OK
```

Two things matter here. QEMU prints the program's semihosting output on
**stderr** (QEMU 10.2 on the newest LTS), so redirect both streams (`2>&1`) or
you will see nothing. And do not pipe through `grep` or `tee`: a pipe hides
QEMU's own exit status.

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
grep '^export DISABLE_AUTO_UPDATE=true' ~/.bashrc.d/15-oh-my-bash.sh   # only if you did B15
fc-list : family | grep 'JetBrainsMono Nerd Font Mono'                 # only if you did B14
env | grep -E '^(UV_OFFLINE|PIP_NO_INDEX|CARGO_NET_OFFLINE)='  # all three set (D4)
grep -Eq 'repo:[[:space:]]*https?://' ~/.local/share/workstation/templates/generic/.pre-commit-config.yaml || echo "pre-commit template: local hooks only"
python3 -I - <<'EOF'
import tomllib, os
l = {x["name"]: x for x in tomllib.load(open(os.path.expanduser("~/.config/helix/languages.toml"), "rb"))["language"]}
print("json/yaml language servers disabled:", all(l[n].get("language-servers") == [] for n in ("json", "yaml")))
EOF
systemctl is-enabled apport.service whoopsie.service motd-news.timer fwupd-refresh.timer 2>&1   # "disabled" only for the A6 switches you chose; otherwise Ubuntu's defaults stay
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

To compare two machines (or a manual and a scripted setup):
`tools/manifest-diff.sh manifest-A.txt manifest-B.txt` ignores host, user, CPU,
kernel, hashes and dates and shows added, removed and changed packages and
tools. Plain `diff` works too, just noisier.

## Pin versions for reproducibility (optional)

*Mirrors `./setup.sh --lock`.* Without pins, a repeat of this guide on
another day installs whatever is newest then. To get identical machines,
write down the versions from your manifest and use them next time:

| Tool | Install a pinned version |
|---|---|
| Rust | `rustup toolchain install 1.NN.N` (version from `rustc --version`) |
| Node.js | set `v=vNN.N.N` in B7 instead of the index lookup (version from `node --version`) |
| uv tools | `uv tool install --reinstall "ruff==X.Y.Z"` (versions from `uv tool list`) |
| cargo tools | `cargo install --locked taplo-cli@X.Y.Z` (from `cargo install --list`) |
| npm tools | `npm install -g bash-language-server@X.Y.Z` (from `npm ls -g`) |
| Python wheels | `dl "numpy==X.Y.Z"` in D1 (versions from the wheelhouse file names) |
| Rust crates | copy the saved `Cargo.lock` into the cache project before `cargo fetch --locked` (D2) |
| Container images | `podman pull docker.io/library/ubuntu@sha256:DIGEST` and `podman tag` it back to `ubuntu:latest` |
| Nerd Font | use the recorded `VERSION` tag in B14 |
| Oh My Bash | use the recorded `commit` in B15 |
| Downloaded installers/tarballs | compare the SHA-256 in `download-hashes.txt` with the recorded value; refuse if it differs |

APT packages are deliberately **not** pinned: that would block Ubuntu
security updates. The manifest records them instead.

To move to newer versions deliberately: install the newest versions (drop
the pins), run Part E, then record a new manifest.

## Undo

Each section above ended with its undo. In general:

- **Files you created with `put`/`put_system`**, **gsettings**, **git
  settings**, **services**, **npm config**, **groups**: `~/workstation-undo.sh`
  contains one command per change, newest last. See them newest first with
  `grep -vE '^(#|set -x)' ~/workstation-undo.sh | tac`, then run the lines you
  want. With the script it is one command that shows everything first and
  asks before it runs anything: `./setup.sh --undo ~/workstation-undo.sh`
  (add `--dry-run` to only list).
- **Packages from APT**: use APT's history on newer APT (`apt history-list`,
  then `sudo apt history-undo <ID>`); with older APT, read
  `/var/log/apt/history.log` for what was installed.
- **Tools in your home directory**: `uv tool uninstall <name>`,
  `cargo uninstall <name>`, `npm rm -g <name>`, `rustup toolchain uninstall <name>`
  (and `rustup self uninstall` if you installed rustup with `rustup-init`). The blocks
  above record these for you; the script's `--undo` replays them.
- **Cache folders**: `rm -rf ~/.local/share/workstation` (templates,
  wheelhouse, crate cache, hashes) and `~/.cargo/registry` for downloaded crates.
- **Switch the offline lock off** without uninstalling anything:
  `rm ~/.bashrc.d/20-offline.sh`.

---

# Troubleshooting

Start with `ws-doctor` (read-only, offline): it lists what is missing or
misconfigured. The full verification is `./setup.sh --self-test` (or Part E).

| Symptom | Likely cause and fix |
|---|---|
| `apt_install` says "not in archive" for a package | Your Ubuntu release does not have it (for example `lazygit` on 24.04, and `zellij` and `difftastic` on both 24.04 and 26.04). The guide has a fallback where one exists (lazygit); otherwise skip it. |
| New terminal has no aliases, no prompt, `cargo` is not found | The shell loader is not active (it is opt-in). Add `for f in "$HOME"/.bashrc.d/*.sh; do [ -r "$f" ] && . "$f"; done; unset f` to `~/.bashrc` ([B10](#b10-shell-bash)). |
| `uv`, `pip` or `cargo` refuse to download | That is the offline lock working ([D4](#d4-enforce-the-offline-environment)). Override for one command: `UV_OFFLINE=0 uv add pkg` or `CARGO_NET_OFFLINE=false cargo update`. |
| `ls`/`ll` or the prompt show boxes or question marks instead of icons | The terminal font is not the Nerd Font. Pick *JetBrainsMono Nerd Font Mono* in the terminal's profile ([B14](#b14-jetbrains-mono-nerd-font-optional-install_nerd_font-default-on)), or use `starship preset plain-text-symbols -o ~/.config/starship.toml` for the prompt and `export WS_ICONS=0` to switch the `ls`/`ll` icons off ([B14](#b14-jetbrains-mono-nerd-font-optional-install_nerd_font-default-on)). |
| `podman info` fails in a container or CI job | Podman needs user namespaces and a cgroup setup that a plain Docker container does not give it. That is not a setup bug; the guard in [B9](#b9-containers-optional-install_podman-install_docker) only removes `containers.conf` if podman worked before the file was added. |
| `qemu-system-riscv64: command not found` | On Ubuntu 26.04 RISC-V emulation is its own package: `apt_install qemu-system-riscv` (on 24.04 it is part of `qemu-system-misc`). The embedded part ([C1](#c1-embedded-part-work-and-personal-profiles)) installs it. |
| Helix cannot copy to or paste from the system clipboard | `wl-clipboard` (Wayland) or `xclip` (X11) is missing: `apt_install wl-clipboard xclip`. |
| I use zsh / Oh My Zsh and the aliases, the prompt or the offline lock are missing | This setup is for bash ([A7](#a7-coming-from-zsh-or-oh-my-zsh-only-if-you-use-zsh)). `./setup.sh --reset-shell` moves your zsh files into a backup folder, makes bash your login shell again and is fully undoable. |
| `hx --health` shows red entries | A language server is not installed or not on `PATH`. `ws-doctor` names the missing ones. |
| Serial port or debug probe: "permission denied" | You are not in the groups `dialout`/`plugdev` (opt-in `JOIN_SERIAL_GROUPS`, [C1](#c1-embedded-part-work-and-personal-profiles)), or you have not logged out and in since joining. |
| Wireshark can capture only as root | The opt-in `JOIN_WIRESHARK_GROUP` is off ([C1](#c1-embedded-part-work-and-personal-profiles)). |
| Two prompts fight (starship vs Oh My Bash) | Only one may own the prompt; while `~/.bashrc.d/15-oh-my-bash.sh` exists, starship is skipped by `10-workstation.sh`. |
| A checksum mismatch message | The download differs from what the project published: do not use it. Retry later; if it persists, the release changed under you, so report it to the project. |
| Something I do not understand | `./setup.sh --explain` describes every step, and the "big picture" section at the top of this page shows where things go. |

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
mentioned here. `tools/check-all.sh` runs every check of the repository in one
go (lint, parsing, README sync, and functional tests in a throw-away home
directory; `--quick` for the static ones, which the git hook from
`tools/install-hooks.sh` runs on every commit), and the GitHub workflow in
`.github/workflows` runs them, plus a real install on the newest Ubuntu LTS,
for every change. For the complete life cycle, `tools/e2e.sh --profile work
--i-know-this-machine-is-disposable` does a **full** install (every opt-in on),
self-test, health check, a second install, manifest, lock, then `--undo` and a
check that nothing is left behind (and, as a last phase, a zsh user's `--reset-shell` and its undo). Run it in a throw-away VM only (it refuses
to run as root or without that flag); the "E2E" workflow does it on GitHub
runners (manually, or on a pull request whose title contains `[e2e]`). What changed and when is in `CHANGELOG.md`. If you find a difference between this guide and the script,
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
