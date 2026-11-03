#include <stdio.h>
#include <string.h>

#include "crc16.h"

int main(void)
{
    const char *msg = "123456789";
    const uint16_t crc = crc16_ccitt((const uint8_t *)msg, strlen(msg));
    if (crc != 0x29B1u)
    {
        printf("FAIL: CRC-16/CCITT-FALSE = 0x%04X, expected 0x29B1\n", (unsigned)crc);
        return 1;
    }
    printf("PASS: CRC-16/CCITT-FALSE = 0x%04X\n", (unsigned)crc);
    return 0;
}
