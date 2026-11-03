/* QEMU RISC-V virt machine: RAM starts at 0x80000000 */
ENTRY(_start)
MEMORY
{
  RAM (rwx) : ORIGIN = 0x80000000, LENGTH = 16M
}
_estack = ORIGIN(RAM) + LENGTH(RAM);
SECTIONS
{
  .text   : { KEEP(*(.text.start)) *(.text*) } > RAM
  .rodata : { *(.rodata*) *(.srodata*) } > RAM
  .data   : { *(.data*) *(.sdata*) } > RAM
  .bss    : { *(.bss*) *(.sbss*) } > RAM
}
