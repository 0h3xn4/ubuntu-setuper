# Workstation Cheat Sheet

Installed by workstation-setup (core). Open any time with `ws-help` (works offline).
Press `q` to quit, `/` to search.

## Helper commands

| Command | What it does |
|---|---|
| `ws-help` | This cheat sheet |
| `ws-init` | Copy generic starter files (.clang-format, .clang-tidy, .clangd, .editorconfig, pre-commit, ruff, host CMakePresets.json) into the current project; never overwrites |
| `ws-doctor` | Quick health check: tools, editor, shell setup, no-cloud settings, offline caches (read-only, offline; `ws-doctor --quiet` shows only problems) |
| `ws-init --list` | Show which starter-file sets are installed (modules add their own, e.g. `ws-init --embedded`) |
| `cppref` / `pydocs` / `cmakedocs` / `rustdocs` | Open local documentation in the browser |
| `z <part-of-dir>` | Jump to a frequently used directory |
| `Ctrl-R` | Fuzzy search command history |
| `Ctrl-T` | Fuzzy pick a file and insert its path |
| `lg` | lazygit: visual git in the terminal |

## First day

New to the terminal? Do these, in this order, and you know the basics:

1. `ws-help` (this page). Press `q` to leave, `/` to search.
2. `hx --tutor` (30 minutes): the built-in Helix tutorial. Helix selects first, then acts.
3. `cd`, `ls`, `ll` (long listing with icons), `la` (also hidden files), `z <part-of-dir>` (jump), `Ctrl-R` (search history), `Ctrl-T` (pick a file).
4. `tldr <command>`: short examples for any command, offline (`tldr tar`).
5. `lg` for visual git. Make a throw-away project: `mkdir play && cd play && git init && ws-init`.
6. `ws-doctor` any time something feels off.
7. `zellij` (if installed): several terminals in one window; its bottom bar lists the keys.
   `kate file` opens a graphical editor with the same language servers.

Handy: `difft a b` (difftastic, if installed) shows what changed structurally;
`cargo nextest run` runs Rust tests faster; with `ccache` installed CMake builds
are cached automatically (`ccache -s` shows hits).

## Helix editor (`hx`)

Modes: `i` insert, `Esc` back to normal, `v` select mode. Helix selects
first, then acts: `w` then `d` deletes a word.

| Keys | Action |
|---|---|
| `Space f` | Find file (fuzzy) |
| `Space b` | Switch buffer |
| `Space /` | Search text in the whole project |
| `Space s` / `Space S` | Symbols in file / in workspace |
| `Space k` | Documentation for symbol under cursor |
| `gd` / `gr` / `gi` | Go to definition / references / implementation |
| `Ctrl-o` / `Ctrl-i` | Jump back / forward |
| `Space r` | Rename symbol everywhere |
| `Space a` | Code actions (quick fixes) |
| `Space d` / `Space D` | Errors and warnings in file / workspace |
| `]d` / `[d` | Next / previous error or warning |
| `Space c` or `Ctrl-c` | Toggle comment |
| `x` | Select line (repeat to extend) |
| `%` | Select whole file |
| `s` | Select regex matches within selection (multi-cursor) |
| `C` | Add cursor on next line |
| `,` | Back to a single cursor |
| `u` / `U` | Undo / redo |
| `Space y` / `Space p` | Copy to / paste from system clipboard |
| `Space ?` | Search all commands |
| `:w` `:q` `:wq` `:q!` | Save, quit, save and quit, quit without saving |
| `:format` | Format file (C/C++ are not auto-formatted on save) |
| `:sh <cmd>` | Run a shell command |

Check language support: `hx --health c` (also `cpp`, `python`, `rust`).

## Building C/C++ with CMake presets

After `ws-init` in a project with a CMakeLists.txt:

```bash
cmake --preset host-debug            # configure (strict warnings)
cmake --build --preset host-debug    # build
ctest --preset host-debug            # run unit tests
cmake --preset host-sanitize         # AddressSanitizer + UBSan build
```

clangd reads `build/host-debug/compile_commands.json` (set in `.clangd`).
Change that path if you work on a different preset.

## Coverage

```bash
cmake --preset coverage && cmake --build --preset coverage && ctest --preset coverage
mkdir -p coverage
gcovr --root . --html-details coverage/index.html build/coverage
```

## Static analysis

```bash
run-clang-tidy -p build/host-debug                 # clang-tidy, uses .clang-tidy
cppcheck --project=build/host-debug/compile_commands.json \
         --enable=warning,style,performance,portability
cppcheck --addon=misra ...                         # needs your licensed MISRA rule texts
scan-build cmake --build build/host-debug          # Clang static analyzer
```

## Python (offline)

Package managers use the internet like on any machine; the wheelhouse is a local copy for offline use:

```bash
uv venv && source .venv/bin/activate
uv pip install numpy pytest                    # from the internet, or the local wheelhouse if you are offline
ruff check . && ruff format .                  # lint and format
basedpyright                                   # type check
```

You are not blocked from the network: `uv add`, `uv pip install`, `cargo add` and friends fetch what you ask for.
Available offline (for a machine without network): see `ls ~/.local/share/workstation/wheelhouse`
(`uv pip install --find-links ~/.local/share/workstation/wheelhouse <pkg>`).
If a command is refused with "network disabled", you have the strict lock (an older install or `ENFORCE_OFFLINE_ENV=1`):
`rm ~/.bashrc.d/20-offline.sh` and open a new terminal, or override once: `UV_OFFLINE=0 uv add <pkg>`.

## Rust (offline)

```bash
cargo new my-crate && cd my-crate
cargo add anyhow                      # from crates.io (or the local crate cache if you are offline)
cargo build
cargo clippy                          # lints
```

Crates are fetched from the internet when you ask (`cargo add`, `cargo build`). With the strict lock on
(`ENFORCE_OFFLINE_ENV=1`): `CARGO_NET_OFFLINE=false cargo update`.

## Containers (offline)

```bash
podman images                                   # images available offline
distrobox create -n lts -i docker.io/library/ubuntu:latest
distrobox enter lts                             # isolated environment, same home dir
```

Images are never pulled implicitly. An explicit `podman pull` still works.
Images for other or older systems (e.g. a project's legacy build
environment) are added deliberately in OFFLINE_CONTAINER_IMAGES.

## Fonts and prompt

The setup installs **JetBrains Mono Nerd Font** (JetBrains Mono plus icon
glyphs) for your user. To see icons in the prompt, set your terminal font to
**JetBrainsMono Nerd Font Mono**: GNOME Terminal > Preferences > your profile >
Custom font (or let the setup do it system-wide: `SET_GNOME_FONT=1`).

```bash
fc-list : family | grep 'JetBrainsMono Nerd Font'      # is it installed?
starship preset nerd-font-symbols -o ~/.config/starship.toml    # icon prompt (after the font works)
starship preset plain-text-symbols -o ~/.config/starship.toml   # no special font needed
```

`ls`, `ll`, `la` and `tree` are `eza` with file icons, which need this font in the terminal
(defined in `~/.bashrc.d/16-aliases.sh`, which loads after Oh My Bash on purpose; `type ls ll` shows what you really get).
Boxes instead of icons? The terminal still uses another font: pick the Nerd Font, or `export WS_ICONS=0`.

Prompt: starship by default. If Oh My Bash is enabled (`INSTALL_OH_MY_BASH=1`)
it owns the prompt instead: edit the theme and plugins in
`~/.bashrc.d/15-oh-my-bash.sh` (`ls ~/.local/share/oh-my-bash/themes`). Its
GitHub update check is off; update on purpose with `./setup.sh --upgrade`.

## Git

```bash
lg                          # lazygit
git log --oneline --graph   # history
pre-commit install          # once per clone, after ws-init
pre-commit run --all-files  # check everything now
```

## Offline documentation

| Command | Content |
|---|---|
| `cppref` | C and C++ language and standard library (cppreference) |
| `pydocs` | Python documentation |
| `cmakedocs` | CMake reference |
| `rustdocs` | Rust standard library |
| `man 3 memcpy` | C library function |
| `man 3posix pthread_create` | POSIX specification |
| `info gdb` | GDB manual |
| `tldr <command>` | Practical examples |
