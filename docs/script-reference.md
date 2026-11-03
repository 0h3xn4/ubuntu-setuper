# workstation-setup: script reference

This page documents the **automated** route (`setup.sh`). The step-by-step manual
route, which does the same things by hand, is the [README](../README.md).

Sets up a workstation on the latest Ubuntu LTS release for software
development, for work and personal use: C/C++/Rust/Python toolchains, the
Helix editor with language servers, git tooling, static analysis, offline
documentation and a comfortable bash. Optional modules add embedded tooling
(ARM and RISC-V cross compilers, QEMU, debug probe, serial and CAN tools) or
everyday desktop apps (office, passwords, media, graphics, backups). No
installed tool contacts the internet by itself after installation.

## Quick start

Run as your normal user (not with sudo), from a logged-in desktop session:

```bash
sudo apt update
./setup.sh --list-profiles
./setup.sh --profile work --check   # dry run: what would happen? changes nothing
./setup.sh --profile work           # install, configure, write manifest, run self-test
```

Then log out and back in, open a terminal and run `ws-help`.

The chosen profile is remembered in `~/.config/workstation/profile`, so later
runs (`--check`, `--self-test`, `--manifest`, `--lock`, `--upgrade`) need no
`--profile` unless you want a different one.

## Profiles, modules and the core

| | What it is |
|---|---|
| **core** | Always installed, on every profile: bash setup, Helix + language servers, git tooling, Python/C/C++/Rust, offline docs, privacy hardening (opt-in, runs after all package installs), offline caches, and the check / self-test / manifest / lock / undo machinery |
| **embedded** | Cross compilers (ARM, RISC-V), QEMU, OpenOCD and probes, serial/CAN tools, Wireshark, verification tools (CBMC, AFL++, ...), optional SPICE kernels, embedded Rust targets and cargo tools, `ws-devname`, cross-build starter files |
| **desktop** | LibreOffice, KeePassXC, VLC, GIMP, Inkscape, Déjà Dup, Firefox/Thunderbird policy files, spell-check languages. Each app has its background network features switched off |

| Profile | Modules |
|---|---|
| `work` | core + embedded |
| `personal` | core + embedded + desktop (embedded is part of it by your decision; remove `embedded` from `profiles/personal.conf` to leave it out) |

Make your own profile by copying a file in `profiles/`; it only needs
`PROFILE_MODULES=(...)` and may preset switches.

## Commands

| Command | Purpose |
|---|---|
| `./setup.sh --profile NAME` | Choose the profile (remembered afterwards) |
| `./setup.sh --undo [FILE]` | Take back an install run: replays the newest `~/workstation-undo-*.sh` (or FILE) newest-first after listing every command and asking. `--dry-run` only lists, `--yes` skips the question. Never removes APT packages. Works on the manual guide's `~/workstation-undo.sh` too |
| `./setup.sh --full` | The **full setup**: switch on every opt-in system change (services, `/etc` drop-ins, groups, GNOME settings, `~/.bashrc` loader, git defaults, browser policies). Switches you set yourself in the environment still win. Also `FULL_SETUP=1`. Asks for confirmation in a terminal. Combine with `--explain`/`--check` to preview. Pass it to `--self-test` too so the extra changes are verified |
| `./setup.sh --explain` | Plain-language tour of every step this profile runs: what it does, why, where it changes things; plus which system changes are on or off. Changes nothing, needs no network |
| `./setup.sh --check` | Dry run: package availability, conflicts, planned changes |
| `./setup.sh` | Full installation, then manifest and self-test |
| `./setup.sh --self-test` | Verify toolchains, offline caches and the no-cloud policy |
| `./setup.sh --manifest` | Write a full list of installed software and versions |
| `./setup.sh --lock` | Pin all non-APT versions and download checksums |
| `./setup.sh --upgrade` | Ignore pins, install the newest stable versions, self-test |
| `./setup.sh --list-profiles` | Show profiles and modules |

Options combine: `./setup.sh --profile personal --check`.

## Files

| Path | Purpose |
|---|---|
| `setup.sh` | The setup logic (core library, install steps, check, self-test, manifest, lock) |
| `workstation.conf` | Core switches, package lists, tool lists. Edit this. |
| `profiles/<name>.conf` | Which modules a machine gets; may preset switches |
| `modules/<name>/module.conf` | A module's switches and package lists |
| `modules/<name>/module.sh` | A module's install steps, self-tests and hooks |
| `modules/<name>/files/` | A module's home files, starter files, self-test sources, cheat sheet part |
| `locks/<profile>.lock`, `locks/<profile>.Cargo.lock` | Pinned versions and checksums per profile (created by `--lock`) |
| `files/home/` | Core config files installed into your home directory |
| `files/templates/` | Generic project starter files used by `ws-init` |
| `files/cheatsheet/` | Core and maintenance parts of the cheat sheet (`ws-help`) |
| `files/selftest/` | Sources compiled and run by the core self-test |

Precedence of settings: environment > lock (versions only) > profile >
`workstation.conf` > module defaults. For example
`INSTALL_DOCKER=1 ./setup.sh` overrides everything for one run.

### Starter files in projects

`ws-init` copies the generic starter files (editorconfig, clang-format/tidy,
clangd, pre-commit, ruff, host CMake presets) into the current project and
never overwrites. Modules add their own set: `ws-init --embedded` also copies
CMake cross toolchain files and ARM/RISC-V presets (included from
`CMakePresets.json`). `ws-init --list` shows what is installed.

## Team workflow (reproducible workstations)

1. One engineer runs `./setup.sh --profile work`, checks the self-test, then
   runs `./setup.sh --lock`.
2. Commit the whole folder, including `locks/work.lock` and
   `locks/work.Cargo.lock`, to version control. One lock per profile.
3. Every other machine with that profile runs `./setup.sh --profile work` from
   that commit and gets the same versions of everything outside APT. Downloads
   whose checksum doesn't match the lock are refused.
4. To upgrade deliberately: run `./setup.sh --upgrade` on one machine, check
   the self-test, re-run `--lock`, review the diff, commit.

APT packages are not pinned (that would block Ubuntu security updates); each
machine's exact package versions are recorded in its manifest
(`~/workstation-manifest-latest.txt`), so two machines can be compared with
`diff`.

## Policies (fixed, no switch, every profile)

**No cloud.** Downloading during installation is allowed. Afterwards, no tool
contacts external services: cloud-connected tools aren't installed, update
checks and telemetry are disabled, and uv/pip/cargo/podman work only from
local caches filled during installation (see `files/home/.bashrc.d/20-offline.sh`).
The self-test verifies this, including one check per desktop app.

For apps that are networked by nature (browser, mail): traffic *you* direct to
a destination *you* chose is fine (opening a website, fetching mail from your
own server, an explicit `podman pull`). Anything automatic or in the
background is not: telemetry, update checks, crash reports, sync, accounts,
recommendations, automatic lookups (album art, website icons, metadata),
implicit downloads. Consequence in Firefox: Safe Browsing (which polls Google)
is switched off by the policy file.

**System changes are opt-in.** By default the setup only installs packages
and writes new files in your home directory. Everything that touches the
system or your login files has its own switch, **off by default**:
`TUNE_INOTIFY`, `DISABLE_REPORTING_SERVICES`, `DISABLE_MOTD_NEWS`,
`DISABLE_FWUPD_REFRESH`, `DISABLE_APT_NEWS`, `DISABLE_NM_CONNECTIVITY_CHECK`,
`SET_GNOME_FONT`, `SET_GNOME_PRIVACY`, `JOIN_DOCKER_GROUP`,
`ENABLE_SHELL_LOADER` (the ~/.bashrc block), `SET_GIT_DEFAULTS`, `INSTALL_OH_MY_BASH`
(Oh My Bash from one pinned commit, loaded from `~/.bashrc.d` with its update
check off; its own installer is never used; it replaces the starship prompt), and the
modules' `JOIN_SERIAL_GROUPS`, `JOIN_WIRESHARK_GROUP`,
`DESKTOP_BROWSER_POLICIES`. `--explain`, `--check` and the install summary
list them with their state. Without `ENABLE_SHELL_LOADER` the shell setup
is installed but inactive (the summary prints the line to add yourself).

**Fonts.** `INSTALL_NERD_FONT` (on by default) installs JetBrains Mono Nerd Font
for your user in `~/.local/share/fonts` (one checksum-verified download from
the project's GitHub release; the version is pinned by the lock). With
`SET_GNOME_FONT=1` GNOME's monospace font becomes `JetBrainsMono Nerd Font Mono 11`
and starship uses its icon preset; otherwise plain-text symbols. `ls`, `ll`, `la` and
`tree` (eza) show file icons whenever the font is installed; they only render if your
terminal uses it. `WS_ICONS=0` switches the icons off, `WS_ICONS=1` forces them on.

**Don't break Ubuntu.** No package is ever removed (`apt --no-remove`) and
no installed package is upgraded (the setup never runs `apt upgrade`; installs
use `--no-upgrade`), no
package-owned config file is edited, and kernel, boot, coreutils and APT
sources are untouched. Only new files are added in `/etc`, existing ones are
never overwritten. Every change is recorded in
`~/workstation-undo-<timestamp>.sh`. Debs from the Ubuntu archive only: the
desktop module installs no snaps and no Flatpaks.

**Versions.** Always the latest Ubuntu LTS release: the setup detects it
(offline, via distro-info) and warns on older or non-LTS releases. For
software with an LTS line, the newest LTS; otherwise the newest stable
release. Never betas, release candidates or nightlies. A lock file is a
deliberate snapshot of "newest at that time"; `--upgrade` moves forward.
**Node.js** is the one tool with an LTS line that is installed, and there the newest *upstream* LTS
wins over the archive's older Node.js (your decision): the setup unpacks the release from nodejs.org
(its index says which is the newest LTS) into `~/.local/opt/node-<version>`, linked from `~/.local/bin`,
after checking it against the `SHASUMS256.txt` the project publishes. No APT repository is added.
`NODE_LTS_VERSION` pins a release (the lock does it), `NODE_FROM_ARCHIVE=1` uses Ubuntu's own
`nodejs`/`npm`, which is also the fallback if the download fails. System components (Python, gcc,
glibc, systemd) always stay the archive version.

**Checksums.** Where the project publishes a checksum (uv, rustup-init, starship, lazygit,
probe-rs, the Nerd Font), the download is compared with *that* and a mismatch is refused. Other
downloads outside APT (the Helix tarball, SPICE kernels) are verified against SHA-256 values in the
lock file; without a lock their checksum is recorded on first download (trust on first use) and pinned
by `--lock`. Compare them with the publisher's values if your process requires it. Package managers
(APT, cargo, uv/pip, npm) verify their own downloads. See "Downloads and checksums" below.

## Switching profiles on one machine

`./setup.sh --profile personal` on a machine that was set up as `work` adds
the personal modules; nothing is removed. The remembered profile changes to
the new one (the undo script restores the old name).

## Not included

Vendor or licensed tools: Gaisler toolchains for LEON (BCC/RCC), RTEMS (build
with the RTEMS Source Builder, ideally in a Distrobox container), VxWorks,
SEGGER J-Link software, Renode, MISRA rule texts for cppcheck.
Browsers and mail clients are not installed (on Ubuntu they are snaps); the
desktop module only places policy files for Firefox and Thunderbird.

## Tools in `tools/`

| Tool | Purpose |
|---|---|
| `tools/check-all.sh [--quick]` | Every check of this repository: `shellcheck`/`bash -n`, JSON/TOML/YAML parsing, README sync, the README's code blocks, `--explain`/`--check` for every profile; without `--quick` also functional tests in a throw-away `HOME` (`ws-init`, `ws-doctor`, `--undo`, manifest diff, the checksum-verified download helper incl. a tamper test, the LibreOffice helper) |
| `tools/check-readme-sync.sh` | Fails if the README misses a package, tool, home file, step, switch, option or privacy service the script knows about |
| `tools/e2e.sh --profile P --i-know-this-machine-is-disposable` | Full end-to-end test on a DISPOSABLE Ubuntu machine: explain/check, full install, self-test (a skipped RISC-V QEMU test counts as a failure), `ws-doctor` in a new shell, shell checks, idempotent re-install, manifest, lock (must pin the Rust toolchain and, when installed, Node.js), `--undo`, leftovers (incl. `~/.local/opt` and the node/npm/npx links). Env: `E2E_SWITCHES`, `E2E_ALLOW_FAILED_STEPS`, `E2E_ALLOW_MISSING`, `E2E_LOG_DIR`. `--plan` shows the phases. Run by `.github/workflows/e2e.yml` |
| `tools/manifest-diff.sh A B` | Compare two manifests (two machines, or manual vs scripted setup), ignoring host, user, CPU, kernel, hashes and dates |
| `tools/install-hooks.sh` | Enable the git pre-commit hook (`check-all.sh --quick`) in this clone |

CI (`.github/workflows/ci.yml`): `check-all.sh` on every push and PR, then for each profile a
`--check` against the real archive of the newest Ubuntu LTS and a reduced real install in a container.
The E2E workflow (`.github/workflows/e2e.yml`, 10 to 20 minutes per job, started manually (Actions > E2E > Run workflow, or the API's workflow_dispatch on any branch, no pull request needed) or by a PR titled with `[e2e]`)
runs `tools/e2e.sh` for both profiles on a GitHub runner VM and in an `ubuntu:latest` container. It
purges the runner's preinstalled `gh` first and removes the container image's dpkg excludes, so the
machine looks like a normal Ubuntu install. Results of the latest runs: README, "How well tested is this?".

Health check: `ws-doctor` (installed in `~/.local/bin`, read-only, offline, no repository needed)
reports missing tools, editor and shell setup, and the no-cloud settings in seconds; `--self-test` is
the full verification.

## Downloads and checksums

Where the project publishes a checksum, the download is compared with *that* checksum and a
mismatch is refused (`fetch_published`): uv, rustup (`rustup-init`), starship, the Nerd Font
(`SHA-256.txt`), probe-rs and lazygit (`checksums.txt`). For the rest (the Helix tarball) the
SHA-256 is recorded on first use and pinned by `--lock` (`fetch_verified`). The release tag of a
`latest/download` URL is read from its redirect, so no GitHub API call is needed. `PROBE_RS_PREBUILT=0`
compiles probe-rs with cargo instead; `lazygit` is taken from its release where the archive has none.
