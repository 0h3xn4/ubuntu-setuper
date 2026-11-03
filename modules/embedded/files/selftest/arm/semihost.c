/* Bare-metal ARM Cortex-M self-test for QEMU (lm3s6965evb).
 * No C library: a minimal vector table plus ARM semihosting calls, so QEMU
 * prints the message on the host and exits with status 0. */
#include <stdint.h>

extern char _estack[];          /* top of RAM, from the linker script */
void reset_handler(void);

__attribute__((section(".vectors"), used))
const uintptr_t vectors[] = {
    (uintptr_t)_estack,         /* initial stack pointer */
    (uintptr_t)reset_handler,   /* reset handler (Thumb bit set by linker) */
};

static int semihost(int op, const void *arg)
{
    register int r0 __asm__("r0") = op;
    register const void *r1 __asm__("r1") = arg;
    __asm__ volatile("bkpt 0xAB" : "+r"(r0) : "r"(r1) : "memory");
    return r0;
}

void reset_handler(void)
{
    semihost(0x04, "ARM Cortex-M self-test OK\n");  /* SYS_WRITE0 */
    semihost(0x18, (const void *)0x20026);          /* SYS_EXIT: ApplicationExit */
    for (;;) {
    }
}
