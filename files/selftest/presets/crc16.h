#ifndef CRC16_H
#define CRC16_H

#include <stddef.h>
#include <stdint.h>

/* CRC-16/CCITT-FALSE (poly 0x1021, init 0xFFFF), as used by CCSDS. */
uint16_t crc16_ccitt(const uint8_t *data, size_t len);

#endif
