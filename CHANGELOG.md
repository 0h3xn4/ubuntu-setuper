# Changelog

All notable changes to this repository. Newest first. The setup has not yet been
run end to end on a real Ubuntu LTS install; see `CLAUDE.md` for the open tasks.

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
- E2E test itself: lock phase SIGPIPE, runner images that already ship rustup/`gh`, container images that strip `/usr/share/doc`.

### Fixed (found by the first CI run on the newest LTS)
- `ws-doctor` no longer reports tools in `~/.local/bin` / `~/.cargo/bin` as missing when the
  (opt-in) shell loader is off.
- The ARM/RISC-V QEMU self-tests now capture stdout and stderr together and log QEMU's exit status
  and version. Cause of the CI failure: QEMU 10.2 prints the program's semihosting output on
  stderr (exit status was 0); the test only read stdout. Not yet confirmed by a CI run.
- README: new "How well tested is this?" section, Troubleshooting in the contents, `ws-doctor` as
  the quick check in Part E, and the QEMU check in Part E redirects both streams.

### Changed
- **Publisher checksums instead of trust-on-first-use** for uv, rustup, starship, the Nerd Font,
  probe-rs and lazygit: the download is compared with the checksum the project itself publishes and a
  mismatch is refused. The installer scripts for uv, rustup and starship are no longer used.
- Release tags are read from the redirect of a `latest/download` URL, so no GitHub API call is needed.
- All package names checked against the real Ubuntu 24.04 archive (only `lazygit` is missing there).

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
