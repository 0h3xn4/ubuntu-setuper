# shellcheck shell=bash
# STEP_WHY / STEP_TOUCHES are declared in setup.sh; '~' in descriptions is literal.
# shellcheck disable=SC2034,SC2088
# =============================================================================
#  modules/embedded/module.sh — code of the "embedded" module
#
#  Sourced by setup.sh after the core library, so it can use its helpers
#  (apt_install, install_file, step, add_to_groups, ...). A module offers
#  hooks named mod_<module>_<hook>; setup.sh calls those that exist:
#
#    pkg_groups   names of PKGS_* arrays to install (check/plan + manifest)
#    steps        install steps (calls `step "Title" function`)
#    home_files   files from <module>/files/home installed into ~
#    groups       user groups the module needs
#    uv_tools / cargo_tools / rust_targets / py_packages / rust_crates
#                 additions to the core tool lists and offline caches
#    check        extra lines for 'Planned system changes' in the --check report
#    check_caches extra lines for 'Offline caches' in the --check report
#    selftests    self-tests (calls `run_test "Title" function module`)
#    nocloud_problems / nocloud_warnings   lines for the no-cloud self-test
#    manifest_tools   commands whose versions go into the manifest
#    manifest_extra   extra lines for the manifest
# =============================================================================
EMBEDDED_DIR="$MODULE_DIR"

# What each step does (shown during install and by ./setup.sh --explain)
STEP_WHY["Embedded toolchain"]="Cross compilers for ARM and RISC-V, QEMU emulators, OpenOCD and flash tools for debug probes, serial and CAN tools. With JOIN_SERIAL_GROUPS=1 your user also joins the 'dialout' and 'plugdev' groups so serial ports and probes work without sudo (active after the next login); otherwise they need sudo."
STEP_TOUCHES["Embedded toolchain"]="apt packages; with JOIN_SERIAL_GROUPS=1 system: adds you to groups dialout and plugdev (sudo)."
STEP_WHY["probe-rs (prebuilt)"]="probe-rs, cargo-flash and cargo-embed (flashing and debugging through debug probes) from the project's own release, checked against its published checksum, instead of compiling them from source (10+ minutes). Set PROBE_RS_PREBUILT=0 to compile with cargo instead."
STEP_TOUCHES["probe-rs (prebuilt)"]="~/.local/bin (3 programs); network: github.com release download, once."
STEP_WHY["Wireshark"]="Packet inspection (for telemetry and bus traffic). With JOIN_WIRESHARK_GROUP=1, members of the 'wireshark' group may capture without root; otherwise capture needs sudo."
STEP_TOUCHES["Wireshark"]="apt package; with JOIN_WIRESHARK_GROUP=1 system: debconf answer + dpkg-reconfigure wireshark-common, adds you to group wireshark (sudo)."
STEP_WHY["Verification tools"]="Formal and static verification helpers: CBMC bounded model checker, flawfinder, AFL++ fuzzer, lizard (complexity) and codespell."
STEP_TOUCHES["Verification tools"]="apt packages; ~/.local (uv tools); network: PyPI."
STEP_WHY["Embedded GUI tools"]="PulseView, the logic-analyzer GUI."
STEP_TOUCHES["Embedded GUI tools"]="apt package."
STEP_WHY["Embedded helpers and templates"]="The 'serial' and 'vcan-up' shell helpers, ws-devname (stable names for USB serial adapters; writes its udev rule only when YOU run it) and the embedded project starter files for 'ws-init --embedded'."
STEP_TOUCHES["Embedded helpers and templates"]="~/.bashrc.d/30-embedded.sh, ~/.local/bin/ws-devname, ~/.local/share/workstation/templates/embedded."
STEP_WHY["SPICE generic kernels"]="Downloads NASA NAIF generic SPICE kernels (about 35 MB) and a meta-kernel that loads them."
STEP_TOUCHES["SPICE generic kernels"]="~/.local/share/workstation/spice; network: naif.jpl.nasa.gov, now."

mod_embedded_pkg_groups() {
  echo PKGS_EMBEDDED
  if on "$INSTALL_GUI_TOOLS"; then echo PKGS_EMBEDDED_GUI; fi
  if on "$INSTALL_WIRESHARK"; then echo PKGS_WIRESHARK; fi
  if on "$INSTALL_VERIFICATION"; then
    echo PKGS_VERIFICATION
    if on "$INSTALL_FRAMA_C"; then echo PKGS_FRAMA_C; fi
  fi
}

mod_embedded_home_files() {
  echo .bashrc.d/30-embedded.sh
  echo .local/bin/ws-devname
}

mod_embedded_groups() {
  if on "$JOIN_SERIAL_GROUPS"; then echo dialout; echo plugdev; fi
  if on "$INSTALL_WIRESHARK" && on "$JOIN_WIRESHARK_GROUP"; then echo wireshark; fi
}

mod_embedded_opt_in() {
  echo "JOIN_SERIAL_GROUPS|add your user to groups dialout and plugdev (serial ports, debug probes without sudo)"
  echo "JOIN_WIRESHARK_GROUP|let group 'wireshark' capture without root (debconf answer, dpkg-reconfigure, group)"
}

mod_embedded_uv_tools() {
  if on "$INSTALL_VERIFICATION"; then printf '%s\n' "${EMBEDDED_UV_TOOLS_VERIFICATION[@]}"; fi
  if on "$INSTALL_FPRIME_BOOTSTRAP"; then echo fprime-bootstrap; fi
}
mod_embedded_cargo_tools() {
  local t
  for t in "${EMBEDDED_CARGO_TOOLS[@]}"; do
    # probe-rs is installed prebuilt unless PROBE_RS_PREBUILT=0
    if [[ $t == probe-rs-tools ]] && on "$PROBE_RS_PREBUILT"; then continue; fi
    echo "$t"
  done
}

mod_embedded_lock_pins() {
  # shellcheck disable=SC2016  # writes ': "${X:=value}"' literally
  if [[ -s $DATA_DIR/probe-rs.version ]]; then printf ': "${PROBE_RS_VERSION:=%s}"\n' "$(<"$DATA_DIR/probe-rs.version")"; fi
}

mod_embedded_manifest_extra_probe() {
  if [[ -s $DATA_DIR/probe-rs.version ]]; then echo "probe-rs (prebuilt): $(<"$DATA_DIR/probe-rs.version")"; fi
}
mod_embedded_rust_targets() { printf '%s\n' "${EMBEDDED_RUST_TARGETS[@]}"; }
mod_embedded_py_packages()  { printf '%s\n' "${EMBEDDED_PY_PACKAGES[@]}"; }
mod_embedded_rust_crates()  { printf '%s\n' "${EMBEDDED_RUST_CRATES[@]}"; }

mod_embedded_manifest_tools() {
  printf '%s\n' arm-none-eabi-gcc riscv64-unknown-elf-gcc gdb-multiarch qemu-system-arm \
    qemu-system-riscv64 qemu-system-sparc openocd cbmc probe-rs tio
}

mod_embedded_manifest_extra() {
  mod_embedded_manifest_extra_probe
  if [[ -d $DATA_DIR/spice ]]; then echo "SPICE kernels:"; (cd "$DATA_DIR/spice" && sha256sum -- * | sed 's/^/  /'); fi
}

mod_embedded_check_caches() {
  if on "$INSTALL_SPICE_KERNELS"; then log "SPICE generic kernels -> $DATA_DIR/spice"; fi
}

mod_embedded_steps() {
  step "Embedded toolchain"             embedded_toolchain
  if on "$PROBE_RS_PREBUILT";    then step "probe-rs (prebuilt)" probe_rs_prebuilt; fi
  if on "$INSTALL_WIRESHARK";    then step "Wireshark"          wireshark_setup; fi
  if on "$INSTALL_VERIFICATION"; then step "Verification tools" verification_tools; fi
  if on "$INSTALL_GUI_TOOLS";    then step "Embedded GUI tools" embedded_gui_tools; fi
  step "Embedded helpers and templates" embedded_files
  if on "$INSTALL_SPICE_KERNELS"; then step "SPICE generic kernels" cache_spice; fi
}

embedded_toolchain() {
  apt_install "${PKGS_EMBEDDED[@]}"
  # Serial ports and USB debug probes without sudo (JOIN_SERIAL_GROUPS=1).
  # Probe udev rules from the packages apply the next time a device is plugged in.
  if on "$JOIN_SERIAL_GROUPS"; then add_to_groups dialout plugdev
  else log "JOIN_SERIAL_GROUPS=0: you are not added to dialout/plugdev; serial ports and probes need sudo"; fi
}

# probe-rs (debug probes, flashing) from the project's own release tarball, checked
# against the checksum the project publishes: saves a 10+ minute compile.
probe_rs_prebuilt() {
  local asset base tag dir
  asset="probe-rs-tools-$(host_arch)-unknown-linux-gnu.tar.xz"; dir="${asset%.tar.xz}"
  if [[ -n ${PROBE_RS_VERSION:-} ]]; then
    tag="$PROBE_RS_VERSION"; base="https://github.com/probe-rs/probe-rs/releases/download/$tag"
  else
    base="https://github.com/probe-rs/probe-rs/releases/latest/download"
    tag="$(release_tag_of "$base/$asset")"
  fi
  fetch_published "$base/$asset" "$STATE_DIR/$asset" "$base/$asset.sha256" "$asset"
  tar -xJf "$STATE_DIR/$asset" -C "$STATE_DIR"
  mkdir -p "$HOME/.local/bin" "$DATA_DIR"
  install -m 755 "$STATE_DIR/$dir/probe-rs" "$STATE_DIR/$dir/cargo-embed" "$STATE_DIR/$dir/cargo-flash" "$HOME/.local/bin/"
  if [[ -n $tag ]]; then printf '%s\n' "$tag" > "$DATA_DIR/probe-rs.version"; fi
  record_undo "rm -f ~/.local/bin/probe-rs ~/.local/bin/cargo-embed ~/.local/bin/cargo-flash"
  ok "Installed probe-rs ${tag:-(version unknown)} (prebuilt)"
}

wireshark_setup() {
  if ! on "$JOIN_WIRESHARK_GROUP"; then
    apt_install "${PKGS_WIRESHARK[@]}"
    log "JOIN_WIRESHARK_GROUP=0: capture needs sudo (packet capture for non-root users is not enabled)"
    return 0
  fi
  local before=""
  if dpkg -s wireshark-common >/dev/null 2>&1; then
    before="$(debconf-show wireshark-common 2>/dev/null | awk -F': ' '/install-setuid/ { print $2 }' || true)"
  fi
  echo "wireshark-common wireshark-common/install-setuid boolean true" \
    | sudo debconf-set-selections
  apt_install "${PKGS_WIRESHARK[@]}"
  if dpkg -s wireshark-common >/dev/null 2>&1; then
    # The undo must work unattended (--undo --yes): a plain 'dpkg-reconfigure' only asks a person, so replayed by
    # the undo it left non-root capture ON (found by --reset-defaults in the E2E). Back to Ubuntu's default: false.
    if [[ $before != true ]]; then
      record_undo "echo 'wireshark-common wireshark-common/install-setuid boolean false' | sudo debconf-set-selections && sudo env DEBIAN_FRONTEND=noninteractive dpkg-reconfigure -f noninteractive wireshark-common"
    fi
    sudo env DEBIAN_FRONTEND=noninteractive dpkg-reconfigure -f noninteractive wireshark-common
  fi
  add_to_groups wireshark
}

verification_tools() {
  apt_install "${PKGS_VERIFICATION[@]}"
  if on "$INSTALL_FRAMA_C"; then apt_install "${PKGS_FRAMA_C[@]}"; fi
}

embedded_gui_tools() { apt_install "${PKGS_EMBEDDED_GUI[@]}"; }

embedded_files() {
  install_file .bashrc.d/30-embedded.sh
  install_file .local/bin/ws-devname 755
  install_templates "$EMBEDDED_DIR/files/templates" embedded
}

cache_spice() {
  local base="https://naif.jpl.nasa.gov/pub/naif/generic_kernels" dir="$DATA_DIR/spice" f
  for f in lsk/naif0012.tls pck/pck00011.tpc pck/gm_de440.tpc spk/planets/de440s.bsp; do
    if [[ -s "$dir/${f##*/}" ]]; then ok "Present: ${f##*/}"; continue; fi
    fetch_verified "$base/$f" "$dir/${f##*/}"
  done
  cat > "$dir/generic.tm" <<EOT
KPL/MK
Generic SPICE kernels, downloaded by workstation-setup.
Python:  import spiceypy; spiceypy.furnsh("$dir/generic.tm")

\begindata
  PATH_VALUES     = ( '$dir' )
  PATH_SYMBOLS    = ( 'K' )
  KERNELS_TO_LOAD = ( '\$K/naif0012.tls'
                      '\$K/pck00011.tpc'
                      '\$K/gm_de440.tpc'
                      '\$K/de440s.bsp' )
\begintext
EOT
  ok "SPICE kernels in $dir (meta-kernel: generic.tm)"
}

# ----------------------------------------------------------------------------
# Self-tests
# ----------------------------------------------------------------------------
mod_embedded_selftests() {
  run_test "CMake cross presets (ARM)"            t_emb_cmake_presets embedded
  run_test "ws-init --embedded"                   t_emb_ws_init       embedded
  run_test "clangd understands ARM code (newlib)" t_emb_clangd_cross  embedded
  run_test "ARM cross: newlib C and C++ link"     t_emb_arm_newlib    embedded
  run_test "ARM Cortex-M program runs in QEMU"    t_emb_arm_qemu      embedded
  run_test "RISC-V program runs in QEMU"          t_emb_riscv_qemu    embedded
  run_test "GDB multiarch knows ARM and RISC-V"   t_emb_gdb           embedded
  run_test "OpenOCD and debug probe configs"      t_emb_openocd       embedded
  run_test "ws-devname rejects hostile USB ids"   t_emb_devname       embedded
  run_test "Rust: bare-metal targets"             t_emb_rust_targets  embedded
  run_test "SPICE generic kernels"                t_emb_spice         embedded
}

t_emb_cmake_presets() {
  needs cmake ninja jq arm-none-eabi-gcc
  mkdir -p tpl
  cp -r "$FILES/templates" tpl/generic
  cp -r "$EMBEDDED_DIR/files/templates" tpl/embedded
  cp -r "$FILES/selftest/presets/." .
  WS_TEMPLATE_DIR="$PWD/tpl" "$FILES/home/.local/bin/ws-init" --embedded >/dev/null
  cmake --preset arm-cortex-m
  cmake --build --preset arm-cortex-m
  arm-none-eabi-objdump -f build/arm-cortex-m/libcrc16.a | grep -q elf32-littlearm
}

t_emb_ws_init() {
  needs jq
  mkdir -p tpl proj
  cp -r "$FILES/templates" tpl/generic
  cp -r "$EMBEDDED_DIR/files/templates" tpl/embedded
  cd proj || return 1
  WS_TEMPLATE_DIR="$PWD/../tpl" "$FILES/home/.local/bin/ws-init" --embedded >/dev/null
  test -f cmake/arm-none-eabi.cmake
  test -f cmake/riscv64-unknown-elf.cmake
  test -f .editorconfig
  grep -q 'embedded variant' .clangd
  jq -e '.include == ["cmake/embedded-presets.json"]' CMakePresets.json >/dev/null
  # The plain generic run must not contain embedded files.
  mkdir ../plain && cd ../plain || return 1
  WS_TEMPLATE_DIR="$PWD/../tpl" "$FILES/home/.local/bin/ws-init" >/dev/null
  test ! -e cmake
  jq -e 'has("include") | not' CMakePresets.json >/dev/null
}

t_emb_clangd_cross() {
  needs clangd arm-none-eabi-gcc
  local gcc; gcc="$(command -v arm-none-eabi-gcc)"
  cat > x.c <<'EOT'
#include <newlib.h>   /* exists only in newlib: proves clangd sees the cross headers */
#include <stdint.h>
uint32_t newlib_major(void) { return (uint32_t)__NEWLIB__; }
EOT
  printf '[{"directory": "%s", "file": "x.c", "command": "%s -mcpu=cortex-m4 -mthumb -c x.c"}]\n' \
    "$PWD" "$gcc" > compile_commands.json
  clangd --check=x.c --query-driver="$gcc"
}

t_emb_arm_newlib() {
  needs arm-none-eabi-gcc arm-none-eabi-g++
  local flags=(-mcpu=cortex-m4 -mthumb -mfloat-abi=hard -mfpu=fpv4-sp-d16 --specs=nano.specs --specs=nosys.specs)
  printf '#include <stdio.h>\nint main(void) { printf("%%d\\n", 42); return 0; }\n' > main.c
  arm-none-eabi-gcc "${flags[@]}" -O2 main.c -o c.elf
  cat > main.cpp <<'EOT'
#include <algorithm>
#include <array>
int main() { std::array<int, 3> a{3, 1, 2}; std::sort(a.begin(), a.end()); return a[0]; }
EOT
  arm-none-eabi-g++ "${flags[@]}" -std=c++17 -fno-exceptions -fno-rtti -O2 main.cpp -o cpp.elf
  arm-none-eabi-size c.elf cpp.elf
}

# Run a bare-metal ELF under QEMU with semihosting. The guest's semihosting output goes
# to QEMU's STDERR (seen on QEMU 10.2 in CI), so stdout and stderr are captured together
# in qemu.txt. The exit status (QEMU_RC) and the QEMU version are printed to the log.
# (Not piped through tee: with pipefail a failure there hides the real cause.)
run_qemu_semihost() {
  local elf="$1" qemu="$2"; shift 2
  QEMU_RC=0
  timeout 30 "$qemu" "$@" -nographic -monitor none -serial none \
    -semihosting-config enable=on,target=native -kernel "$elf" < /dev/null > qemu.txt 2>&1 || QEMU_RC=$?
  cat qemu.txt
  echo "--- $("$qemu" --version | head -n1); exit status $QEMU_RC"
}

t_emb_arm_qemu() {
  needs arm-none-eabi-gcc qemu-system-arm
  arm-none-eabi-gcc -mcpu=cortex-m3 -mthumb -O1 -ffreestanding -nostdlib \
    -T "$EMBEDDED_DIR/files/selftest/arm/lm3s6965.ld" "$EMBEDDED_DIR/files/selftest/arm/semihost.c" -o arm.elf
  run_qemu_semihost arm.elf qemu-system-arm -M lm3s6965evb
  grep -q "ARM Cortex-M self-test OK" qemu.txt
  (( QEMU_RC == 0 )) || { echo "QEMU exited with status $QEMU_RC (0 expected after SYS_EXIT with ApplicationExit)"; return 1; }
}

t_emb_riscv_qemu() {
  needs riscv64-unknown-elf-gcc qemu-system-riscv64
  riscv64-unknown-elf-gcc -march=rv64imac -mabi=lp64 -mcmodel=medany -mno-relax -O1 \
    -ffreestanding -nostdlib -T "$EMBEDDED_DIR/files/selftest/riscv/virt.ld" \
    "$EMBEDDED_DIR/files/selftest/riscv/semihost.c" -o riscv.elf
  run_qemu_semihost riscv.elf qemu-system-riscv64 -M virt -bios none
  grep -q "RISC-V self-test OK" qemu.txt
  (( QEMU_RC == 0 )) || { echo "QEMU exited with status $QEMU_RC (0 expected after SYS_EXIT with ApplicationExit)"; return 1; }
}

t_emb_gdb() {
  needs gdb-multiarch
  gdb-multiarch -batch -ex 'set architecture' > arch.txt 2>&1 || true
  grep -q 'armv7e-m' arch.txt
  grep -q 'riscv:rv64' arch.txt
}

t_emb_openocd() {
  needs openocd
  openocd --version 2>&1 | head -n1
  test -f /usr/share/openocd/scripts/interface/stlink.cfg
  test -f /usr/share/openocd/scripts/interface/cmsis-dap.cfg
}

# ws-devname writes USB-supplied strings into a root-owned udev rules file; it
# must refuse anything that could inject rules. Uses a fake udevadm, no sudo.
t_emb_devname() {
  local bin="$PWD/bin" out
  mkdir -p "$bin"
  cat > "$bin/udevadm" <<'EOT'
#!/usr/bin/env bash
printf 'ID_VENDOR_ID=0403\nID_MODEL_ID=6001\nID_SERIAL_SHORT=%s\n' "$FAKE_SERIAL"
EOT
  cat > "$bin/sudo" <<'EOT'
#!/usr/bin/env bash
echo "sudo must not be called for a refused device" >&2; exit 99
EOT
  chmod +x "$bin/udevadm" "$bin/sudo"
  out="$(PATH="$bin:$PATH" FAKE_SERIAL='A1", RUN+="/bin/true' \
         "$EMBEDDED_DIR/files/home/.local/bin/ws-devname" add /dev/null evil 2>&1 || true)"
  grep -q 'Refusing' <<<"$out" || { echo "hostile serial was not refused: $out"; return 1; }
}

t_emb_rust_targets() {
  needs rustc
  printf '#![no_std]\npub fn add(a: u32, b: u32) -> u32 { a.wrapping_add(b) }\n' > lib.rs
  local t
  for t in "${EMBEDDED_RUST_TARGETS[@]}"; do
    rustc --edition 2021 --crate-type lib --target "$t" --emit obj -o "$t.o" lib.rs
    echo "built for $t"
  done
}

t_emb_spice() {
  needs_on INSTALL_SPICE_KERNELS
  local f
  for f in naif0012.tls pck00011.tpc gm_de440.tpc de440s.bsp generic.tm; do
    [[ -s "$DATA_DIR/spice/$f" ]] || { echo "missing: $f"; return 1; }
  done
}
