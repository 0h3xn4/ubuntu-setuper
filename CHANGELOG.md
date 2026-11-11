# Changelog

All notable changes to this repository. Newest first. The full life cycle of both profiles
has been run end to end in CI on Ubuntu 24.04 and 26.04 LTS (a VM and a container each); the
self-test has also been run once on the author's real machine (profile `work`, `--full`), which found
several problems CI could not see (aliases replaced by Oh My Bash, the offline lock blocking `uv`, Kate's plugins, the Format plugin, noisy basedpyright; see below). The desktop module's app settings have not been checked
in a desktop session. See `CLAUDE.md` for the open tasks.

## Unreleased

### Changed (`--reset-defaults` is now a COMPLETE reset; report: "the reset did not reset bash although I clearly asked to reset EVERYTHING")
- **What went wrong:** asked for "a complete reset to ubuntu default", I offered three scopes and built the one picked, "system settings". That
  version removed only the marked loader block from `~/.bashrc` and left `~/.bashrc.d`, `~/.inputrc`, the prompt, Oh My Bash, the tools and the
  packages in place, and a loader line an older manual told you to add without the marker was not even found. The question narrowed what you
  had asked for; it should not have.
- **Now, in this order:** (1) every undo file of earlier runs is replayed, newest first, which takes back precisely what those runs recorded
  (undo files of the reset modes themselves are never replayed: replaying a reset's undo would undo the reset); (2) the system settings, as
  before; (3) `~/.bashrc`, `~/.profile`, `~/.bash_logout` become Ubuntu's own copies from `/etc/skel` (yours go to the backup), bash the login
  shell; (4) everything the setup can put in your home folder is MOVED to `~/workstation-setup/reset-backup-<time>/home/`: `~/.bashrc.d`,
  `~/.inputrc`, starship's config, Oh My Bash, `.gdbinit`, `.npmrc`, the editors' and tools' configs, the releases in `~/.local/opt` and the
  setup's entries in `~/.local/bin` (your own scripts there stay), `~/.cargo`, `~/.rustup`, uv's and npm's folders, the caches the tools filled,
  podman's storage, record files older versions left in `~`; (5) the Ubuntu packages the setup installed (your decision, "remove them,
  safely"): read from apt's own history (entries with the setup's `--no-remove --no-upgrade`, so nothing that was already on the machine),
  purged only after `apt-get -s purge` shows that nothing else would go (otherwise none is removed and the plan names what would go), and the
  settings folders of their apps (Kate, GIMP, VLC, KeePassXC, Inkscape, Wireshark) moved too; (6) the Nerd Font, last.
- **Found by the first E2E run of this (#41), fixed:** the package list lost every library. `dpkg-query` names a Multi-Arch library with its
  architecture (`libc6:amd64`) and the comparison used the name without it, so about two thirds of the setup's packages fell out of the list.
  The guard did its job: the simulation showed those libraries going too, and in all eight jobs nothing was removed (on two runner VMs apt
  could not even resolve the partial removal). The check-all fake now prints library names the way the real `dpkg-query` does.
- **Found by the second run (#42), fixed:** Ubuntu's base system now stays even where the setup installed it. A container has no systemd until
  the install pulls it in, so systemd was on the list: on 26.04 apt refused (essential `systemd-sysv`) and removed nothing, on 24.04 it removed
  systemd. Packages marked Essential or Protected, of priority required or important, and everything they need stay installed. On the real
  runner VMs, where systemd was there before, the removal worked as intended: 620 and 668 packages removed, `--undo` reinstalled all of them in
  about two minutes.
- **Third run (#43): all eight jobs green.** On the four runner VMs (the case of a real machine) the reset removed 620 to 894 packages and
  `--undo` reinstalled every one of them (`gdb-multiarch`, `qemu-system-arm` gone and back), in about two to three minutes. In the four containers
  the guard still refused the package step, rightly: Ubuntu's own `systemd-resolved` needed one of the packages. Refusing everything for one
  shared package was too blunt, so now **a package stays when anything that stays still needs it** (Ubuntu's base, software you installed
  yourself, ...), and the plan names those; only the rest is removed.
- `--undo` takes all of it back except step 1 (that is what `./setup.sh` reinstalls): it moves everything back and reinstalls the packages
  (with apt's retries and a lock wait, marking the dependencies automatic again).
- **Not covered without the old undo files:** the lines the setup added to LibreOffice's and GIMP's settings, Kate's plugin selection and the
  default-app pins stay (those files are yours; only the undo files know what was added). A terminal profile where you named a font yourself.
- Tests: `t_reset_defaults` rewritten (old undo file replayed and renamed, unmarked loader line, skel copies, `~/.bashrc.d`, a Node release and
  its link moved while your own `~/.local/bin/mytool` stays, zsh to bash, the font last, packages from a fake apt history: the setup's two go, your
  `vim` stays, the guard refuses when the removal would take `ubuntu-desktop`; a second run finds nothing; `--undo` restores everything and
  reinstalls the packages). Broken on purpose six ways, each caught. The E2E's 13th phase checks the shell part and the package part for real.

### Changed (Ubuntu's own telemetry and services are never switched off; the user's decision)
- **Request:** "the script should not stop any ubuntu default telemetry"; asked for the scope, the answer was "all of Ubuntu's own
  services". Removed the switches `DISABLE_REPORTING_SERVICES` (apport, whoopsie, kerneloops), `DISABLE_MOTD_NEWS`, `DISABLE_FWUPD_REFRESH`,
  `DISABLE_APT_NEWS`, `DISABLE_NM_CONNECTIVITY_CHECK` and `SET_GNOME_PRIVACY` (location, automatic time zone, problem reports, usage
  statistics, web search), and with them the step "Privacy hardening". They were off by default, but `--full` turned them on. The
  setup now leaves all of these as Ubuntu ships them; the no-cloud rule is about the tools the setup installs. A switch that is still
  set (in a profile or the environment) is ignored with a warning that names `--reset-defaults`.
- **Not changed, flagged:** the desktop module's optional Firefox/Thunderbird policy files (`DESKTOP_BROWSER_POLICIES`, opt-in; they switch
  off the browser's own telemetry) and its Déjà Dup setting (local backups only). Both concern apps Ubuntu ships; whether they fall under the
  new rule is the user's call.
- **Verified in E2E run #39 (head `b5a3f19`, all eight jobs):** the new 13th phase compares the state of Ubuntu's services before and after the full
  install (`--full`) and found them unchanged on every VM; in the containers, which have no `systemctl` before the install, none was disabled or masked.

### Added (`./setup.sh --reset-defaults`: system settings back to Ubuntu's default, installing nothing; the user's request)
- **Request:** "a complete reset to ubuntu default only, meaning not setting up but rather just resetting"; scope chosen: system settings.
  It covers everything any version of the setup could change outside your own files: Ubuntu's services that Ubuntu enables (read from the
  packages' install scripts in the real 24.04 and 26.04 archives: `apport-autoreport.path`/`.timer`, `whoopsie.path`, `kerneloops.service`,
  `motd-news.timer`, `fwupd-refresh.timer`; not `whoopsie.service`, which Ubuntu does not enable), APT news, the setup's files below `/etc`
  (only when they still hold exactly the setup's content), Wireshark's non-root capture, the groups `dialout`/`wireshark`/`docker` (`plugdev`
  stays: Ubuntu gives it to the first user), the GNOME settings any version could change, the setup's global git defaults (only where the value
  is still the setup's) and the `~/.bashrc` loader block. Only what differs from Ubuntu's default is listed; it asks first (`--dry-run`, `--yes`),
  keeps backups, and `./setup.sh --undo` takes it back. Tools, fonts, editors, `~/.bashrc.d` and your files stay.
- **Why it matters for an existing install:** an earlier `--full` run switched Ubuntu's crash reports, MOTD news and the rest off, and its undo
  file predates the "Ubuntu's own default" rule for GNOME settings. `--reset-defaults` puts back Ubuntu's default directly.
- **Tests:** `t_reset_defaults` in `tools/check-all.sh` (fakes for `systemctl`, `pro`, debconf, `gsettings` and the groups, a fake `/etc`, real git:
  dry run, reset, a second run finds nothing, `--undo` restores; broken on purpose four ways to prove it fails), and a 13th E2E phase on real
  machines: the full install must leave Ubuntu's services exactly as they were, then `--reset-defaults` and `--undo` run against the real
  `systemctl`, `sudo` and git. README: A6 (now "left alone"), B13 (font only), a new "Reset to Ubuntu's defaults" section with the manual
  commands, a troubleshooting row; also two links that pointed at renamed sections.
- **Found by the reset in the first E2E run (#38), and fixed:** two settings the normal `--undo` left behind. Wireshark's non-root capture: its undo
  line was a plain `dpkg-reconfigure wireshark-common`, which only asks a person, so replayed by `--undo --yes` capture stayed allowed; it now sets
  the answer back to "no" itself. The global Git LFS filter that `git lfs install --skip-repo` adds (with `SET_GIT_DEFAULTS`) had no undo line at all; it
  has one now, when the run added it. The E2E's leftovers phase now checks both. The same run's phase 13 failed in the three container jobs on a test
  bug: a container has no `systemctl` before the install, so the "before" state was empty; it now checks there that no unit is disabled or masked.
- **Verified in E2E run #39 (head `b5a3f19`): all eight jobs passed all 13 phases** (24.04 and 26.04, runner VM and container, `work` and
  `personal`); self-test 34/37 (container) and 35/38 (VM), 0 failed, 0 warnings, only the usual skips. After the full install and `--undo`, the
  reset's dry run listed exactly what the test had planted (a disabled `motd-news.timer`, the inotify file, `init.defaultBranch`, the `~/.bashrc`
  block), plus the runner's own `docker` group on the VMs; no Wireshark and no Git LFS any more. The runner images' masked `fwupd-refresh.timer`
  was reported and left alone, as designed. Reset and `--undo` worked against the real `systemctl`, `sudo` and git. Slow mirror again: one
  container install took 62 minutes (110 MB at 60 kB/s), and one VM job was stopped at 104 minutes in the middle of a 463 MB download at about
  100 kB/s; its re-run passed in 13 minutes.
- **Not verified:** a real desktop session (the GNOME part of the reset).

### Changed (defaults: an install keeps Ubuntu's defaults, and `--undo` returns to Ubuntu's own default; the user's decisions)
- **Audit** (real 24.04 archive data, full install of both profiles: 98 chosen packages, about 850 with dependencies): no package registers the terminal,
  editor, graphical browser or window manager (only `lynx` as the text-mode `www-browser`, which Ubuntu does not set). So the report "Konsole replaced
  Terminator" was not the setup (the setup installs only `konsole-kpart`). Of the file types the new apps claim, 178 are decided by Ubuntu's own list
  (`gnome-mimeapps.list`: Kate does NOT take over text or code files), 95 are not (VLC for some audio/video formats, Inkscape for Visio/Corel, a KDE helper
  from `kio` for `ssh://`/`telnet://` links). Whether one actually wins depends on GNOME's fallback order, which needs a desktop session to see.
- **Guard (`KEEP_DEFAULT_APPS`, on by default):** before the first install the setup records `gio mime` (GNOME's own lookup) for every file type that has an
  app; after the installs it sets back each type whose app changed, as a user default in `~/.config/mimeapps.list`, and says which. `--undo` removes exactly
  those entries (and the file, if the setup created it). Nothing happens without a desktop. README B18 is the manual version (a note in A3 before installing).
- **`--undo` returns GNOME settings to Ubuntu's own default** (`gsettings reset`), no longer to the value found before (decided by the user: "ubuntus own default").
  Your own files that the setup only added to (Kate, Helix, app settings) still come back from their backups: "default" there would mean deleting your settings.
- Test: `t_default_apps` (fake `gio` and `mimeinfo.cache`: only the taken-over type is set back, a new type and an unchanged one are left alone, the undo keeps
  the user's own entries and removes the file it created, nothing happens without a desktop, `gset` records `gsettings reset`).
- **Not verified:** a real desktop session (the guard ran only against a fake `gio`); 26.04's packages were not audited for file types (only the terminal
  question, via the archive index).
- **Verified in E2E run #36 on the final code (head `94d00bc`):** the new step ran in all eight jobs and changed nothing, as expected on a fresh runner: "No file-type defaults to compare" on the
  first install (no `gio` and no desktop database before it), "No default app changed" on the second run of the `personal` jobs. So CI proves the step is harmless; the
  path that actually sets a type back has only been tested with the fake `gio`.

### Fixed (`--undo` no longer leaves an unreadable terminal halfway; report: a screenshot of a terminal full of empty boxes after running the undo)
- The undo removed the JetBrains Mono Nerd Font in the **middle** of its run. A terminal that uses that font draws every character as an empty box the
  moment the files are gone (also the text already on screen), so the rest of the undo, and its summary, could not be read. Now the font removal runs
  **last**, the plan shown before the question says so in plain words, and a last notice is printed right before it. Nothing else changes order (still
  newest first). Check: `t_undo_font` (a fake undo file: order C, A, then the font; warning only when a font is removed; broken on purpose once to prove it fails).
  README: the Undo section and a troubleshooting row (close the window and open a new one; pick another font if the profile names the removed one).
- **Verified in E2E run #36 on the final code (head `94d00bc`):** in every job's undo log "Removing the Nerd Font now" is printed before the last command, and the undo and leftovers phases pass.
- **Spaced-out letters in Terminator after the undo (my advice was the trap).** The README told you to untick Terminator's *Use the system fixed width font* and pick
  *JetBrainsMono Nerd Font Mono* by name. The setup never edits terminal profiles, so the undo, which removes the font, could not put that back, and Terminator fell back to
  a font that is not truly monospaced. The advice is now the opposite: tick *Use the system fixed width font* (Ubuntu's default; the system font is what `SET_GNOME_FONT`
  sets and `--undo` restores). The undo also checks Terminator's config and GNOME Terminal's profiles and, if one names the font itself, says which and how to go back.
- **Not caused by the setup:** a later report that Konsole had replaced Terminator as the terminal. The setup installs only `konsole-kpart` (Kate's
  embedded terminal panel: no program, no menu entry, no `x-terminal-emulator` registration); checked against the real 24.04 and 26.04 archives, where
  `konsole-kpart` does not depend on the Konsole app (it is the other way round) and Kate only *suggests* `konsole-kpart`.

### Fixed (a busy apt lock no longer stops the setup; report: a screenshot of `Could not get lock /var/lib/apt/lists/lock ... held by process (packagekitd)`)
- **The script waits for Ubuntu's own updater instead of failing.** `packagekitd` (behind Software Updater and GNOME Software) holds the apt lock for a while after login and after
  package installs, and apt fails at once. The script's first step was `apt-get update || die "...Check network / proxy settings."`: it died on that, with a message that pointed the wrong way.
  Now every `apt-get install` and `apt-get update` goes through `apt_run`, which retries a lock error every 5 s for up to `APT_LOCK_WAIT` seconds (default 300, `0` = do not wait),
  prints once who holds it ("packagekitd (PID 2826)"), and then gives up with apt's own message. Other errors still fail at once; the lock files are never touched.
  Found by testing apt 2.8.3 in a scratch directory: `-o DPkg::Lock::Timeout=6` did NOT make `apt-get update` wait (it failed after 0 s), so a retry loop is needed.
- Check: `t_apt_lock` in `tools/check-all.sh` (fake `sudo`: busy twice then free, busy forever, a non-lock error, `APT_LOCK_WAIT=0`; broken on purpose once to prove it fails), and the
  download lint now rejects any direct `sudo apt-get install|update` in `setup.sh`. README: the manual's `apt_wait` helper (A2), a troubleshooting row, the script reference.
- **Not verified for real:** a real `packagekitd` holding the lock (only a fake `sudo` and a lock held by a helper process on a scratch directory); the E2E never meets one.
- **Verified in E2E run #36 on the final code (head `94d00bc`):** no apt option error and no lock wait in any of the eight jobs' logs (apt was never busy there, so the waiting itself is covered by `t_apt_lock` only).

### Changed (the setup is gentler on the machine; report: "my laptop became considerably slower and laggy")
- **The run lowers its own priority (`LOW_PRIORITY`, on by default).** Nothing in the script did before: apt, cargo and the self-test ran at normal priority, and cargo
  compiled on every core with about 1 GB of RAM per `rustc`, which can push a laptop into swapping. `be_gentle` now `renice`s the setup process to 10 (never lowering a
  niceness you chose), puts it in I/O class best-effort 7 (apt, cargo and cmake inherit both, also through `sudo`), and exports `CARGO_BUILD_JOBS` and
  `CMAKE_BUILD_PARALLEL_LEVEL` = min(half the cores, free RAM / 1.5 GB, at least 1) unless you set them yourself. Nothing is persisted; `LOW_PRIORITY=0` switches it off.
  Applies to an install, `--upgrade` and `--self-test`. On desktop kernels each terminal is scheduled as one group ("autogroup"), so the RAM cap matters more than the priority.
- **A re-run no longer recompiles cargo tools you already have.** `cargo install --locked` was run for every tool on every run, so as soon as a newer `cargo-nextest` or
  `taplo-cli` existed each re-run spent 10+ minutes compiling it. Now only MISSING tools are installed (`cargo_tools_install`), like every other tool here ("left alone, only
  `--upgrade` moves it"); a lock pin that differs from the installed version is still installed, and `--upgrade` still reinstalls all.
- Tests in `tools/check-all.sh` (both broken on purpose once to prove they fail): `t_gentle` (real `renice`, inheritance by a child process, job caps against a fake `/proc/meminfo`,
  user settings win, a lower priority you chose is not raised) and `t_cargo_tools` (fake `cargo`: nothing installed twice, only the missing tool, `--upgrade`, pins).
- **Not known yet:** whether this removes your lag. The cause on your laptop was not measured (the diagnostics were not run), and a slowdown that outlasts the run would be something
  else (e.g. the desktop's file indexer or a language server). README troubleshooting has the one command that names the busy process.
- **Verified in E2E run #36 on the final code (head `94d00bc`): all eight jobs passed all 12 phases** (24.04 and 26.04, runner VM and container, `work` and `personal`); self-test 34/37
  (container) and 35/38 (VM), 0 failed, 0 warnings, only the usual skips. Every job logged "at most 2 parallel build jobs", compiled the cargo
  tools once and left them alone on the second run (no recompile). **The price, stated plainly:** container installs took 773 to 907 s against 535 to 717 s in run #32
  (VM installs 696 to 1013 s, about as before), most likely the 2-job build cap. One VM install (24.04 `work`) took 71 minutes; its log shows why: about 58 minutes of apt
  downloads from the runner's Ubuntu mirror at 33 to 750 kB/s (two packages needed apt's new retry), not the setup. One container job (24.04 `personal`) first failed in the
  workflow's own preparation, before the setup ran: Ubuntu's security server listed new perl packages it could not deliver yet (HTTP 404); its re-run passed.
  If you prefer speed over a calm machine: `LOW_PRIORITY=0`, or set `CARGO_BUILD_JOBS` yourself.

### Changed (downloads survive a slow or flaky mirror; request: "make it robust and resilient")
- **apt retries and times out.** Every `apt-get install` and `apt-get update` in `setup.sh` now runs with `-o Acquire::Retries=3 -o Acquire::http::Timeout=60
  -o Acquire::https::Timeout=60` (`APT_NET`). Before, apt used its defaults: no retry at all, so one failed fetch ended the whole batch (the script then retried
  package by package, but each of those also had zero retries). Command-line options only: no APT source and no package-owned configuration is touched.
- **curl treats a trickling transfer as failed.** The five copy-pasted `--retry 6 --retry-max-time 180 --connect-timeout 20` sets are one array, `CURL_DL`, with
  `--speed-limit 4096 --speed-time 60` added: a download below 4 KB/s for 60 s is aborted ("operation too slow", a retried error) instead of being waited for.
  Origin: E2E run #28, where one job made no progress for 78 minutes and its re-run needed 2h19m for the install because a runner mirror delivered at 33 kB/s.
- **Limits, stated plainly.** apt has no minimum-speed setting, so a mirror that is slow but alive is still waited for (the E2E jobs' `timeout-minutes: 150`
  stays as the backstop and was not changed); 33 kB/s is above the 4 KB/s guard on purpose, because a slow link that makes progress is not a failure.
  A whole-batch retry after `apt-get update` was considered and left out: with retries on every fetch the existing one-package-at-a-time fallback already is the second attempt.
- Check: `tools/check-all.sh` runs the real `fetch_verified`, `fetch_published` and `apt_install` against a fake `curl`/`sudo` and checks the flags, and lints `setup.sh`
  so a new download or `apt-get install` that skips `CURL_DL`/`APT_NET` fails (broken on purpose once to prove it fails). README manual helpers (A2), the README troubleshooting
  table and `docs/script-reference.md` describe it.
- **Verified: E2E run #32 on this change (head `59773ec`): all eight jobs passed all 12 phases** (24.04 and 26.04, runner VM and container, `work` and `personal`); self-test 34/37
  (container) and 35/38 (VM), 0 failed, 0 warnings, only the two usual skips (container images not cached in the container jobs, SPICE kernels off by default). Checked in the
  downloaded artifacts: no apt or curl option errors in any install log, every checksum-verified download and the Neovim install still worked, install phases 9 to 12 minutes.
  **Not shown by this run:** that the retries and the minimum-speed guard fire. No job hit a slow or failing mirror this time (no "Retrying", "Operation too slow" or `Err:` line in
  any log), so what is verified is that the new options are accepted everywhere and break nothing, plus the fake-driven check; behaviour under a real stalled mirror is untested.

### Added (Neovim as a second editor, on request: "users would also like nvim")
- **Neovim** (`INSTALL_NVIM`, on by default) next to Helix, which stays the default (`$EDITOR` is unchanged). Same rule as Helix and the
  other tools without an LTS line: the newest **upstream** stable release (`nvim-linux-x86_64.tar.gz` / `nvim-linux-arm64.tar.gz`, tag read from the
  redirect of the `latest/download` URL) goes to `~/.local/opt/nvim-<version>`, linked from `~/.local/bin/nvim`; Ubuntu's `neovim` (0.9.5 on 24.04,
  0.11.6 on 26.04) is only the fallback (recorded in the missing list, so the E2E fails on it); `NVIM_VERSION` (with the `v`; the lock pins it) and
  `NVIM_FROM_ARCHIVE=1` work like the Helix ones. The download is **trust on first use**, then pinned by the lock: a checksum file next to the release
  could not be confirmed from the development sandbox (the release page was not readable there). If the project does publish one, switching to
  `fetch_published` is a small follow-up.
- **`~/.config/nvim/init.lua`**, new file only (an `init.lua` of yours is never overwritten; with an `init.vim` of yours it is not added, because Neovim refuses to load both; the self-test then warns instead of failing). It is
  **plugin-free**: no plugin manager, so Neovim never downloads anything by itself, and it switches off the spell-file downloader and the node/perl/
  python3/ruby providers. It starts Neovim's built-in language-server client for the same local servers as Helix and Kate (clangd, basedpyright at
  "standard", ruff, rust-analyzer with clippy, taplo, bash-language-server, cmake-language-server; none for JSON/YAML), formats Python/Rust/TOML on save
  like Helix, and written to also work on the archive's 0.9.5 (the completion popup needs 0.11+).
- Self-test **"Neovim loads its configuration, quiet LSP"** (`t_nvim`): starts the real `nvim --headless` on a small Python file
  (`files/selftest/lsp/nvim_check.py`/`.lua`) and requires that basedpyright reports the one real mistake and none of the strict-mode diagnostics.
  Checks in `check-all.sh`: the install function against fake releases (install, failed download, second run). `e2e.sh`: `nvim` must come from
  upstream (`~/.local/bin`), the lock must pin `NVIM_VERSION`, nothing may be left behind. `ws-doctor` lists `nvim` (optional).
- Docs: README B17, big picture, release table, troubleshooting row; `docs/script-reference.md`; a Neovim page in the cheat sheet (for someone who has
  not used a modal editor: `Esc`, `:q!`, `:Tutor`). Written and unit-tested in the sandbox, which cannot run downloaded
  binaries; the first E2E from this commit was the real test and it passed on first contact (see Verified below). Interactive use (keymaps,
  completion popup, clipboard, format on save, the language servers other than basedpyright) is not covered by the headless test.

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
- **E2E run #28 on the Neovim commit (head `4fafeb4`): all eight jobs (24.04 and 26.04, runner VM and container, `work` and `personal`) passed all 12 phases**; self-test 34/37
  (container `work`/`personal`) and 35/38 (VM), 0 failed, 0 warnings, only the SPICE/container-image skips; one more passed test than run #26 in every job = the new
  `Neovim loads its configuration, quiet LSP`. **Neovim v0.12.6 was installed from upstream in all eight jobs** (none fell back to Ubuntu's package) and the real
  Neovim attached the real basedpyright at the "standard" level. One job (24.04 runner VM, `work`) had to be re-run alone: its first attempt made no progress for
  78 minutes (cancelled by hand) in the install step, whose partial log ends in apt `Get` lines from the runner's Azure Ubuntu mirror, and the re-run passed but its
  install phase took 8363 s because that mirror delivered 76 MB at 33 kB/s. A slow runner mirror, not the setup. The E2E jobs do have `timeout-minutes: 150` (the slow
  re-run came close to it); apt was run without retries (`Acquire::Retries` defaults to 0) and the `curl` downloads have retries but no minimum-speed guard, so a mirror that
  trickles instead of failing is never retried. The PR's own CI (static checks and the reduced real installs with the blocking
  self-test on 24.04 and the newest LTS) was green as well.
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
