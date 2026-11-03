# shellcheck shell=bash
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
  echo dialout
  echo plugdev
  if on "$INSTALL_WIRESHARK"; then echo wireshark; fi
}

mod_embedded_uv_tools() {
  if on "$INSTALL_VERIFICATION"; then printf '%s\n' "${EMBEDDED_UV_TOOLS_VERIFICATION[@]}"; fi
  if on "$INSTALL_FPRIME_BOOTSTRAP"; then echo fprime-bootstrap; fi
}
mod_embedded_cargo_tools() { printf '%s\n' "${EMBEDDED_CARGO_TOOLS[@]}"; }
mod_embedded_rust_targets() { printf '%s\n' "${EMBEDDED_RUST_TARGETS[@]}"; }
mod_embedded_py_packages()  { printf '%s\n' "${EMBEDDED_PY_PACKAGES[@]}"; }
mod_embedded_rust_crates()  { printf '%s\n' "${EMBEDDED_RUST_CRATES[@]}"; }

mod_embedded_manifest_tools() {
  printf '%s\n' arm-none-eabi-gcc riscv64-unknown-elf-gcc gdb-multiarch qemu-system-arm \
    qemu-system-riscv64 qemu-system-sparc openocd cbmc probe-rs tio
}

mod_embedded_manifest_extra() {
  if [[ -d $DATA_DIR/spice ]]; then echo "SPICE kernels:"; (cd "$DATA_DIR/spice" && sha256sum -- * | sed 's/^/  /'); fi
}

mod_embedded_check_caches() {
  if on "$INSTALL_SPICE_KERNELS"; then log "SPICE generic kernels -> $DATA_DIR/spice"; fi
}

mod_embedded_steps() {
  step "Embedded toolchain"             embedded_toolchain
  if on "$INSTALL_WIRESHARK";    then step "Wireshark"          wireshark_setup; fi
  if on "$INSTALL_VERIFICATION"; then step "Verification tools" verification_tools; fi
  if on "$INSTALL_GUI_TOOLS";    then step "Embedded GUI tools" embedded_gui_tools; fi
  step "Embedded helpers and templates" embedded_files
  if on "$INSTALL_SPICE_KERNELS"; then step "SPICE generic kernels" cache_spice; fi
}

embedded_toolchain() {
  apt_install "${PKGS_EMBEDDED[@]}"
  # Serial ports and USB debug probes without sudo. Probe udev rules from the
  # packages apply the next time a device is plugged in.
  add_to_groups dialout plugdev
}

wireshark_setup() {
  echo "wireshark-common wireshark-common/install-setuid boolean true" \
    | sudo debconf-set-selections
  apt_install "${PKGS_WIRESHARK[@]}"
  if dpkg -s wireshark-common >/dev/null 2>&1; then
    sudo env DEBIAN_FRONTEND=noninteractive dpkg-reconfigure -f noninteractive wireshark-common
    record_undo "sudo dpkg-reconfigure wireshark-common   # answer 'No' to disallow non-root capture"
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

t_emb_arm_qemu() {
  needs arm-none-eabi-gcc qemu-system-arm
  arm-none-eabi-gcc -mcpu=cortex-m3 -mthumb -O1 -ffreestanding -nostdlib \
    -T "$EMBEDDED_DIR/files/selftest/arm/lm3s6965.ld" "$EMBEDDED_DIR/files/selftest/arm/semihost.c" -o arm.elf
  timeout 30 qemu-system-arm -M lm3s6965evb -nographic -monitor none -serial none \
    -semihosting-config enable=on,target=native -kernel arm.elf < /dev/null | tee qemu.txt
  grep -q "ARM Cortex-M self-test OK" qemu.txt
}

t_emb_riscv_qemu() {
  needs riscv64-unknown-elf-gcc qemu-system-riscv64
  riscv64-unknown-elf-gcc -march=rv64imac -mabi=lp64 -mcmodel=medany -mno-relax -O1 \
    -ffreestanding -nostdlib -T "$EMBEDDED_DIR/files/selftest/riscv/virt.ld" \
    "$EMBEDDED_DIR/files/selftest/riscv/semihost.c" -o riscv.elf
  timeout 30 qemu-system-riscv64 -M virt -bios none -nographic -monitor none -serial none \
    -semihosting-config enable=on,target=native -kernel riscv.elf < /dev/null | tee qemu.txt
  grep -q "RISC-V self-test OK" qemu.txt
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
