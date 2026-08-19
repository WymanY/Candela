#ifndef CANDELA_PUBLIC_IO_H
#define CANDELA_PUBLIC_IO_H

#include <stdbool.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

bool CandelaPublicDisplayCanChangeOrientation(uint32_t displayID);
int32_t CandelaPublicDisplayGetOrientation(uint32_t displayID);
bool CandelaPublicDisplaySetOrientation(uint32_t displayID, int32_t degrees);
bool CandelaPublicI2CAvailable(uint32_t displayID);
bool CandelaPublicI2CWrite(uint32_t displayID, const uint8_t *bytes, uint32_t count);
bool CandelaPublicI2CRead(
    uint32_t displayID,
    const uint8_t *send,
    uint32_t sendCount,
    uint8_t *reply,
    uint32_t replyCount
);

#ifdef __cplusplus
}
#endif

#endif /* CANDELA_PUBLIC_IO_H */
