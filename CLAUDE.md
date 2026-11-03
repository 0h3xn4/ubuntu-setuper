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

- **core** (setup.sh + workstation.conf + files/): always on.
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
- Self-tests: functions t_*, run via `run_test "title" fn [module]`; exit
  codes 0 pass, 77 skip (`skip`, `needs`, `needs_on`), 78 warning, other fail.

## Status
Done and checked in a sandbox (Ubuntu 24.04, no package archive, no network):
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

NOT verified on a real Ubuntu LTS install: nothing has been verified against
its actual package archive, and the desktop module's app settings are written
from documentation, not from a run of each app.

## Open tasks (in order)
1. In a VM with the latest Ubuntu LTS: `sudo apt update &&
   ./setup.sh --profile work --check` and the same for `personal`. Fix
   package names reported NOT AVAILABLE (module.conf / workstation.conf).
2. Run `./setup.sh --profile work` in the VM (snapshot first), then
   `--self-test`; repeat for `personal`.
3. Assumptions to verify on the real latest LTS (written without being able to test):
   - containers.conf `[engine] pull_policy = "never"` is accepted by podman
     (cache_images removes the file again if `podman info` fails).
   - Helix tarball name helix-<ver>-x86_64-linux.tar.xz (only if Helix isn't in apt).
   - `clangd --check` returns non-zero when the file has errors.
   - QEMU semihosting tests (t_emb_arm_qemu, t_emb_riscv_qemu): vector table,
     SYS_EXIT semantics (32-bit ARM passes the reason code directly; RV64 a
     pointer to a 2-word block).
   - Doc paths: cppreference under /usr/share/cppreference/doc/html/,
     POSIX man pages as section 3posix.
   - udev properties ID_VENDOR_ID / ID_MODEL_ID / ID_SERIAL_SHORT /
     ID_USB_INTERFACE_NUM on tty devices (ws-devname).
   - starship installer flags `-y -b <dir>`; uv versioned installer URL
     https://astral.sh/uv/<version>/install.sh.
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
