/* Bare-metal RISC-V (RV64) self-test for QEMU (virt machine, -bios none).
 * No C library: a tiny startup that sets the stack pointer, plus RISC-V
 * semihosting calls, so QEMU prints the message and exits with status 0. */

__asm__(".section .text.start, \"ax\"\n"
        ".global _start\n"
        "_start:\n"
        "  la sp, _estack\n"
        "  call main\n"
        "1: j 1b\n");

static long semihost(long op, const void *arg)
{
    register long a0 __asm__("a0") = op;
    register const void *a1 __asm__("a1") = arg;
    /* The semihosting trap is this exact uncompressed 3-instruction sequence. */
    __asm__ volatile(".option push\n"
                     ".option norvc\n"
                     ".balign 16\n"
                     "slli x0, x0, 0x1f\n"
                     "ebreak\n"
                     "srai x0, x0, 7\n"
                     ".option pop\n"
                     : "+r"(a0) : "r"(a1) : "memory");
    return a0;
}

int main(void)
{
    semihost(0x04, "RISC-V self-test OK\n");  /* SYS_WRITE0 */
    long exit_block[2] = {0x20026, 0};         /* ApplicationExit, status 0 */
    semihost(0x18, exit_block);                /* SYS_EXIT (64-bit form) */
    for (;;) {
    }
}
