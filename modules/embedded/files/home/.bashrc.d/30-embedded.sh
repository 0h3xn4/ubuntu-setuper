# shellcheck shell=bash
# ~/.bashrc.d/30-embedded.sh — installed by workstation-setup (embedded module)
# Edit freely. setup.sh will not overwrite this file unless run with
# FORCE_CONFIG=1.

# Serial console:  serial [/dev/ttyUSB0] [baud]     (exit tio: Ctrl-t q)
serial() { tio -b "${2:-115200}" "${1:-/dev/ttyUSB0}"; }

# Virtual CAN bus for testing without hardware:  vcan-up [vcan0]
vcan-up() {
  local dev="${1:-vcan0}"
  sudo modprobe vcan || return
  ip link show "$dev" >/dev/null 2>&1 || sudo ip link add dev "$dev" type vcan
  sudo ip link set up "$dev" && echo "$dev is up (try: candump $dev)"
}
