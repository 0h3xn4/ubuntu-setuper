# Workstation Cheat Sheet

Installed by workstation-setup (core). Open any time with `ws-help` (works offline).
Press `q` to quit, `/` to search.

## Helper commands

| Command | What it does |
|---|---|
| `ws-help` | This cheat sheet |
| `ws-init` | Copy generic starter files (.clang-format, .clang-tidy, .clangd, .editorconfig, pre-commit, ruff, host CMakePresets.json) into the current project; never overwrites |
| `ws-init --list` | Show which starter-file sets are installed (modules add their own, e.g. `ws-init --embedded`) |
| `cppref` / `pydocs` / `cmakedocs` / `rustdocs` | Open local documentation in the browser |
| `z <part-of-dir>` | Jump to a frequently used directory |
| `Ctrl-R` | Fuzzy search command history |
| `Ctrl-T` | Fuzzy pick a file and insert its path |
| `lg` | lazygit: visual git in the terminal |

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

Package managers work only from local caches (no internet at runtime):

```bash
uv venv && source .venv/bin/activate
uv pip install numpy pytest                    # served from the local wheelhouse
ruff check . && ruff format .                  # lint and format
basedpyright                                   # type check
```

Available offline: see `ls ~/.local/share/workstation/wheelhouse`.
To deliberately fetch something new (internal mirror, approved by IT):
`UV_OFFLINE=0 uv pip install <pkg>`

## Rust (offline)

```bash
cargo new my-crate && cd my-crate
cargo add anyhow                      # from the local crate cache
cargo build
cargo clippy                          # lints
```

To deliberately fetch something new: `CARGO_NET_OFFLINE=false cargo update`

## Containers (offline)

```bash
podman images                                   # images available offline
distrobox create -n lts -i docker.io/library/ubuntu:latest
distrobox enter lts                             # isolated environment, same home dir
```

Images are never pulled implicitly. An explicit `podman pull` still works.
Images for other or older systems (e.g. a project's legacy build
environment) are added deliberately in OFFLINE_CONTAINER_IMAGES.

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
