#ifndef CANDELA_PRIVATE_IO_H
#define CANDELA_PRIVATE_IO_H

/*
 * Typedefs only. Private DisplayServices / IOAVService / CGS symbols are
 * resolved with dlsym in BrightnessKit — never declared extern here.
 */

typedef const void *IOAVServiceRef;
typedef const void *IOI2CConnectRef;

#endif /* CANDELA_PRIVATE_IO_H */
