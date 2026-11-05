# Changelog

All notable changes to this repository. Newest first. The full life cycle of both profiles
has been run end to end in CI on Ubuntu 24.04 and 26.04 LTS (a VM and a container each); the
self-test has also been run once on the author's real machine (profile `work`, `--full`), which found
several problems CI could not see (aliases replaced by Oh My Bash, the offline lock blocking `uv`, Kate's plugins, the Format plugin, noisy basedpyright; see below). The desktop module's app settings have not been checked
in a desktop session. See `CLAUDE.md` for the open tasks.

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

### Changed (the records live in one folder, not loose in your home directory)
- **The undo script, manifest, log and the generated cheat sheet now go into `~/workstation-setup/`** (your request; before,
  `workstation-undo-*.sh`, `workstation-manifest-*.txt`, `workstation-manifest-latest.txt`, `workstation-setup-*.log` and
  `WORKSTATION-CHEATSHEET.md` sat directly in `~`). `WS_OUT_DIR` picks another folder. An install run moves the old files in
  (never overwriting anything there); `--undo` finds undo files in the new folder and, as before, in `~`. `ws-help` looks in the
  new folder first. Your existing `~/.bashrc.d/10-workstation.sh` is never edited: if it is an earlier version that still looks for
  `~/WORKSTATION-CHEATSHEET.md`, a link is left there (recorded for `--undo`). The `--reset-shell` backup folder stays in `~`.
  Tests: `check-all.sh` checks the migration (moved, never overwritten, link only when needed); the E2E fails if any such file is
  loose in `~` after an install.

### Changed (you are not blocked from the network; Kate gets its terminal panel)
- **The strict offline lock is now opt-in** (`ENFORCE_OFFLINE_ENV`, default **0**; your request: "dont block me, as the user from the
  network"). `~/.bashrc.d/20-offline.sh` (`UV_OFFLINE=1`, `PIP_NO_INDEX=1`, `CARGO_NET_OFFLINE=true`) is an environment setting of your own
  terminal, so it blocked the commands you typed yourself (`uv pip install pandas-stubs` failed with "network disabled"). By default
  `uv`, `pip` and `cargo` now work as on any machine. What stays off are the tools' OWN background network features (update checks,
  telemetry, `podman` pulling by itself, uv downloading Pythons: `uv python install` is still blocked, ask if you want that
  relaxed). The local caches are still filled during installation. **An install that predates this change still has the file:**
  `rm ~/.bashrc.d/20-offline.sh` and open a new terminal (the setup never deletes your files). `ws-doctor` says what the lock does
  if it is there. The E2E now fails if a default install blocks `uv` or `cargo` in a new shell.
- **Kate's terminal panel works:** `konsole-kpart` (about 2 MB, the embedded terminal part, no network features) is installed with Kate.
  Kate only *suggests* it, so APT skipped it and the panel said "Konsole not installed". `t_kate` now checks for it.

### Fixed (an older install gets the new defaults)
- **The setup now adds missing defaults to settings files you already have** (the first real run of the new version: `basedpyright is quiet in the editors` FAILED
  on your machine because your `~/.config/kate/lspclient/settings.json` predates the quiet level and the setup never overwrites your files, so Kate stayed noisy). A
  re-run now adds what is MISSING to your Kate lspclient/formatting settings (recursively; every value you set stays) and the basedpyright level to your Helix
  `languages.toml` (only if you set none; the result must still parse, or the file is restored), with a backup under `~/.local/share/workstation/settings-backups/`
  and an undo record. The self-test message says what to do. New check `t_settings_migrate`. Stale wording about the "offline lock" in the shell step text and the
  opt-in table (it is opt-in since the earlier change) is corrected.
- The README troubleshooting has a row for the `yaml-language-server` self-test failure (an npm global that fetches schemas by itself).

### Verified (this batch)
- **E2E run #26 on the final code (head `79905b7`, the settings-migration fix): all eight jobs passed all 12 phases**; self-test 33/36 (container) and 34/37 (VM)
  on both releases, 0 failed, 0 warnings, only the SPICE and container-image skips. The PR's own CI (static checks, `--check`, reduced real installs with the
  blocking self-test on 24.04 and the newest LTS) was green too, the first time the blocking self-test step was seen passing on a pull request.
- **E2E run #24 on the final code (head `1bfb316`): all eight jobs (24.04 and 26.04, runner VM and container, `work` and `personal`) passed all 12 phases**; self-test 33/36
  (container) and 34/37 (VM) passed, 0 failed. It covered rustup/lazygit/uv/Helix/probe-rs from upstream, the opt-in offline lock (new shell not blocked), the records
  folder, Kate's plugin set and Format settings (`ws-pyformat` with the real ruff), and the real `basedpyright-langserver` started like Kate does (quiet on an untyped file).
  The run before it failed five jobs only on GitHub's HTTP 504 for the probe-rs download, which is why the retries were raised (below).

### Fixed (downloads ride out a short GitHub outage)
- **Downloads now retry for up to about a minute (6 tries, growing pauses) instead of 3 tries within seconds.** In one E2E run GitHub answered HTTP 504 for
  the probe-rs release in five of eight jobs at the same moment (the other three got the file): the step was reported as failed and the E2E failed on it,
  as designed, but 3 quick retries cannot outlast even a short CDN hiccup, for you or for CI. Applies to the project downloads (checksum files, tarballs,
  the lazygit asset list, the Node.js index). A real failure (404, a checksum mismatch) is still refused at once.

### Changed (the Python type checker is quiet in the editors)
- **basedpyright now checks at the "standard" level in Kate and Helix** (your question "why all these errors in kate editor?", answer "as per your
  recommendation"). Its own default, "recommended", is very strict and flooded working untyped code, and anything built on a library without
  type hints (pandas), with "Type of ... is unknown" / "Type annotation is missing ...". Kate gets it through a `settings` block on the Python
  server entry (works with both Kate versions: 23.08 sends it with `didChangeConfiguration`, 25.12 answers `workspace/configuration` from it), Helix
  through `[language-server.basedpyright.config.basedpyright]`. A project's own `pyrightconfig.json` / `[tool.basedpyright]` still wins; `ws-init` copies a
  `pyrightconfig.json` (standard) into new projects for the command line. New self-test `t_basedpyright_default` starts the real language server
  like Kate does and requires a clean result for a small untyped file (with a control that must be strict). **Existing installs keep their old
  settings files** (never overwritten): see the README troubleshooting row for the two edits. `uv python install` stays blocked, as you asked.
- README troubleshooting: a row for spaced-out terminal text (Terminator profile font).

### Added (Kate is set up, not just installed)
- **Kate's plugins are switched on** (your report: "all the plugins were missing"). Kate enables only 8 of its ~30 plugins by default
  and stores the choice per session. The setup now switches on Build, CMake Tools, Debugger, Symbol Viewer, Snippets, Formatting,
  Git Blame, File System Browser and Colored Brackets next to Kate's defaults (`KATE_PLUGINS_ON` in `workstation.conf`), and keeps
  Compiler Explorer (sends code to godbolt.org) and XML Validation (xmllint may fetch schemas) **off** (`KATE_PLUGINS_OFF`). It edits
  only the `[Kate Plugins]` keys of `~/.local/share/kate/anonymous.katesession` and your existing named sessions, backs each file up
  first and records the undo; a second run changes nothing. Quit Kate before running the setup (it rewrites those files when it quits).
  Plugin names were checked in the real Kate packages of 24.04 (23.08) and 26.04 (25.12). `t_kate` fails if a plugin of the set
  is missing from the installed Kate or not switched on; `kconfig_set` (the small helper that does the edit) has its own test.
- **Kate no longer complains on save** ("autopep8 is not installed", your report): the Format plugin I had switched on formats on SAVE by
  default and only knows autopep8 for Python. The new `~/.config/kate/formatting/settings.json` turns format-on-save off (it would reformat
  code, JSON and XML behind your back; `clang-format` switches it on for itself, so that is off too) and sends Kate's `autopep8` entry to
  `~/.local/bin/ws-pyformat`, which formats with ruff (the formatter of your hooks). `t_kate` runs it for real, `check-all.sh` checks how it
  calls ruff. My earlier plugin change should have set this up at once; I enabled the plugin without checking what it does on save.

### Changed (rustup and lazygit follow the same upstream-first rule)
- **rustup and lazygit now come from their projects' releases too**, for consistency with uv, Helix, starship and Node.js
  (your decision). rustup is `rustup-init` checked against the `.sha256` the Rust project publishes, installed in `~/.cargo`
  (`--default-toolchain none`, no shell-file edits, self-update still disabled); lazygit is the release tarball checked against
  its `checksums.txt`, in `~/.local/bin`. New pins `RUSTUP_VERSION` and `LAZYGIT_VERSION` (the lock writes them) and switches
  `RUSTUP_FROM_ARCHIVE` / `LAZYGIT_FROM_ARCHIVE`. lazygit is no longer in the apt package list (it would have installed the
  archive's older one first). Ubuntu's package is the fallback; the E2E no longer allows lazygit to be missing.

### Changed (the newest upstream release wins for uv, Helix and starship; the CI self-test blocks)
- **uv, Helix and starship now come from their projects' releases, not from Ubuntu's older package** (your decision,
  the rule Node.js already followed). They are unpacked into your home directory (`~/.local/bin`, Helix in
  `~/.local/opt`), uv and starship after checking the checksum the project publishes, Helix on trust-on-first-use
  (no checksum is published), all pinned by the lock (`UV_VERSION`, `HELIX_VERSION`, new `STARSHIP_VERSION`).
  Ubuntu's package is the fallback if a download fails (reported in the summary; the E2E fails on it).
  `UV_FROM_ARCHIVE`, `HELIX_FROM_ARCHIVE` and `STARSHIP_FROM_ARCHIVE` (default 0) give the old behaviour back;
  `ALLOW_CURL_INSTALLERS=0` forbids the downloads. A tool you already have is left alone; `--upgrade` installs the newest
  release in `~/.local/bin`, in front of any package from Ubuntu, which is never removed. `rustup` and `lazygit`
  still prefer the archive. `--check` now says which source each tool will use and which archive version it passes over.
  `helix_version` reads the release redirect first (no API call, no rate limit), the API only as a fallback; the Helix
  tarball name follows the CPU (`aarch64` too).
- **The CI self-test step is blocking** (it ended in `|| true`). It is the only CI step that proves the installed tools
  work; a lenient step lets a broken run look green; the QEMU test that made it flaky has passed in every recent run.
  It fails only when a test fails (warnings and skips do not). Reasoning is in `ci.yml`.
- **Verified:** E2E run #18 on the final code (head `a4f6899`, workflow_dispatch): all eight jobs (24.04 and 26.04, runner VM
  and container, `work` and `personal`) passed all 12 phases. uv 0.13.7 and Helix 25.07.1 came from upstream in every job and no
  job fell back to the archive's package; self-test 33/36 (VM) and 32/35 (container) passed, 0 failed, only the expected skips.
- Tests: `check-all.sh` checks the install order (`t_upstream_first`) and the install functions against fake releases
  (`t_upstream_install`); `e2e.sh` checks that uv and Helix land in `~/.local/bin`, that the lock pins uv, and has a new
  twelfth phase that installs starship from its real release (`--full` turns Oh My Bash on, which owns the prompt).

### Added (Ubuntu 24.04 LTS support: no forced upgrade)
- **Ubuntu 24.04 LTS and 26.04 LTS are both supported** (`SUPPORTED_UBUNTU` in `workstation.conf`). Before, an older
  LTS got an upgrade nag and a confirmation question. Now a supported release is accepted without fuss; a release older
  than 24.04 (Python 3.11+ is needed) and non-LTS releases are refused; a release newer than any listed asks first.
- **Release differences are data:** `PKG_SINCE` / `PKG_SINCE_NOTE` (a package that exists only from a release on, e.g.
  `qemu-system-riscv` from 26.04, is skipped with a note on 24.04, where RISC-V is part of `qemu-system-misc`).
- Verified for real against 24.04's archive (`--check`, both profiles: nothing missing but `lazygit`/`zellij`/`difftastic`,
  648 and 846 packages, none removed), and the tools' real 24.04 versions (eza 0.18 `--icons=auto`, fzf 0.44 key-bindings,
  `containers.conf` `pull_policy`, CMake 3.28 presets v6).
- CI: `ci.yml` and `e2e.yml` now run on 24.04 and on the newest LTS (8 E2E jobs). README "Which Ubuntu releases do I need?"
  compares the two. Unit test for the release logic in `tools/check-all.sh`.

### Fixed (found by the first Ubuntu 24.04 end-to-end run)
- **A failed optional download no longer breaks unrelated settings.** On 24.04 `lazygit` comes from its release; a curl
  failure inside a `pipefail` pipeline aborted the whole "Base CLI tools" step before the tealdeer privacy config was
  written (self-test: "tldr auto-update is not disabled"). The settings that switch things off now come first, and a
  failed `lazygit` download is reported and recorded, never fatal.
- **`fetch_published` no longer falls back to trust-on-first-use** when the project's checksum file cannot be fetched
  (it did, silently, for example for the Nerd Font during the same GitHub hiccup): that let anyone able to block the
  checksum file get a tampered download accepted. It now retries, then refuses; only a SHA-256 pinned in the lock can
  stand in. Unit-tested (`tools/check-all.sh`).
- Result of that run: 24.04 `work`/`personal` on the runner VM and `work` in the container passed all 11 phases
  (RISC-V QEMU via `qemu-system-misc`, Kate, Node.js 26 from nodejs.org, `lazygit` from its release).
- **Verified:** a second full run on the fixed code passed **all eight jobs** (24.04 and 26.04, runner VM and container,
  `work` and `personal`; self-test 33/36 on the VM and 32/35 in the container on both releases, 0 failed).

### Fixed (Kate's language-server settings were ignored)
- Kate supports ONE server per language with a flat `command` (checked in the source of 23.08.5 on 24.04 and 25.12.3 on
  26.04). The settings file nested a `servers` map inside each language, which Kate silently ignores, so Python, CMake and
  TOML help never worked in Kate. Now flat (Python = basedpyright); the self-test checks the shape, not just that the JSON parses.

### Fixed (found by the first run on a real machine)
- **Oh My Bash replaced the `ls`/`ll`/`la`/`grep` aliases** (no eza, no icons, a plain `ls -lh`): it defines its own
  while it loads, after `10-workstation.sh`. The aliases now live in `~/.bashrc.d/16-aliases.sh`, which loads after
  Oh My Bash. `ws-doctor` warns when `ls`/`ll` are not eza in a new shell and says how to fix it; the E2E shell phase now
  checks the aliases themselves (before it only checked environment variables). README B10/B15, troubleshooting,
  script reference, cheat sheet. For an existing install: `install -m 644 files/home/.bashrc.d/16-aliases.sh ~/.bashrc.d/`.
  Verified by an E2E run (all 11 phases, four jobs) with the real Oh My Bash switched on.
- The No-cloud self-test failed on a machine where `yaml-language-server` was already installed (not by this
  setup). The message now says where the tool comes from (APT package, npm global, snap, or by hand), how to
  find out and what to check before removing it, and that this setup never installs it. README B16 and the
  troubleshooting table explain it.

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
