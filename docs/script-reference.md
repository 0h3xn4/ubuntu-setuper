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
| **core** | Always installed, on every profile: bash setup, Helix + language servers, git tooling, Python/C/C++/Rust, offline docs, privacy hardening, offline caches, and the check / self-test / manifest / lock / undo machinery |
| **embedded** | Cross compilers (ARM, RISC-V), QEMU, OpenOCD and probes, serial/CAN tools, Wireshark, verification tools (CBMC, AFL++, ...), optional SPICE kernels, embedded Rust targets and cargo tools, `ws-devname`, cross-build starter files |
| **desktop** | LibreOffice, KeePassXC, VLC, GIMP, Inkscape, Déjà Dup, Firefox/Thunderbird policy files, spell-check languages. Each app has its background network features switched off |

| Profile | Modules |
|---|---|
| `work` | core + embedded |
| `personal` | core + desktop (add `embedded` in `profiles/personal.conf` if you want it) |

Make your own profile by copying a file in `profiles/`; it only needs
`PROFILE_MODULES=(...)` and may preset switches.

## Commands

| Command | Purpose |
|---|---|
| `./setup.sh --profile NAME` | Choose the profile (remembered afterwards) |
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

**Don't break Ubuntu.** No package is ever removed (`apt --no-remove`), no
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

**Checksums.** Files downloaded outside APT (installers, Helix, SPICE
kernels) are verified against SHA-256 values in the lock file. Without a
lock, checksums are recorded on first download (trust on first use) and
pinned by `--lock`. Compare them with the publisher's values if your process
requires it. Package managers (APT, cargo, uv/pip, npm) verify their own
downloads. Note: a pinned checksum of a *mutable* URL (e.g. the `rustup`
installer script) will refuse a later upstream change until you run
`--upgrade` and re-lock; that is the intended trade-off.

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
