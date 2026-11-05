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
   are never installed. Runtime enforcement: uv.toml, containers.conf, lazygit/tealdeer/npm/rustup
   settings, and the desktop module's per-app settings (the tools' OWN background network features).
   DECIDED by the user ("dont block me, as the user from the network"): the USER is never blocked from the
   network. The strict env lock files/home/.bashrc.d/20-offline.sh (UV_OFFLINE=1, PIP_NO_INDEX=1,
   CARGO_NET_OFFLINE=true) applied to the user's own terminal and blocked what they typed, so it is OPT-IN now
   (ENFORCE_OFFLINE_ENV default 0, for air-gapped/policy machines). What requirement 1 forbids is a tool contacting
   the network by itself (telemetry, update checks, implicit downloads), not a command the user types. An older
   install may still have the file; the setup never deletes user files: tell the user `rm ~/.bashrc.d/20-offline.sh`.
   Still blocked on purpose, ask before changing: `uv python install` (python-downloads = "never", system Python).
   Inherently networked apps (browser, mail): the user did NOT confirm Claude's proposed strict
   definition ("only traffic the user directs"). Their answer: such apps "of course might have
   network access, naturally". So the setup does not try to cut off the network use that is the
   app's purpose (browsing, fetching mail). The hard requirement stays strict for everything the
   SETUP installs: dev tools, language servers, package managers, no telemetry/update checks/
   implicit downloads. Per-app hardening already in the desktop module (update checks, metadata
   lookups, crash reports of everyday apps) stays as is; do not extend it to browser/mail behaviour
   beyond the optional policy files. Safe Browsing (polls Google) is switched off by the Firefox
   policy file from before this answer: it is a security trade-off, mention it and ask before
   changing it either way.
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
   - OS: DECIDED by the user: users on an OLDER Ubuntu LTS (24.04) must be able to use the setup
     WITHOUT upgrading, and everything must be compatible with their release. SUPPORTED_UBUNTU in
     workstation.conf lists the verified LTS releases ("24.04 26.04"); os_check accepts any of them silently (an
     info line only), refuses a release older than the oldest (22.04: no Python 3.11 tomllib etc.) and non-LTS,
     and asks for confirmation on a release newer than any listed (verify first). A release is added ONLY after
     (1) `--check` on its real archive is clean (the sandbox is 24.04; the 26.04 index is readable at
     archive.ubuntu.com/ubuntu/dists/resolute/{main,universe}/binary-amd64/Packages.gz) and (2) the E2E is green
     on it (matrices in ci.yml and e2e.yml). Release differences are data, not scattered if-statements:
     PKG_SINCE / PKG_SINCE_NOTE in workstation.conf (a package that exists only from a release on is skipped with a
     note on older ones; today qemu-system-riscv from 26.04, on 24.04 RISC-V is in qemu-system-misc). Features of
     newer releases (e.g. APT 3's history) must be optional or explained as "on newer APT". Components of a
     release are whatever that release ships (24.04: Kate 23.08, Python 3.12, QEMU 8.2, archive Node 18 which is
     EOL: the upstream-LTS rule matters most there); upstream-downloaded tools are the newest on both.
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
   - DECIDED by the user: when the Ubuntu archive ships an older version and upstream has a
     newer LTS, the NEWEST UPSTREAM LTS WINS. Implemented for Node.js (the only installed tool with
     an LTS line): node_install() unpacks the release nodejs.org's index.json marks as newest LTS into
     ~/.local/opt/node-<ver> (links in ~/.local/bin), checked with fetch_published against the
     project's SHASUMS256.txt; NO APT repository (no NodeSource). NODE_LTS_VERSION pins (lock),
     NODE_FROM_ARCHIVE=1 or a failed download falls back to the archive's nodejs/npm (the fallback is
     recorded in MISSING_FILE so the E2E flags it). NOT extended to tools without an LTS line
     (uv, Helix, starship, rustup, lazygit used to prefer the archive when it had them: DECIDED by the user later,
     "upstream please" and "for consistency sake do it": the newest upstream release wins for these five as well, see below).
   - DECIDED by the user: uv, Helix, starship, rustup and lazygit (no LTS line) also take the newest UPSTREAM stable release over an
     older archive package. install_upstream_first() (setup.sh) holds the rule: not installed -> release (uv and
     starship checked with the checksum the project publishes, Helix trust-on-first-use + lock pin) into ~/.local;
     a failed download -> the archive's package, written to MISSING_FILE ("<tool> newest release (used the
     archive's)") so the E2E fails on it; UV/HELIX/STARSHIP_FROM_ARCHIVE=1 prefers the archive;
     ALLOW_CURL_INSTALLERS=0 uses the archive silently; an already installed tool is left alone, `--upgrade`
     installs the newest release in ~/.local/bin (in front of Ubuntu's package, never removed). Pins: UV_VERSION,
     HELIX_VERSION, STARSHIP_VERSION (v-prefixed tag), RUSTUP_VERSION, LAZYGIT_VERSION (v-prefixed tag). rustup and
     lazygit followed on request ("for consistency sake do it"): lazygit is NOT in PKGS_BASE any more (it would
     install the archive's first); rustup_install_upstream reads the version from the checksum-verified rustup-init
     itself (so it always downloads, then skips the install if that version is there) and updates ~/.cargo in place;
     E2E_ALLOW_MISSING no longer allows lazygit. Tests: check-all t_upstream_first (the order, with fakes), t_upstream_install
     (the install functions against fake releases), e2e.sh checks uv/hx land in ~/.local/bin and phase 12
     installs starship for real (--full turns Oh My Bash on, which owns the prompt, so the main install skips it).
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
  `work` = core + embedded, `personal` = core + embedded + desktop (embedded is in personal by the
  user's decision; `PROFILE_MODULES=(embedded desktop)`). The chosen profile
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
- The cheat sheet (~/workstation-setup/WORKSTATION-CHEATSHEET.md) is generated from
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

### zsh / Oh My Zsh users (`--reset-shell`)
The setup is BASH-ONLY (decided by the user: "the user would rather want to get rid of zsh ... some kind of factory
reset in order to be able to use your setup", i.e. NO zsh support). `./setup.sh --reset-shell` (reset_shell_mode)
moves the zsh dotfiles (ZSH_FILES) into ~/workstation-shell-backup-<time>/ (never deletes; symlinks move as links),
copies a missing ~/.bashrc and ~/.profile from /etc/skel, and `sudo usermod -s /bin/bash` if the login shell is zsh.
It lists everything and asks (--dry-run, --yes), records every step for --undo (backup rmdir recorded FIRST so it runs
last), and NEVER removes the zsh package (requirement 2: no package removal; it only prints the apt command).
Deliberate exception to "every system change has a default-off switch in the opt_in table": it is an explicit one-off
mode like --undo, not part of an install, and --full does not turn it on (the usermod only happens because the user
ran this command and confirmed). Without a reset, zsh sessions never load ~/.bashrc.d, so none of the shell setup (aliases, prompt, PATH, the optional
offline lock) applies there: that is why the reset exists. Tests: check-all.sh t_reset_shell (fake getent/sudo/id, fake /etc/skel;
the mode checks `id -u` so a fake id can stand in for a non-root user) and e2e.sh phase 11 (real zsh and usermod;
VERIFIED GREEN in run #11).
README A7 is the manual version.

### Kate's LSP settings (a bug found while adding 24.04)
Kate supports exactly ONE server per language with a flat "command" list (lspclientservermanager.cpp, both 23.08.5
and 25.12.3); json::merge replaces arrays and merges objects recursively; the user file is read from
`<AppConfigLocation>/lspclient/settings.json` = ~/.config/kate/lspclient/settings.json by default. The earlier settings
file nested `servers` inside each language (python -> servers -> basedpyright/ruff), which Kate IGNORES, and the old
self-test only checked that the JSON parsed. Now flat (python = basedpyright; ruff is Helix-only) and t_kate asserts the
shape. Defaults: yaml/json servers exist in Kate (schema fetching: never install them).

### basedpyright level (found on the user's real machine: "why all these errors in kate editor?")
basedpyright's OWN default typeCheckingMode is "recommended" (very strict: reportUnknown*, reportMissingParameterType, reportUnusedImport as
errors; verified in basedpyright 1.40.2's langserver: serverSettings.typeCheckingMode default 'recommended'). Working untyped code, or code on
a library without stubs (pandas), then floods the editor. DECIDED by the user ("as per your recommendation"): "standard" everywhere by default.
Mechanism, verified in the sources: server settings come from the section `basedpyright` (key `typeCheckingMode` directly in it) via
workspace/configuration, or, when the client does not declare that capability, from the `settings` of workspace/didChangeConfiguration.
Kate 23.08 sends the server entry's "settings" after start (didChangeConfiguration); Kate 25.12 declares workspace/configuration and answers it
from the same "settings" by dotted section. So files/home/.config/kate/lspclient/settings.json python entry has
"settings": {"basedpyright": {"typeCheckingMode": "standard"}}; Helix: [language-server.basedpyright.config.basedpyright] in languages.toml
(Helix answers workspace/configuration from `config`). A project's pyrightconfig.json / [tool.basedpyright] still WINS (it overrides the
editor default), and ws-init ships files/templates/pyrightconfig.json ("standard") for the command line, which reads project files only.
Test: t_basedpyright_default (setup.sh self-test) runs the REAL basedpyright-langserver through files/selftest/lsp/default_level.py in both
Kate modes on a small untyped file and requires no errors/warnings; the control without settings must be strict (else exit 78 warning: the
upstream default changed). check-all t_lsp_default_level tests that client against a mock server (we never run downloaded binaries in the
sandbox). The user's `uv python install` stays blocked (python-downloads = "never"): asked, answer "no, if not strictly need".
Terminal: the user "occasionally" uses Terminator; a spaced-out-letters screenshot (apt output) came from a terminal whose font is not a true
monospace; README troubleshooting has the Terminator steps (profile font = JetBrainsMono Nerd Font Mono). Not reproducible from here.

### Kate plugins (found on the user's real machine: "all the plugins were missing")
Kate (23.08 and 25.12, source checked) enables only 8 plugins by default (katefiletree, katesearch, kateproject, tabswitcher,
textfilter, externaltools, lspclient, katekonsole) and stores the choice PER SESSION in the group `[Kate Plugins]` of
~/.local/share/kate/anonymous.katesession (the no-session start) and sessions/*.katesession, key = the plugin's .so file name.
kate_plugins() (setup.sh) sets KATE_PLUGINS_ON=true / KATE_PLUGINS_OFF=false through kconfig_set (python edit of ONLY those keys;
backup + undo record before a change; idempotent). OFF on purpose: compilerexplorer (QNetwork to godbolt.org) and katexmlcheckplugin
(xmllint without --nonet). konsole-kpart is installed too (Kate only suggests it; without it the terminal panel says "Konsole not
installed"). A new session starts with the 8 defaults again (no way around it short of patching Kate); a running Kate overwrites the
files on exit (kate_plugins warns). When Kate's plugin set changes in a new release, t_kate fails on a missing plugin: update the lists.
The Format plugin (found the hard way on the user's machine: "autopep8 is not installed" on every save): formatOnSave defaults to TRUE
(globally and, explicitly, for clang-format) and Kate 23.08 has no ruff formatter, only autopep8. files/home/.config/kate/formatting/settings.json
(merged over Kate's defaults: objects merge, arrays replace) sets formatOnSave false (global AND clang-format) and maps the "autopep8" command to
~/.local/bin/ws-pyformat (ruff format on stdin, prints the result: what Kate expects from autopep8). LESSON: before enabling a Kate plugin read
what it does on its own (saves, background network) in its source; t_kate asserts this config and runs ws-pyformat for real.

### Terminal look
`ls`/`ll`/`la`/`tree` are eza; icons (`--icons=auto`) are on when ~/.local/share/fonts/JetBrainsMonoNerdFont
exists, `WS_ICONS=0|1` overrides. The user likes this look (long listing, folder/file icons, starship `❯`
prompt) and uses JetBrains Mono Nerd Font in their terminal.

### Decisions by the user (the former open questions, all answered)
- No-cloud definition for networked apps: see requirement 1 (they may use the network naturally).
- Everyday apps and languages: the defaults are fine (LibreOffice, KeePassXC, VLC, GIMP, Inkscape,
  Déjà Dup; DESKTOP_LANGUAGES empty = English only).
- Browser and mail: keep Ubuntu's own Firefox/Thunderbird snaps (this setup neither installs nor
  removes them) and only place the optional policy files (DESKTOP_BROWSER_POLICIES, opt-in), as
  Claude recommended. Still UNVERIFIED whether the snaps read /etc/<app>/policies/policies.json.
- `embedded` is part of `personal`.
- Newest upstream LTS wins over the archive: requirement 4.
Answered later: tools WITHOUT an LTS line (uv, Helix, starship, rustup, lazygit) also prefer upstream (requirement 4).

## Checks you can run (and CI)
- `tools/check-all.sh` (all) or `--quick` (static; the pre-commit hook via
  `tools/install-hooks.sh`). CI (.github/workflows/ci.yml) runs it, then per profile
  `--check` against the real archive of `ubuntu:latest` and a reduced real install. It ran
  green (PR #5, #6, #8). Its self-test step is BLOCKING since the user agreed (it used to end in "|| true"):
  it is the only CI step that proves the installed tools work, a lenient step lets a broken run look green, and the
  QEMU test that made it flaky passes in every recent run. It fails only when a test FAILS (warnings 78 and skips 77
  do not). If a test is wrong, fix or skip THAT test with a stated reason; never make the step lenient again.
- The cloud sandbox is Ubuntu 24.04 with a reachable archive: `apt-get update` works, so
  `./setup.sh --profile X --check` verifies package names for real on 24.04 (only zellij/difftastic
  are missing, qemu-system-riscv is skipped as "not needed"). For 26.04 read the archive index (see
  requirement 4); the E2E is what verifies it for real. `apt-get download PKG` + `dpkg -x` into a scratch
  directory lets you read what a package ships (man pages, example files) without running anything.
  Real Kate behaviour: read its SOURCE at the tag (git fetch --depth 1 from github.com/KDE/kate, tags
  v23.08.5 = 24.04, v25.12.3 = 26.04), never run Python from inside the downloaded directory.
- A real install (`./setup.sh` without --check) is BLOCKED in the cloud sandbox by its
  guard ("modify shared resources": sudo, packages, a test user with sudo rights), and
  must not be worked around. Real installs belong in the CI workflow (container) or in a
  VM of the user's. Do not create users/sudoers entries in the sandbox to attempt it.

- `tools/e2e.sh` = the full end-to-end test (see docs/script-reference.md); the "E2E" workflow
  runs it on GitHub runner VMs and a newest-LTS container, only manually or for a PR whose title
  contains "[e2e]" (a push to such a PR cancels its running E2E: batch pushes). It is the ONLY way to
  test a real full install (the sandbox cannot). A whole job takes ~12-22 min (the install step 9-19 min, depending on the runner). get_job_logs shows the
  summary table at the end of a FAILED job's log only; for green jobs download the artifact
  (api.github.com/repos/OWNER/REPO/actions/artifacts/ID/zip with $GITHUB_TOKEN) and read summary.md.
  A docs-only change does not need an E2E: leave "[e2e]" out of its PR title.

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
- In the manual, `20-offline.sh` (the OPT-IN strict lock, D4) is installed LAST if at all;
  the script installs it early (only with ENFORCE_OFFLINE_ENV=1) but clears its variables for its own run.

## Conventions in setup.sh
- `set -Eeuo pipefail`; each install step runs via `step` in a subshell so one
  failure doesn't abort the run; failures are summarized at the end.
- apt_install skips missing packages and records them (never fatal).
- write_config / install_file (core or module home files) /
  install_system_file / install_templates / record_undo / fetch_verified
  (SHA-256 TOFU, then pinned via lock) / add_to_groups / disable_units / gset.
- Use `if ...; then ...; fi`, not `cmd && cmd`, in functions run under set -e.
- Never pipe into `grep -q` under pipefail (SIGPIPE makes the pipeline fail): capture into a variable
  first. This bit three times (ws-init test, check-all, the E2E lock phase).
- Files in ~/.bashrc.d load in NAME order: 10-workstation (env, history, integrations), 15-oh-my-bash (opt-in),
  16-aliases (everyday aliases), 20-offline. Aliases MUST come after Oh My Bash: it defines its own ls/ll/la/l/grep
  (lib/directories.sh, lib/grep.sh, ls init function) while loading and silently replaces earlier ones (found on the
  user's real machine; the E2E now asserts the aliases, ws-doctor checks them). install_file never overwrites an
  existing file, so an old 10-workstation.sh keeps its aliases and the new 16 file adds the right ones.
- Order matters for services: anything that disables a unit (privacy_hardening) runs AFTER all package
  installs, because a dependency can switch its timer back on. Every `record_undo` must be recorded
  BEFORE the thing that can fail, and only for what THIS run created (check "did it exist?" first).
- Containers: no running systemd (`systemctl disable`, never `--now`), no podman (`podman info` fails
  whatever the config says: judge a config by before/after, not by one failing call).
- NEVER locate code in setup.sh with a text search for "main() {": it also
  occurs inside self-test heredocs (C/C++ sources).
- Optional downloads must never abort the step they sit in: `x="$(curl ... | awk ...)"` under pipefail dies on a
  curl error (exit 22 = HTTP error); append `|| true`, and write the OFF-switching config (tealdeer, ...) BEFORE
  anything that needs the network (found on the first 24.04 run, where lazygit comes from its release).
- Downloads outside APT: prefer `fetch_published URL DEST SUMS_URL [NAME]` (checks the
  checksum the PROJECT publishes; refuses a mismatch; if the checksum file cannot be fetched it RETRIES then
  REFUSES, never trust-on-first-use, unless the lock pins the SHA-256; records "<url> <sha> published"
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
FINAL E2E OF THIS BATCH (GitHub run #24, workflow_dispatch on the branch, head 1bfb316): 8/8 GREEN, 12/12 phases in every job; self-test 33/36
(container work/personal) and 34/37 (VM), 0 failed, only SPICE/container-image skips. Verified in it: rustup 1.29.3 (rustup-init, container jobs; the VM image's own
rustup is left alone), lazygit 0.66.2, uv 0.13.7, Helix 25.07.1, probe-rs 0.32.0 all from upstream with no archive fallback; the default install does not
block uv/cargo in a new shell (strict lock opt-in); Kate plugin set + t_kate PASS on Kate 23.08 (24.04) and 25.12 (26.04); ws-pyformat run with the real ruff;
t_basedpyright_default PASSED against the REAL basedpyright-langserver in both Kate modes (written without being able to run the server: it worked on first
contact). History of this batch: run #21 (bc04a24) 8/8; run #23 (6c7dcec) failed 5/8 ONLY on GitHub HTTP 504 for the probe-rs release (curl 22, 4 quick tries,
same minute in 5 jobs) -> download retries raised to --retry 6 --retry-max-time 180 (1bfb316), the E2E correctly failed on the failed step instead of hiding it.
LESSON: read WHY a job failed (summary.md install block, install.log) before calling it flaky; here the log said 504 outright. The CI self-test (blocking) still has
not been seen on a PULL REQUEST yet.
E2E WITH UPSTREAM-FIRST uv/Helix/starship (GitHub run #18, workflow_dispatch on the branch, head a4f6899): 8/8 GREEN, all 12
phases everywhere (phase 12 = starship installed from its real release in a scratch HOME; --full turns Oh My Bash on, so the main
install never installs starship). uv 0.13.7 and Helix 25.07.1 were installed from upstream in all eight jobs, none used the
archive fallback; self-test 33/36 (VM work/personal), 32/35 (container), 0 failed, only SPICE/container-image skips; ~13-16 min per
job. The CI self-test is blocking in ci.yml but only runs on a PULL REQUEST: it has not been seen green yet (check it on the PR before merging).
E2E ON 24.04 + 26.04 (GitHub runs #15 and #16, workflow_dispatch on the branch, matrix ubuntu 24.04/latest x vm/container x work/personal =
8 jobs; headers say "Ubuntu 24.04.5 LTS" / "Ubuntu 26.04.1 LTS"). Run #15 (head 05ea021): 7/8 green; the failure (container 24.04
personal) was a transient GitHub error during two downloads: it aborted the Base CLI tools step via a pipefail curl in
lazygit_fallback (24.04 only: lazygit is not in its archive) BEFORE the tealdeer config was written, and fetch_published silently
fell back to TOFU for the Nerd Font (security downgrade). Fixed in 480a823 (see Conventions). Run #16 (head 480a823): 8/8 GREEN, all
11 phases everywhere; self-test 33/36 (VM work/personal) and 32/35 (container) on BOTH releases, 0 failed; RISC-V QEMU passes on
24.04 via qemu-system-misc; Kate starts; Node v26.13.0 from nodejs.org on both (archive Node 18 is EOL); lazygit from its release on
24.04. Install step 10-19 min, one 26.04 VM job took 51 min (slow runner, no log hint; get_job_logs of a RUNNING job is 404).
E2E RUN #13 (workflow_dispatch on the branch, head f71d2fa): GREEN, 11/11 phases in all four jobs, with the alias fix:
the shell phase now asserts ls/ll/la are eza and grep is ours WITH the real Oh My Bash on (--full), ws-doctor reports
"ls and ll are eza" in all four; self-test 33/36 (VM), 32/35 (container), 0 failed. Origin of the fix: the USER'S REAL
MACHINE (first non-CI run, profile work, --full): 32/33 self-test passed, the failure was an already-installed
yaml-language-server (message improved, see CHANGELOG), and the user saw no icons and wrong aliases because Oh My Bash
replaced ls/ll/la/grep (16-aliases.sh loads after it now). LESSON: CI cannot see what a real machine shows; ask the user
for the self-test output and `type ls ll` first.
E2E WITH PHASE 11 (GitHub run #11, workflow_dispatch on the branch, head a56737a): GREEN, 11/11 phases in all four jobs.
Phase 11 = `--reset-shell` with a REAL zsh and REAL `sudo usermod` (VM user "runner", container user "tester"): login
shell zsh -> bash, files in the backup folder, then `--undo` -> zsh and files back, original shell restored. Self-test
33/36 (VM work/personal), 32/35 (container), 0 failed; only the expected skips (SPICE, container images).
FULL E2E, EARLIER (GitHub run #7, workflow_dispatch on the branch, head c9f4669): GREEN in all four jobs, nothing
hidden: self-test vm-work 33/0, vm-personal 36/0, container-work 32/0, container-personal 35/0 (passed/failed),
install step 9-19 min across runs (10-13 min in the last), ws-doctor 0 failed, RISC-V QEMU test PASSES, lock pins NODE_LTS_VERSION, leftovers clean (incl.
~/.local/opt and node/npm/npx). Node.js v26.13.0 from nodejs.org (node_install) in every job, bash-language-server
installed with its npm; personal = core + embedded + desktop. Remaining skips are expected (SPICE kernels off by
default; container images off in the container jobs). The run before it (#6, head 8fb892a) was green too but its
selftest.log showed `SKIP RISC-V program runs in QEMU (qemu-system-riscv64 not installed)`: 26.04 split RISC-V out of
qemu-system-misc into `qemu-system-riscv` (found by reading the real 26.04 package index at
archive.ubuntu.com/ubuntu/dists/resolute/{main,universe}/binary-amd64/Packages.gz, which the sandbox can download).
Fixed in c9f4669; e2e.sh now FAILS on a RISC-V skip and checks the Node lock pin and its undo.
LESSON: green is not enough, grep the logs for SKIP and WARN. Six E2E runs actually executed (4 on PR #8, then 2
manual dispatches); GitHub's run numbers count one more, a PR-event run whose jobs were skipped (no "[e2e]" in the title).
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
them. The RISC-V skip found later is described above.)
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
     2-word block) VERIFIED in CI since c9f4669 (needs the qemu-system-riscv package on 26.04).
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
   same for personal, review, commit locks/. (The lock now also pins NODE_LTS_VERSION.)
5. (DONE: the E2E covered Node.js upstream LTS and personal = core+embedded+desktop, see Status.)
   An E2E can be started WITHOUT a PR: actions_run_trigger(run_workflow, workflow_id e2e.yml, ref = the branch);
   a docs push to that branch then does not cancel it (only pull_request runs share the cancel group per ref).

## Safety rules for Claude Code in this repo
- Do not run `./setup.sh` (install mode) on the development machine: it uses
  sudo and changes the system. `--check`, `--self-test`, `--manifest` are
  read-only apart from files under ~/.local/share/workstation and ~ ;
  `--lock` only writes locks/<profile>.lock (use WORKSTATION_LOCK=/tmp/x.lock
  to test). For experiments point HOME at a scratch directory.
- Keep both policies above when changing anything; extend the no-cloud
  self-test (t_nocloud_policy / a module's nocloud_problems hook) when adding
  a tool that could phone home.
