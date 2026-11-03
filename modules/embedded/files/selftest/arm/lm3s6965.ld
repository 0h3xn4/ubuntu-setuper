/* Memory map of the TI LM3S6965 (QEMU machine lm3s6965evb) */
ENTRY(reset_handler)
MEMORY
{
  FLASH (rx)  : ORIGIN = 0x00000000, LENGTH = 256K
  RAM   (rwx) : ORIGIN = 0x20000000, LENGTH = 64K
}
_estack = ORIGIN(RAM) + LENGTH(RAM);
SECTIONS
{
  .text : { KEEP(*(.vectors)) *(.text*) *(.rodata*) } > FLASH
  /DISCARD/ : { *(.ARM.exidx*) *(.comment) }
}
