#ifndef CANDELA_PRIVATE_IO_H
#define CANDELA_PRIVATE_IO_H

#include <stdbool.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/*
 * Typedefs only. Private DisplayServices / IOAVService / CGS symbols are
 * resolved with dlsym in BrightnessKit — never declared extern here.
 */

typedef const void *IOAVServiceRef;
typedef const void *IOI2CConnectRef;

/*
 * MonitorPanel.MPDisplay is loaded at runtime. These helpers never link
 * the private framework at build time.
 */
bool CandelaDisplayCanChangeOrientation(uint32_t displayID);
int32_t CandelaDisplayGetOrientation(uint32_t displayID);
bool CandelaDisplaySetOrientation(uint32_t displayID, int32_t degrees);

#ifdef __cplusplus
}
#endif

#endif /* CANDELA_PRIVATE_IO_H */
