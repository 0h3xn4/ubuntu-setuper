# CLAUDE.md — context for Claude Code

This repo sets up a workstation on the latest Ubuntu LTS release for software
development, for work and personal use (the user's work is spacecraft flight
software, hence the embedded module). It was designed in a claude.ai
conversation; this file carries that context over.

## The user
- Spacecraft flight software engineer; languages: Python, C, C++, Rust,
  plus JSON/YAML/XML.
- Terminal beginner who chose a terminal editor: Helix (not Neovim).
- Wants to understand and control the setup; explain changes, don't just make them.

## Hard requirements (never violate, fixed on EVERY profile, no switch)
1. **No cloud.** No installed tool may contact external services during
   normal use: no telemetry, update checks, online lookups, implicit
   downloads. Downloading DURING INSTALLATION is explicitly allowed.
   Cloud-connected tools (gh, schema-fetching JSON/YAML LSPs, snaps, ...)
   are never installed. Runtime enforcement: files/home/.bashrc.d/20-offline.sh,
   uv.toml, containers.conf, lazygit/tealdeer/npm/rustup settings, and the
   desktop module's per-app settings.
   Definition for inherently networked apps (PROPOSED by Claude, NOT yet
   confirmed by the user): allowed is traffic the user directs to a
   destination the user chose (opening a website, fetching mail from their
   own server, an explicit `podman pull`); not allowed is anything automatic
   or in the background (telemetry, update checks, crash reports, sync,
   accounts, recommendations, automatic lookups, implicit downloads).
2. **Don't break Ubuntu.** apt install always with --no-remove --no-upgrade;
   NEVER run `apt upgrade`/`full-upgrade` (the user rejected a system upgrade
   step: updating the system is Ubuntu's business, not this setup's); never edit
   package-owned config files (conffile prompts block unattended security
   updates); only NEW drop-in files in /etc (never overwrite an existing
   one: install_system_file); disable (never mask) services; no changes to
   kernel, boot, coreutils, architecture variants, APT sources.
   SYSTEM CHANGES ARE OPT-IN (the user decided): by default the setup only
   runs apt installs and writes NEW files under the home directory. Every
   change to /etc, services, groups, GNOME settings, ~/.bashrc or global git
   config has its own switch, OFF by default (OPT_IN_CORE in setup.sh and the
   modules' `opt_in` hook; listed by --explain/--check/summary). Never add a
   system-level change without a default-off switch, an entry in the opt_in
   table, a README section marked [opt-in] and a gated self-test.
   INSTALL_OH_MY_BASH is in that table although it is software, not a system
   change (the user asked for it as an opt-in that --full also turns on). Oh My
   Bash's own installer is NEVER used (it replaces ~/.bashrc and enables a
   GitHub update check): oh_my_bash() clones ONE pinned commit into
   ~/.local/share/oh-my-bash and 15-oh-my-bash.sh sets DISABLE_AUTO_UPDATE=true;
   10-workstation.sh skips starship while that file exists. The self-test fails
   if auto-update is not disabled.
   JetBrains Mono Nerd Font (INSTALL_NERD_FONT, default on) is a user-level
   install under ~/.local/share/fonts; extract only the two ligature families
   (not NL/Propo). NERD_FONT_VERSION and OH_MY_BASH_COMMIT are pinned by --lock.
   `./setup.sh --full` (or FULL_SETUP=1) is the "full setup": apply_full turns
   on every switch in OPT_IN_CORE + the modules' opt_in hook, except those the
   user set in the environment (ENV_AT_START snapshot). A new opt-in switch
   is picked up by --full automatically once it is in the opt_in table.
3. **Everything reversible.** Every system/config change calls record_undo.
4. **Always the latest stable, long-term supported version** (decided by the
   user), for the OS and for software in general:
   - OS: the latest Ubuntu LTS release. Never hardcode a release: os_check
     detects it at runtime via distro-info's offline database and warns on
     older or non-LTS releases. Release-specific features (e.g. APT 3's
     history) must be optional or explained as "on newer APT".
   - Software with an LTS line (Node.js, Java, container base images, ...):
     the newest LTS. Software without one (Rust, Helix, ruff, uv, ...): the
     newest stable release. Never betas, RCs, nightlies.
   - Never hardcode version numbers as defaults. Empty = "newest stable,
     resolved at install time"; exact versions live only in the lock files.
   - Lock vs latest: the lock is a deliberate snapshot of "newest at that
     time" (needed for reproducible work machines). `./setup.sh --upgrade`
     ignores the pins, installs the newest versions and self-tests; then
     `--lock` re-pins. Without a lock, every install gets the newest.
   - Container images: ubuntu:latest (= newest LTS). Older images only as
     deliberate, pinned exceptions.
   - OPEN QUESTION (ask the user): when the Ubuntu archive ships an older but
     Canonical-supported version and upstream has a newer LTS/stable release
     (e.g. Node.js), which wins? Current code prefers the archive (security
     updates via apt for the release's lifetime, no extra package sources).
     Components the OS itself depends on (system Python, gcc, glibc,
     systemd) must ALWAYS stay the archive version under requirement 2.

Note: Claude Code itself is cloud-connected. Per requirement 1 it must not be
installed on the target workstation. Develop this repo on another machine,
and test in a disposable VM with the latest Ubuntu LTS.

## Structure (modules and profiles)
One setup for flight-software work, other work, and personal machines.
Decisions by the user: no-cloud and don't-break-Ubuntu are strict on every
profile; scope for development stays as is (no new web / data science /
DevOps modules); the personal profile includes everyday desktop apps.
Neutral naming everywhere (project "workstation-setup", ws-help, ws-init,
ws-devname, /dev/ws/, ~/.local/share/workstation); flight-software specifics
belong only inside the embedded module.

- **core** (setup.sh + workstation.conf + files/): always on. Includes Helix, Kate
  (INSTALL_KATE; deb; ~/.config/kate/lspclient/settings.json merged over Kate's defaults,
  verified against Kate's source: JSON merge, same schema), ws-init, ws-doctor (standalone
  health check), `--undo`, ccache enabled via CMAKE_*_COMPILER_LAUNCHER in 10-workstation.sh.
- **modules/<name>/** (module.conf = switches and package lists; module.sh =
  hooks, install steps, self-tests; files/ = home files, templates,
  selftest sources, cheatsheet.md): `embedded` (cross compilers, QEMU,
  OpenOCD, serial/CAN, Wireshark, verification tools, SPICE, embedded Rust
  targets/cargo tools, ws-devname, embedded templates) and `desktop`
  (LibreOffice, KeePassXC, VLC, GIMP, Inkscape, Déjà Dup, Firefox/
  Thunderbird policy files, languages).
- **profiles/<name>.conf**: `PROFILE_MODULES=(...)`, may preset switches.
  `work` = core + embedded, `personal` = core + desktop. The chosen profile
  is remembered in ~/.config/workstation/profile.
- **locks/<profile>.lock** and **locks/<profile>.Cargo.lock**: one per profile.
- Load order in load_config: lock > profile > workstation.conf > module.conf
  (`: "${X:=default}"`, so first set wins; the environment beats all).
- Module hooks `mod_<module>_<hook>` are called through `module_collect`:
  pkg_groups, steps, home_files, groups, uv_tools, cargo_tools,
  rust_targets, py_packages, rust_crates, check, check_caches, selftests,
  nocloud_problems, nocloud_warnings, manifest_tools, manifest_extra,
  opt_in (lines "SWITCH|what it does"). A module's functions
  get `MODULE_DIR` at source time (modules store it, e.g. EMBEDDED_DIR).
- Starter files: files/templates -> ~/.local/share/workstation/templates/
  generic, module files/templates -> templates/<module>/. `ws-init` (a script
  in ~/.local/bin, not a shell function) copies generic; `ws-init --embedded`
  puts module variants first and adds `cmake/embedded-presets.json` to
  CMakePresets.json via jq `include`.
- The cheat sheet (~/WORKSTATION-CHEATSHEET.md) is generated from
  files/cheatsheet/00-core.md + modules/*/files/cheatsheet.md +
  99-maintenance.md and refreshed on every run.

### Desktop module rules
- Debs from the Ubuntu archive only. No snaps, no Flatpak/Flathub.
- Every app gets its background network features switched off through NEW
  files (never package-owned ones), and each setting gets a check in
  mod_desktop_nocloud_problems (feeds t_nocloud_policy).
- Browser and mail clients are NOT installed (Firefox/Thunderbird are snaps
  on Ubuntu). The module only places /etc/firefox/policies/policies.json and
  /etc/thunderbird/policies/policies.json when absent. Whether the snaps read
  them is UNVERIFIED: check about:policies. Whether to keep snaps at all is
  the user's/IT's decision. Safe Browsing is disabled by the policy (it polls
  Google); say so when asked.
- GNOME Online Accounts: leave unconfigured; the self-test WARNS (status 78,
  not a failure) if an account exists.

### Open questions for the user
- Confirm the "no cloud" definition above.
- Which everyday apps (defaults: LibreOffice, KeePassXC, VLC, GIMP, Inkscape,
  Déjà Dup; each has a DESKTOP_* switch) and which languages
  (DESKTOP_LANGUAGES is empty = English only).
- Browser and email client: keep the Firefox/Thunderbird snaps with the
  policy files, or something else?
- Should `embedded` be part of the `personal` profile?

## Checks you can run (and CI)
- `tools/check-all.sh` (all) or `--quick` (static; the pre-commit hook via
  `tools/install-hooks.sh`). CI (.github/workflows/ci.yml) runs it, then per profile
  `--check` against the real archive of `ubuntu:latest` and a reduced real install. It ran
  green (PR #5, #6); its self-test step is still non-blocking ("|| true") because the QEMU
  test failed (see Status): make it blocking once a CI run shows that test passing.
- The cloud sandbox is Ubuntu 24.04 with a reachable archive: `apt-get update` works, so
  `./setup.sh --profile X --check` verifies package names for real (only `lazygit` was
  missing on 24.04). It is NOT the latest LTS (26.04), so names may differ there.
- A real install (`./setup.sh` without --check) is BLOCKED in the cloud sandbox by its
  guard ("modify shared resources": sudo, packages, a test user with sudo rights), and
  must not be worked around. Real installs belong in the CI workflow (container) or in a
  VM of the user's. Do not create users/sudoers entries in the sandbox to attempt it.

- `tools/e2e.sh` = the full end-to-end test (see docs/script-reference.md); the "E2E" workflow
  runs it on GitHub runner VMs and a newest-LTS container, only manually or for a PR whose title
  contains "[e2e]". It is the ONLY way to test a real full install (the sandbox cannot). Fetch its
  logs with get_job_logs; the summary table is at the end of each job's log.

## Making the setup understandable
- Every step has a plain-language `STEP_WHY[title]` and `STEP_TOUCHES[title]`
  (core: setup.sh; modules: their module.sh). They are printed during the
  install and by `./setup.sh --explain` (changes nothing, no network).
  tools/check-readme-sync.sh fails if a step has no description.
- README.md has a "big picture" section (zones, opt-in table, paths, when the
  network is used, what it never does); keep it consistent with OPT_IN_CORE.

## Documentation: the README is a MANUAL, mirroring the script
- README.md is a step-by-step manual setup guide for users who distrust the
  script or want to control every step. Its sections follow the order of
  setup.sh's `step` calls and name the step/function they mirror. The
  automated route (profiles, locks, policies, file table) is documented in
  docs/script-reference.md.
- Keep them in step: after changing a package/tool list, a home file, a
  `step`, a `gset` call, a UNITS_* array or an opt-in switch, update README.md and run
  `tools/check-readme-sync.sh` (exit 1 = the README misses something). The
  README's code blocks were syntax-checked with bash -n and the helper,
  put/git_set/loader/template/cheat-sheet/LibreOffice/GIMP blocks were run
  in a scratch HOME. Changes in behaviour (not just lists) must be mirrored
  by hand.
- In the manual, `20-offline.sh` (the runtime lock) is installed LAST (D4);
  the script installs it early but clears its variables for its own run.

## Conventions in setup.sh
- `set -Eeuo pipefail`; each install step runs via `step` in a subshell so one
  failure doesn't abort the run; failures are summarized at the end.
- apt_install skips missing packages and records them (never fatal).
- write_config / install_file (core or module home files) /
  install_system_file / install_templates / record_undo / fetch_verified
  (SHA-256 TOFU, then pinned via lock) / add_to_groups / disable_units / gset.
- Use `if ...; then ...; fi`, not `cmd && cmd`, in functions run under set -e.
- NEVER locate code in setup.sh with a text search for "main() {": it also
  occurs inside self-test heredocs (C/C++ sources).
- Downloads outside APT: prefer `fetch_published URL DEST SUMS_URL [NAME]` (checks the
  checksum the PROJECT publishes; refuses a mismatch; records "<url> <sha> published"
  in the hash DB, which --lock skips) over `fetch_verified` (trust on first use + lock
  pin). Read a release tag with `release_tag_of <latest/download URL>` (redirect, no API).
  Never run a freshly downloaded binary in the cloud sandbox to "test" it: the auto-mode
  classifier blocks that; verify checksums and file lists instead.
- NEVER `rm -rf` a path built from $HOME in a command you run (the safety check blocks it);
  use a fresh scratch directory per test instead.
- Self-tests: functions t_*, run via `run_test "title" fn [module]`; exit
  codes 0 pass, 77 skip (`skip`, `needs`, `needs_on`), 78 warning, other fail.

## Status
Verified against the REAL Ubuntu 24.04 archive (apt lists were reachable): every package
name in the configs (only lazygit, zellij, difftastic are absent on 24.04; the script skips
or falls back), and `apt-get install -s --no-remove --no-upgrade` for both profiles shows no
removals. The Helix tarball name pattern exists on GitHub (HEAD 200); Helix publishes no
checksum file, so trust-on-first-use stays. Downloads checked for real against the
projects' published checksums: uv, rustup-init, starship, lazygit, Nerd Font, probe-rs
(also a tamper test). Oh My Bash and the Nerd Font install into a scratch HOME for real.
FULL E2E on Ubuntu 26.04.1 (PR #8, `tools/e2e.sh`): GREEN in all four jobs (VM and `ubuntu:latest` container,
work and personal), all 10 phases: --check, --full install, self-test (32 passed/0 failed on VM work, 31/0 in
the container work job), ws-doctor, idempotent re-run, manifest, lock, --undo of every undo file, leftovers.
It took four runs. Bugs it found in the SETUP: `p7zip-full` -> `7zip`, `qemu-user-static` -> `qemu-user` +
`qemu-user-binfmt` (both also exist on 24.04); undo records missing for rustup toolchains, cargo tools, uv
tools, npm globals; `podman rmi` undo not idempotent; `systemctl disable --now` fails without systemd running;
`containers.conf` only installed with the image cache; privacy hardening ran BEFORE package installs, which
re-enabled motd-news.timer (it now runs after all installs); the containers.conf guard removed the file
because `podman info` fails in Docker (it now removes only if podman worked before and fails after).
Bugs in the TEST: SIGPIPE in the lock phase, runner image ships rustup and `gh` (the VM job purges gh),
Docker image strips /usr/share/doc (workflow removes dpkg excludes). Limits: the container job runs with
CACHE_CONTAINER_IMAGES=0 and no systemd; no desktop session (GNOME settings, desktop-app settings and the
icons in a real terminal are still unverified). The Kate, Nerd Font and Oh My Bash steps DID run (self-test passes).
Job summaries of green jobs are NOT at the end of get_job_logs (only failures print them): download the
artifact (api.github.com/repos/OWNER/REPO/actions/artifacts/ID/zip with GITHUB_TOKEN) and read summary.md.
FIRST REAL CI RUN (PR #5, `ubuntu:latest` = newest LTS, both profiles; jobs green): `--explain`,
`--check` against the real archive, and a reduced REAL INSTALL as a normal user all worked.
The self-test on that install (work profile): 20 passed, 1 failed, 1 warning (shell loader
off, expected), 12 skipped. Passed for real: gcc/clang++/sanitizers, CMake+GoogleTest,
presets, ws-init, clangd, ruff+basedpyright (uv from the checksum-verified tarball), Helix
(tarball install, config loads), pre-commit offline, ccache, ws-doctor, ARM cross builds,
gdb-multiarch, OpenOCD configs, ws-devname. The one FAIL, `[embedded] ARM Cortex-M program runs
in QEMU`, was a TEST bug found from the next run's log (PR #6 diagnostics): QEMU 10.2.1 exits 0
but prints semihosting output on STDERR, and the test only read stdout. run_qemu_semihost now
captures both (`> qemu.txt 2>&1`); confirmed by the full E2E run. ws-doctor wrongly
reported tools in ~/.local/bin as missing when the shell loader is off: fixed (it searches
~/.local/bin and ~/.cargo/bin itself) and CONFIRMED in the real CI log (31 ok).
(In THAT early run Kate, the Nerd Font, Oh My Bash and Rust were switched off or not run; the full E2E above ran
them. The RISC-V QEMU test is still the one to look at in an E2E summary: it may have been skipped.)
Fetch CI logs with the github get_job_logs tool (job ids from the PR's check runs).

Also done and checked in the sandbox:
- shellcheck is clean on all shell files; bash -n; JSON/YAML/TOML parse.
- `--check` runs end to end for both profiles; `--self-test`, `--manifest`,
  `--lock` run; a generated lock is loaded again and wins over the config.
- Verified by tests: ws-init (generic, --embedded, never overwrites, jq
  include patch), CMake host presets with the include file, ws-devname
  refuses hostile udev strings, LibreOffice settings helper (create, merge,
  idempotent), install_* helpers and the desktop settings flow with a fake
  HOME/sudo.
Review fixes already applied: the system-upgrade step was removed entirely (apt install uses --no-remove --no-upgrade);
INSTALL_FRAMA_C handled consistently (needs INSTALL_VERIFICATION);
ws-devname validates vendor/product/serial/interface before writing a root
udev rule; OpenOCD example binds to 127.0.0.1.

Verified on a real Ubuntu 26.04.1 LTS (see FULL E2E above): package names, a full install of both profiles,
undo and re-runs. NOT verified: the desktop module's app settings (written from documentation, not from a
run of each app) and anything needing a desktop session.

## Open tasks (in order)
1. (DONE by the E2E workflow: names checked on 26.04, only lazygit/zellij/difftastic are absent and handled.)
2. (DONE in CI for both profiles on a runner VM and a container.) Still worth doing in the user's own
   VM with a desktop session (snapshot first): `./setup.sh --profile work --full`, then `--self-test`; same
   for `personal`. Check the icons in `ll` once the terminal uses the Nerd Font.
3. Assumptions to verify on the real latest LTS (written without being able to test):
   - containers.conf `[engine] pull_policy = "never"` is accepted by podman
     (install_podman_conf removes the file again only if podman worked before it and fails after it).
   - (verified) Helix tarball name helix-<ver>-x86_64-linux.tar.xz exists on GitHub.
   - `clangd --check` returns non-zero when the file has errors.
   - QEMU semihosting tests: ARM verified in CI (QEMU 10.2.1: SYS_EXIT 0x20026 -> exit status 0;
     semihosting output on stderr, hence 2>&1). RISC-V (t_emb_riscv_qemu: RV64 SYS_EXIT with a
     2-word block) still unverified: qemu-system-misc was not installed in the CI subset.
   - Doc paths: cppreference under /usr/share/cppreference/doc/html/,
     POSIX man pages as section 3posix.
   - udev properties ID_VENDOR_ID / ID_MODEL_ID / ID_SERIAL_SHORT /
     ID_USB_INTERFACE_NUM on tty devices (ws-devname).
   - Release asset names and the .sha256/checksum files of uv, rustup-init, starship,
     lazygit, Nerd Fonts and probe-rs were checked for real (not the installer scripts any more).
   - Kate: `QT_QPA_PLATFORM=offscreen kate --version` works headless (used by t_kate);
     the LSP settings file merge was verified in Kate's source, not by running Kate.
   - probe-rs: the unpacked binaries run (not executed in the sandbox); probe udev rules
     are a system file left to the user.
   - Desktop: LibreOffice AutoCheckEnabled item path in
     registrymodifications.xcu; KeePassXC keys GUI/CheckForUpdates and
     Security/IconDownloadFallback; VLC keys metadata-network-access,
     qt-privacy-ask, qt-updates-notif in vlcrc; GIMP `(check-updates no)`
     in gimprc under ~/.config/GIMP/<major.minor>/; Déjà Dup gsettings
     `org.gnome.DejaDup backend` value 'local'; Firefox/Thunderbird policy
     names and whether the snaps read /etc/<app>/policies/policies.json;
     `check-language-support -l <lang>` output.
   - OpenOCD `-c "bindto 127.0.0.1"` is accepted (cheat sheet example).
4. When the VM runs are clean: `./setup.sh --profile work --lock` and the
   same for personal, review, commit locks/.

## Safety rules for Claude Code in this repo
- Do not run `./setup.sh` (install mode) on the development machine: it uses
  sudo and changes the system. `--check`, `--self-test`, `--manifest` are
  read-only apart from files under ~/.local/share/workstation and ~ ;
  `--lock` only writes locks/<profile>.lock (use WORKSTATION_LOCK=/tmp/x.lock
  to test). For experiments point HOME at a scratch directory.
- Keep both policies above when changing anything; extend the no-cloud
  self-test (t_nocloud_policy / a module's nocloud_problems hook) when adding
  a tool that could phone home.
