## Embedded module

| Command | What it does |
|---|---|
| `ws-init --embedded` | Generic starter files plus CMake cross toolchain files, ARM/RISC-V presets and a `.clangd` with a target note |
| `ws-devname list` | Show connected USB serial adapters and their stable names |
| `ws-devname add /dev/ttyUSB0 obc-console` | Name an adapter; it then always appears as `/dev/ws/obc-console` |
| `ws-devname remove obc-console` | Remove a name |
| `serial /dev/ws/obc-console 115200` | Open a serial console (exit: `Ctrl-t` then `q`) |
| `vcan-up` | Create virtual CAN bus `vcan0` for testing without hardware |

### Cross builds with CMake presets

After `ws-init --embedded`:

```bash
cmake --preset arm-cortex-m && cmake --build --preset arm-cortex-m
cmake --preset riscv        && cmake --build --preset riscv
```

When working on target code, change `.clangd` to `build/arm-cortex-m` so
clangd sees the cross compiler's flags and headers.

Target CPU flags belong in your project, e.g. for a Cortex-M4F:
`-mcpu=cortex-m4 -mthumb -mfloat-abi=hard -mfpu=fpv4-sp-d16 --specs=nano.specs`

Rust bare-metal: `cargo build --target thumbv7em-none-eabihf`
(also `thumbv6m-none-eabi`, `thumbv7m-none-eabi`, `riscv32imac-unknown-none-elf`).

### Verification tools

```bash
flawfinder src/                                    # security-relevant patterns
lizard -C 10 src/                                  # functions with complexity > 10
cbmc file.c --function f --bounds-check --pointer-check   # bounded model checking
```

### Debugging on hardware

```bash
# Terminal 1: OpenOCD (examples: ST-Link + STM32F4, CMSIS-DAP + generic).
# OpenOCD listens on ALL network interfaces by default (gdb :3333, telnet
# :4444, tcl :6666) - bind it to this machine only:
openocd -c "bindto 127.0.0.1" -f interface/stlink.cfg -f target/stm32f4x.cfg
openocd -c "bindto 127.0.0.1" -f interface/cmsis-dap.cfg -f target/<your-target>.cfg

# Terminal 2: GDB
gdb-multiarch build/arm-cortex-m/app.elf \
  -ex "target extended-remote :3333" -ex "monitor reset halt" -ex "load"
```

With several probes connected, select one by serial number in OpenOCD
(`adapter serial <serial>`). Rust/probe-rs: `probe-rs list`, then
`probe-rs run --chip <chip> target.elf`.

### Running target code in QEMU (no hardware)

```bash
qemu-system-arm -M lm3s6965evb -nographic -kernel app.elf        # Cortex-M3
qemu-system-riscv64 -M virt -bios none -nographic -kernel app.elf
qemu-system-sparc -M leon3_generic -nographic -kernel app.elf    # LEON3
# Add  -s -S  to wait for GDB on port 1234:  gdb-multiarch app.elf -ex "target remote :1234"
# Add  -semihosting-config enable=on,target=native  for semihosting output
```

### Serial and CAN

```bash
ws-devname list                       # what is connected
serial /dev/ws/obc-console 115200     # console (Ctrl-t q to exit)
ls -l /dev/serial/by-id/               # built-in stable (long) names

vcan-up                                # virtual CAN bus vcan0
candump vcan0                          # watch traffic
cansend vcan0 123#DEADBEEF             # send a frame
```

Named devices live in `/etc/udev/rules.d/70-workstation-devices.rules`.

### Offline packages added by this module

Python: `pyserial python-can spacepackets crc` (`uv pip install ...`).
Rust crates: `heapless cortex-m cortex-m-rt embedded-hal defmt postcard ...`
(`cargo add ...`). Optional SPICE kernels: `~/.local/share/workstation/spice/generic.tm`.
