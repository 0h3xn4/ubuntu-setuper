# Changelog

All notable changes to this repository. Newest first. The full life cycle of both profiles
has been run end to end in CI on Ubuntu 26.04.1 LTS (a VM and a container); it has not yet
been run on a machine with a desktop session. See `CLAUDE.md` for the open tasks.

## Unreleased

### Added
- **Kate** (`INSTALL_KATE`, on by default): the KDE text editor as a Debian package, with its
  language-server client pointed at the local servers (README B16).
- **Extra terminal tools** (`INSTALL_NICE_TO_HAVE`): zellij, difftastic (skipped where the archive
  lacks them); `cargo-nextest`; `wl-clipboard` and `xclip` so Helix can use the system clipboard.
- **ccache** is switched on for CMake builds when installed (with a self-test).
- **`ws-doctor`**: read-only, offline health check you can run without this repository.
- **`./setup.sh --undo [FILE]`** (`--dry-run`, `--yes`): replays an undo file newest-first.
- **`probe-rs` prebuilt** (`PROBE_RS_PREBUILT`, on by default) instead of a 10+ minute compile.
- **lazygit fallback** from the project's release where the archive has no package (24.04).
- `tools/check-all.sh`, `tools/manifest-diff.sh`, `tools/install-hooks.sh` (pre-commit hook) and a
  GitHub Actions workflow (static checks, plus `--check` and a real install on the newest LTS).
- README: troubleshooting table, "first day" page in the cheat sheet.

### Added (zsh users)
- **`./setup.sh --reset-shell`**: for someone who comes from zsh / Oh My Zsh. This setup is for bash (the shell
  files, the prompt and the offline lock live in `~/.bashrc.d`; zsh never loads them), so the command moves the
  zsh files (`~/.oh-my-zsh`, `~/.zshrc`, ...) into `~/workstation-shell-backup-<time>/` (nothing is deleted),
  restores `~/.bashrc` / `~/.profile` from `/etc/skel` if missing, and makes bash the login shell again. It lists
  every change and asks (`--dry-run`, `--yes`), records everything for `--undo`, and never removes the `zsh`
  package. README A7 does the same by hand; a unit test (`check-all.sh`) and a new E2E phase (real zsh, real
  `usermod`) cover it. The E2E phase passed in all four jobs (runner VM and container, `work` and `personal`).

### Verified
- End-to-end run on Ubuntu 26.04.1 LTS (GitHub runner VM and `ubuntu:latest` container, `work` and `personal`):
  all ten phases pass in all four jobs; self-test 33/36 (VM) and 32/35 (container) passed, 0 failed; Node.js 26
  from nodejs.org in every job; the RISC-V QEMU test passes.

### Fixed (found by the fifth end-to-end run)
- 26.04 moved RISC-V emulation out of `qemu-system-misc` into its own package: `qemu-system-riscv` is now in the
  embedded package list (before, no RISC-V emulator was installed on 26.04 and its self-test was skipped).
- The E2E test now treats a skipped RISC-V QEMU test as a failure, checks that the lock pins `NODE_LTS_VERSION`
  and that undo removes `~/.local/opt` and the node/npm/npx links.

### Changed (decisions by the user)
- **Node.js: the newest upstream LTS wins** over the archive's older one. `node_install` unpacks the release
  nodejs.org marks as the newest LTS into `~/.local/opt/node-<version>` (linked from `~/.local/bin`), checked
  against the project's published `SHASUMS256.txt`; no APT repository. `NODE_LTS_VERSION` pins it (the lock
  does), `NODE_FROM_ARCHIVE=1` or a failed download uses Ubuntu's `nodejs`/`npm`.
- **`embedded` is part of the `personal` profile** (core + embedded + desktop).
- **Networked apps may use the network naturally** (the stricter proposed definition was not accepted);
  the browser/mail decision is: keep Ubuntu's snaps, place only the optional policy files.
- Everyday desktop apps and languages: the defaults stay.

### Added (icons)
- `ls`/`ll`/`la`/`tree` (eza) show file icons when the JetBrains Mono Nerd Font is installed; `ll` is now a plain
  long listing like `ls -l` (use `la` for hidden files). `WS_ICONS=0` switches icons off, `WS_ICONS=1` forces them on.

### Added (end-to-end test)
- `tools/e2e.sh` and `.github/workflows/e2e.yml`: the full life cycle of a profile (full install,
  self-test, ws-doctor, idempotent re-install, manifest, lock, undo, leftovers) on GitHub runner VMs
  and in a newest-LTS container; manual, or on a PR titled with `[e2e]`.
- Fix found by reading the code for it: the sysctl drop-in is now recorded for undo as soon as it is
  written, and failing to apply it (container) only warns.

### Fixed (found by the first end-to-end run on Ubuntu 26.04 LTS)
- Package names that changed: `p7zip-full` is now `7zip`; `qemu-user-static` is now `qemu-user` + `qemu-user-binfmt`
  (both names also exist on 24.04).
- `containers.conf` (podman never pulls implicitly) is installed whenever podman is, not only with the image cache.
- Disabling a service no longer uses `--now` (fails without a running systemd, e.g. in a container): it disables,
  then stops on a best-effort basis. Its undo is `systemctl enable`.
- Undo now covers what was missing: Rust toolchains (and `~/.rustup` when this run created it), cargo tools, uv tools,
  global npm tools; the `podman rmi` undo no longer fails when the image is gone; undo commands find `~/.local/bin` and `~/.cargo/bin`.
- Privacy hardening now runs after all installs (a dependency re-enabled `motd-news.timer`); `containers.conf` is installed in the Containers step; `~/.rustup` ownership is decided before `rustup set` creates it.
- The `containers.conf` guard no longer removes the file when podman cannot run at all (a container): it only removes it if podman worked before the file and fails after.
- E2E test itself: lock phase SIGPIPE, runner images that already ship rustup/`gh`, container images that strip `/usr/share/doc`.

### Fixed (found by the first CI run on the newest LTS)
- `ws-doctor` no longer reports tools in `~/.local/bin` / `~/.cargo/bin` as missing when the
  (opt-in) shell loader is off.
- The ARM/RISC-V QEMU self-tests now capture stdout and stderr together and log QEMU's exit status
  and version. Cause of the CI failure: QEMU 10.2 prints the program's semihosting output on
  stderr (exit status was 0); the test only read stdout. Confirmed by the following CI runs.
- README: new "How well tested is this?" section, Troubleshooting in the contents, `ws-doctor` as
  the quick check in Part E, and the QEMU check in Part E redirects both streams.

### Changed
- **Publisher checksums instead of trust-on-first-use** for uv, rustup, starship, the Nerd Font,
  probe-rs and lazygit: the download is compared with the checksum the project itself publishes and a
  mismatch is refused. The installer scripts for uv, rustup and starship are no longer used.
- Release tags are read from the redirect of a `latest/download` URL, so no GitHub API call is needed.
- All package names checked against the real Ubuntu 24.04 archive (only `lazygit` is missing there);
  the end-to-end runs then checked them on 26.04 (see the "Fixed" section above).

## 2026-11-03 — `--full`, Nerd Font, Oh My Bash (PR #4)
- `./setup.sh --full`: switch on every opt-in system change at once.
- JetBrains Mono Nerd Font (user-only install); Oh My Bash as an opt-in from one pinned commit.

## 2026-11-03 — Opt-in system changes, no system upgrade, `--explain` (PR #3)
- System changes (services, `/etc` drop-ins, groups, GNOME settings, `~/.bashrc`, git config) are
  opt-in, one switch each. The `apt upgrade` step was removed; installs use `--no-upgrade`.
- `./setup.sh --explain`: plain-language tour of every step.

## 2026-11-03 — The README becomes a manual guide (PR #2)
- Step-by-step manual setup that mirrors the script; `tools/check-readme-sync.sh`.

## 2026-11-03 — Modules and profiles (PR #1)
- Core + `embedded` and `desktop` modules; `work` and `personal` profiles; one lock per profile.
- Review fixes: `--no-remove` everywhere, `INSTALL_FRAMA_C` consistency, `ws-devname` input validation,
  OpenOCD bound to localhost.
