# workstation-setup: script reference

This page documents the **automated** route (`setup.sh`). The step-by-step manual
route, which does the same things by hand, is the [README](../README.md).

Sets up a workstation on Ubuntu 24.04 LTS or 26.04 LTS (no upgrade to the newest
is required) for software development, for work and personal use: C/C++/Rust/Python toolchains, the
Helix and Neovim editors with language servers, git tooling, static analysis, offline
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
| **core** | Always installed, on every profile: bash setup, Helix and Neovim + language servers, git tooling, Python/C/C++/Rust, offline docs, privacy hardening (opt-in, runs after all package installs), offline caches, and the check / self-test / manifest / lock / undo machinery |
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
| `./setup.sh --undo [FILE]` | Take back an install run: replays the newest `~/workstation-setup/workstation-undo-*.sh` (or FILE) newest-first after listing every command and asking. `--dry-run` only lists, `--yes` skips the question. Never removes APT packages. Works on the manual guide's `~/workstation-setup/workstation-undo.sh` too (and on undo files that earlier versions left in `~`) |
| `./setup.sh --reset-defaults` | **Complete** reset to **Ubuntu's own default**, installing nothing, in this order: (1) the undo files of earlier runs are replayed, newest first (never those of the reset modes); (2) system settings; (3) `~/.bashrc`, `~/.profile`, `~/.bash_logout` become Ubuntu's own copies from `/etc/skel`, bash the login shell; (4) everything the setup can put in `~` is MOVED to `~/workstation-setup/reset-backup-<time>/home/` (`~/.bashrc.d`, `~/.inputrc`, starship and Oh My Bash, editor configs, `~/.local/opt` releases and the setup's `~/.local/bin` entries, `~/.cargo`, `~/.rustup`, uv and npm folders, caches, podman storage, loose record files); (5) the Ubuntu packages apt's own history shows the setup installed (entries with its `--no-remove --no-upgrade`) are purged after `apt-get -s purge` proves nothing else goes (otherwise none is removed and the plan names what would go), with the settings folders of their apps; (6) the Nerd Font, last. System settings in detail: Ubuntu's services that Ubuntu enables (`apport-autoreport.path`/`.timer`, `whoopsie.path`, `kerneloops.service`, `motd-news.timer`, `fwupd-refresh.timer`) on again when they are disabled (a masked one is reported, not touched), APT news on, the setup's files below `/etc` removed when they still hold exactly the setup's content (connectivity probe, inotify limits, Firefox/Thunderbird policies), Wireshark capture back to root only, groups `dialout`/`wireshark`/`docker` left (`plugdev` stays: Ubuntu gives it to the first user), GNOME settings any version could change reset to the schema default, the setup's global git defaults removed where the value is still the setup's, and the `~/.bashrc` loader block removed (backup kept). Only what differs from Ubuntu's default is listed. Lists first and asks (`--dry-run`, `--yes`); recorded, so `./setup.sh --undo` takes it back. Tools, fonts, editors, `~/.bashrc.d` and your files stay. A one-off command like `--undo`: not part of an install, `--full` never runs it |
| `./setup.sh --reset-shell` | For someone coming from **zsh / Oh My Zsh** (this setup is for bash): moves their zsh files (`~/.oh-my-zsh`, `~/.zshrc`, `~/.zshenv`, `~/.zsh_history`, ...) into `~/workstation-shell-backup-<time>/` (nothing is deleted; symlinks are moved as links), copies `~/.bashrc` / `~/.profile` from `/etc/skel` if missing, and makes bash the login shell (`sudo usermod -s /bin/bash`, effective at the next login). Lists every change first and asks (`--dry-run` only lists, `--yes` skips the question); `./setup.sh --undo` takes it back. The `zsh` package is never removed. An explicit one-off command like `--undo`: not part of an install, and `--full` does not turn it on |
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

**The records folder.** Everything the setup writes for you to read goes into one folder, `~/workstation-setup/`
(`WS_OUT_DIR=/some/folder` in the environment picks another one): the cheat sheet `WORKSTATION-CHEATSHEET.md`,
`workstation-undo-<time>.sh`, `workstation-manifest-<time>.txt` with `workstation-manifest-latest.txt`, and
`workstation-setup-<time>.log`. Earlier versions left these loose in `~`; an install run moves them in (never overwriting
anything there). The setup never edits your existing `~/.bashrc.d/10-workstation.sh`; if that earlier version still looks for
`~/WORKSTATION-CHEATSHEET.md`, a link is left there (recorded for `--undo`) and can be deleted once you replace the file.
The `--reset-shell` backup folder (`~/workstation-shell-backup-<time>/`) stays where it is: it holds your own zsh files.
`--reset-defaults` keeps the files it removes (and `~/.bashrc` before its edit) in `~/workstation-setup/reset-backup-<time>/`; its undo copies them back from there.

### Starter files in projects

`ws-init` copies the generic starter files (editorconfig, clang-format/tidy,
clangd, pre-commit, ruff, `pyrightconfig.json` with the Python type-checker level "standard", host CMake presets) into the current project and
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
(`~/workstation-setup/workstation-manifest-latest.txt`), so two machines can be compared with
`diff`.

## Policies (fixed, no switch, every profile)

**No cloud.** Downloading during installation is allowed. Afterwards, no tool
contacts external services: cloud-connected tools aren't installed, update
checks and telemetry are disabled by the tools' own settings, and podman never pulls an image on its own.
**You are never blocked from the network** (your decision): a command you type yourself (`uv add`, `uv pip install`,
`cargo add`, `podman pull`) works. The local caches (wheelhouse, crate cache, images) are filled during installation for
a machine that will have no network. The strict lock that limits `uv`, `pip` and `cargo` to those caches
(`files/home/.bashrc.d/20-offline.sh`, `ENFORCE_OFFLINE_ENV=1`) is opt-in, for air-gapped or policy machines; it also blocks
what you type yourself, because it is an environment setting of your terminal. An install that predates this decision
may still have the file: `rm ~/.bashrc.d/20-offline.sh`.
The shell files in `~/.bashrc.d` load in name order: `10-workstation.sh` (PATH, history, integrations),
`15-oh-my-bash.sh` (opt-in), `16-aliases.sh` (the everyday aliases; after Oh My Bash on purpose, because
Oh My Bash replaces `ls`/`ll`/`la`/`grep`), `20-offline.sh` (the opt-in strict offline lock).
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
`TUNE_INOTIFY`, `SET_GNOME_FONT`, `JOIN_DOCKER_GROUP`,
`ENABLE_SHELL_LOADER` (the ~/.bashrc block), `SET_GIT_DEFAULTS`, `INSTALL_OH_MY_BASH`
(Oh My Bash from one pinned commit, loaded from `~/.bashrc.d` with its update
check off; its own installer is never used; it replaces the starship prompt), and the
modules' `JOIN_SERIAL_GROUPS`, `JOIN_WIRESHARK_GROUP`,
`DESKTOP_BROWSER_POLICIES`. `--explain`, `--check` and the install summary
list them with their state. Without `ENABLE_SHELL_LOADER` the shell setup
is installed but inactive (the summary prints the line to add yourself).

**Ubuntu's own services and telemetry are never touched** (decided by the user: the setup must not stop
Ubuntu's default telemetry, and leaves all of Ubuntu's own services as Ubuntu ships them). Crash reports
(apport, whoopsie, kerneloops), `motd-news`, the `fwupd` refresh, APT news, NetworkManager's connectivity
probe and GNOME's privacy settings stay as they are. The no-cloud policy above is about the tools the setup
installs. Older versions had switches for these (`DISABLE_REPORTING_SERVICES`, `DISABLE_MOTD_NEWS`,
`DISABLE_FWUPD_REFRESH`, `DISABLE_APT_NEWS`, `DISABLE_NM_CONNECTIVITY_CHECK`, `SET_GNOME_PRIVACY`); they are
gone, the script warns if one is still set, and `./setup.sh --reset-defaults` puts back what such a version changed.

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
`~/workstation-setup/workstation-undo-<timestamp>.sh`. Debs from the Ubuntu archive only: the
desktop module installs no snaps and no Flatpaks.

**Ubuntu releases.** `SUPPORTED_UBUNTU` in `workstation.conf` lists the LTS releases the setup is
verified on (24.04 and 26.04): every package name checked against that release's real archive and the full
end-to-end test run on it in CI. Any of them works; **nobody has to upgrade to the newest**. Releases older than the
oldest listed one are refused (their tools are too old), a non-LTS release is refused, a release newer than any listed
one asks for confirmation (run `--check` first). `PKG_SINCE` lists packages that exist as separate packages only from a
given release on (`qemu-system-riscv` from 26.04; on 24.04 RISC-V is in `qemu-system-misc`): they are skipped on older
releases with a note, not a warning. To add a release: add it to `SUPPORTED_UBUNTU` only after `--check` on its real
archive is clean and the E2E workflow is green on it (add it to the matrices in `.github/workflows`).

**Versions.** For software with an LTS line, the newest LTS; otherwise the newest stable
release. What Ubuntu itself ships is whatever your supported release has (Canonical patches it). Never betas, release candidates or nightlies. A lock file is a
deliberate snapshot of "newest at that time"; `--upgrade` moves forward.
**Node.js** is the one tool with an LTS line that is installed, and there the newest *upstream* LTS
wins over the archive's older Node.js (your decision): the setup unpacks the release from nodejs.org
(its index says which is the newest LTS) into `~/.local/opt/node-<version>`, linked from `~/.local/bin`,
after checking it against the `SHASUMS256.txt` the project publishes. No APT repository is added.
`NODE_LTS_VERSION` pins a release (the lock does it), `NODE_FROM_ARCHIVE=1` uses Ubuntu's own
`nodejs`/`npm`, which is also the fallback if the download fails. System components (Python, gcc,
glibc, systemd) always stay the archive version.
**uv, Helix, Neovim, starship, rustup and lazygit** (no LTS line) follow the same rule, also your decision: the newest *upstream*
release wins over an older archive package. Each is unpacked into your home directory (`~/.local/bin`; Helix in
`~/.local/opt/helix-<version>`, linked from `~/.local/bin/hx`; Neovim in `~/.local/opt/nvim-<version>`, linked from
`~/.local/bin/nvim`), uv and starship after checking the checksum their project publishes, Helix and Neovim on
trust-on-first-use (for Neovim a checksum file could not be confirmed). `UV_VERSION`, `HELIX_VERSION`, `NVIM_VERSION` (with the `v`),
`STARSHIP_VERSION`, `RUSTUP_VERSION` and `LAZYGIT_VERSION` pin a release (the lock does it); `UV_FROM_ARCHIVE=1`,
`HELIX_FROM_ARCHIVE=1`, `NVIM_FROM_ARCHIVE=1`, `STARSHIP_FROM_ARCHIVE=1`, `RUSTUP_FROM_ARCHIVE=1` and `LAZYGIT_FROM_ARCHIVE=1` prefer Ubuntu's package; `ALLOW_CURL_INSTALLERS=0` forbids the downloads (Ubuntu's package
is used). Ubuntu's package is also the fallback if a download fails, and then the summary lists it as "newest
release (used the archive's)". A tool you already have is left alone; `--upgrade` installs the newest release in
`~/.local/bin` (rustup: `~/.cargo/bin`, updated in place), in front of any package from Ubuntu (never removed). rustup is
`rustup-init` with its published `.sha256`; the Rust toolchain itself is always the newest stable (`RUST_TOOLCHAIN`).

**Checksums.** Where the project publishes a checksum (uv, rustup-init, starship, lazygit,
probe-rs, the Nerd Font, Node.js), the download is compared with *that* and a mismatch is refused. If the
published checksum itself cannot be fetched (after retries), the download is **refused**, never trusted blindly;
only a SHA-256 pinned in the lock file can stand in for it. Other
downloads outside APT (the Helix and Neovim tarballs, SPICE kernels) are verified against SHA-256 values in the
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
| `tools/e2e.sh --profile P --i-know-this-machine-is-disposable` | Full end-to-end test on a DISPOSABLE Ubuntu machine (13 phases; the eleventh is a zsh user: real zsh, `--reset-shell`, `--undo`; the twelfth installs starship from its real release; the thirteenth checks that the full install left Ubuntu's own services as they were, then puts what an older version could leave behind back with `--reset-defaults` and restores it with `--undo`): explain/check, full install, self-test (a skipped RISC-V QEMU test counts as a failure), `ws-doctor` in a new shell, shell checks, idempotent re-install, manifest, lock (must pin the Rust toolchain, uv and, when installed, Node.js), uv, Helix, Neovim and lazygit must come from upstream (`~/.local/bin`, not Ubuntu; rustup too in the container jobs), the default install must not block `uv`/`cargo`, no record file may be loose in `~`, `--undo`, leftovers (incl. `~/.local/opt` and the node/npm/npx links). Env: `E2E_SWITCHES`, `E2E_ALLOW_FAILED_STEPS`, `E2E_ALLOW_MISSING`, `E2E_LOG_DIR`. `--plan` shows the phases. Run by `.github/workflows/e2e.yml` |
| `tools/manifest-diff.sh A B` | Compare two manifests (two machines, or manual vs scripted setup), ignoring host, user, CPU, kernel, hashes and dates |
| `tools/install-hooks.sh` | Enable the git pre-commit hook (`check-all.sh --quick`) in this clone |

CI (`.github/workflows/ci.yml`): `check-all.sh` on every push and PR, then for each profile a
`--check` against the real archive and a reduced real install in a container, on 24.04 and on the newest LTS,
followed by the self-test. **The self-test step blocks** (a failing test turns the workflow red): it is the only CI step that proves
the installed tools work, a lenient step ("|| true") lets a broken run look green, and the QEMU test that
once made it flaky has passed in every recent run. It fails only when a test FAILS; warnings and skips do not. The
`ws-doctor` call after it stays informational.
The E2E workflow (`.github/workflows/e2e.yml`, eight jobs: runner VM and container, on 24.04 and the newest LTS, each for `work` and `personal`; about 12 to 22 minutes per job, started manually (Actions > E2E > Run workflow, or the API's workflow_dispatch on any branch, no pull request needed) or by a PR titled with `[e2e]`)
runs `tools/e2e.sh` for both profiles on a GitHub runner VM and in an `ubuntu:latest` container. It
purges the runner's preinstalled `gh` first and removes the container image's dpkg excludes, so the
machine looks like a normal Ubuntu install. Results of the latest runs: README, "How well tested is this?".

Health check: `ws-doctor` (installed in `~/.local/bin`, read-only, offline, no repository needed)
reports missing tools, editor and shell setup, and the no-cloud settings in seconds; `--self-test` is
the full verification.

## Default apps: `KEEP_DEFAULT_APPS`

An apt install can make a new app the default for a file type that Ubuntu's own list (`/usr/share/applications/gnome-mimeapps.list`) does not
decide. Audited for the full install on 24.04 (real archive: 98 chosen packages, ~850 with dependencies): no package registers the terminal,
editor or graphical browser (only `lynx` as the text-mode `www-browser`, which Ubuntu does not set); 178 claimed file types are decided by
Ubuntu's list; 95 are not (VLC for some audio/video types, Inkscape for Visio/Corel, `ktelnetservice5` from KDE's `kio` for `ssh://`/`telnet://`).
With `KEEP_DEFAULT_APPS=1` (default) `defaults_snapshot` records `gio mime` for every type in `mimeinfo.cache` before the first install, and
the step "Keep default apps" sets back each type whose app changed, as a user default in `~/.config/mimeapps.list`; `--undo` removes exactly
those entries (one python command in the undo file) and the file if the setup created it. Nothing happens without a desktop. Test: `t_default_apps`
(fake `gio`). `gset` (GNOME settings) records `gsettings reset` for `--undo`: Ubuntu's own default, the user's decision.

## A busy apt lock: `APT_LOCK_WAIT`

Ubuntu's own updater (`packagekitd`) holds the apt lock for a while after login and after package installs, and apt then fails at once
("Could not get lock /var/lib/apt/lists/lock. It is held by process N (packagekitd)"). Every `apt-get install` and `apt-get update` of the script
goes through `apt_run`, which retries a lock error every 5 s for up to `APT_LOCK_WAIT` seconds (default 300, `0` = do not wait), prints once
who holds the lock, then gives up with apt's own message. Any other error returns at once; the lock files are never touched. apt's own
`-o DPkg::Lock::Timeout` is not enough: it does not cover the lists lock of `apt-get update` (tested with apt 2.8.3). The preflight error
message no longer blames the network for this. Test: `tools/check-all.sh` (`t_apt_lock`, fake `sudo`), plus a lint that rejects a direct
`sudo apt-get install|update` in `setup.sh`.

## Resource use: `LOW_PRIORITY`

A laptop became slow and laggy during a run (the compiles use every core and about 1 GB of RAM per job). With `LOW_PRIORITY=1` (the
default; `LOW_PRIORITY=0` switches it off) `be_gentle` runs at the start of an install, `--upgrade` and `--self-test`: it `renice`s the
setup process to 10 (never *lowering* a niceness you chose), puts it in I/O class best-effort 7, and exports `CARGO_BUILD_JOBS` and
`CMAKE_BUILD_PARALLEL_LEVEL` = min(half the cores, free RAM / 1.5 GB, at least 1) unless you set them. Children (apt, cargo, cmake,
also through `sudo`) inherit the priority; nothing is persisted. Cargo tools that are already installed are left alone (a re-run does
not recompile them for a newer release; `--upgrade` does, and a lock pin that differs from the installed version is installed).
Tests: `tools/check-all.sh` checks the real `renice` inheritance, the job caps with a fake `/proc/meminfo`, and the cargo skip logic
with a fake `cargo`.

## Downloads and checksums

**Network resilience.** Every download goes through two shared option sets in `setup.sh` (command-line options only, no APT source
or package-owned configuration is touched): `APT_NET` (`Acquire::Retries=3`, 60 s timeouts on silent HTTP/HTTPS connections) for
every `apt-get install` and `apt-get update`, and `CURL_DL` (`--retry 6 --retry-max-time 180 --connect-timeout 20 --speed-limit 4096
--speed-time 60`) for every `curl` download, so a transfer that stays below 4 KB/s for 60 s counts as stalled and is retried instead
of being waited for. apt has no minimum-speed option: a mirror that is slow but alive is still waited for, and the E2E jobs'
`timeout-minutes: 150` is the backstop. `tools/check-all.sh` runs the real functions against a fake `curl`/`sudo` and lints `setup.sh`:
a new download or `apt-get install` that skips the shared options fails the check.

Where the project publishes a checksum, the download is compared with *that* checksum and a
mismatch is refused (`fetch_published`): uv, rustup (`rustup-init`), starship, the Nerd Font
(`SHA-256.txt`), probe-rs and lazygit (`checksums.txt`). For the rest (the Helix and Neovim tarballs) the
SHA-256 is recorded on first use and pinned by `--lock` (`fetch_verified`). The release tag of a
`latest/download` URL is read from its redirect, so no GitHub API call is needed. `PROBE_RS_PREBUILT=0`
compiles probe-rs with cargo instead; `lazygit` is taken from its release (the newest upstream release wins over the archive's).
