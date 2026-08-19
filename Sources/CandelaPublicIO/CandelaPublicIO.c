#include "CandelaPublicIO.h"

#include <CoreGraphics/CoreGraphics.h>
#include <IOKit/IOKitLib.h>
#include <IOKit/graphics/IOGraphicsLib.h>
#include <IOKit/graphics/IOGraphicsTypes.h>
#include <IOKit/i2c/IOI2CInterface.h>
#include <math.h>
#include <string.h>

#ifndef kIOFBSetTransform
#define kIOFBSetTransform 0x00000400
#endif

#ifndef kIOScaleRotate0
#define kIOScaleRotate0 0x00000000
#endif

#ifndef kIOScaleRotate90
#define kIOScaleRotate90 0x00000030
#endif

#ifndef kIOScaleRotate180
#define kIOScaleRotate180 0x00000060
#endif

#ifndef kIOScaleRotate270
#define kIOScaleRotate270 0x00000050
#endif

static uint32_t scaleRotate(int32_t degrees) {
    switch (degrees) {
        case 90:
            return kIOScaleRotate90;
        case 180:
            return kIOScaleRotate180;
        case 270:
            return kIOScaleRotate270;
        default:
            return kIOScaleRotate0;
    }
}

static bool displayUnitFromLocation(CFTypeRef locationValue, uint32_t *unit) {
    if (locationValue == NULL || unit == NULL || CFGetTypeID(locationValue) != CFStringGetTypeID()) {
        return false;
    }

    CFStringRef location = (CFStringRef)locationValue;
    CFRange at = CFStringFind(location, CFSTR("@"), kCFCompareBackwards);
    if (at.location == kCFNotFound) {
        return false;
    }
    CFIndex start = at.location + at.length;
    CFIndex length = CFStringGetLength(location) - start;
    if (length <= 0) {
        return false;
    }

    uint32_t parsed = 0;
    for (CFIndex index = start; index < CFStringGetLength(location); index++) {
        UniChar character = CFStringGetCharacterAtIndex(location, index);
        if (character < '0' || character > '9') {
            return false;
        }
        uint32_t digit = (uint32_t)(character - '0');
        if (parsed > (UINT32_MAX - digit) / 10) {
            return false;
        }
        parsed = parsed * 10 + digit;
    }
    *unit = parsed;
    return true;
}

static bool dictionaryMatchesDisplay(CFDictionaryRef info, uint32_t displayID) {
    if (info == NULL) {
        return false;
    }
    int64_t infoVendor = 0;
    int64_t infoProduct = 0;
    int64_t infoSerial = 0;
    CFNumberRef vendorNumber = CFDictionaryGetValue(info, CFSTR(kDisplayVendorID));
    CFNumberRef productNumber = CFDictionaryGetValue(info, CFSTR(kDisplayProductID));
    CFNumberRef serialNumber = CFDictionaryGetValue(info, CFSTR(kDisplaySerialNumber));
    if (vendorNumber != NULL) {
        CFNumberGetValue(vendorNumber, kCFNumberSInt64Type, &infoVendor);
    }
    if (productNumber != NULL) {
        CFNumberGetValue(productNumber, kCFNumberSInt64Type, &infoProduct);
    }
    if (serialNumber != NULL) {
        CFNumberGetValue(serialNumber, kCFNumberSInt64Type, &infoSerial);
    }
    uint32_t vendor = CGDisplayVendorNumber(displayID);
    uint32_t product = CGDisplayModelNumber(displayID);
    uint32_t serial = CGDisplaySerialNumber(displayID);
    if ((uint32_t)infoVendor != vendor || (uint32_t)infoProduct != product) {
        return false;
    }
    if (serial != 0 && infoSerial != 0 && (uint32_t)infoSerial != serial) {
        return false;
    }
    uint32_t infoUnit = 0;
    CFTypeRef location = CFDictionaryGetValue(info, CFSTR(kIODisplayLocationKey));
    if (displayUnitFromLocation(location, &infoUnit) && infoUnit != CGDisplayUnitNumber(displayID)) {
        return false;
    }
    return true;
}

static io_service_t matchingService(uint32_t displayID, const char *className) {
    io_iterator_t iterator = 0;
    if (IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching(className), &iterator) != KERN_SUCCESS) {
        return 0;
    }

    io_service_t fallback = 0;
    io_service_t service = IOIteratorNext(iterator);
    while (service != 0) {
        CFDictionaryRef info = IODisplayCreateInfoDictionary(service, kIODisplayOnlyPreferredName);
        bool matched = dictionaryMatchesDisplay(info, displayID);
        if (info != NULL) {
            CFRelease(info);
        }
        if (matched) {
            if (fallback != 0) {
                IOObjectRelease(fallback);
            }
            IOObjectRelease(iterator);
            return service;
        }
        if (fallback == 0 && CGDisplayIsBuiltin(displayID) != 0) {
            fallback = service;
            service = IOIteratorNext(iterator);
            continue;
        }
        IOObjectRelease(service);
        service = IOIteratorNext(iterator);
    }
    IOObjectRelease(iterator);
    return fallback;
}

static io_service_t displayConnect(uint32_t displayID) {
    return matchingService(displayID, "IODisplayConnect");
}

static io_service_t framebuffer(uint32_t displayID) {
    io_service_t service = matchingService(displayID, "IOFramebuffer");
    if (service != 0) {
        return service;
    }
    io_service_t connect = displayConnect(displayID);
    if (connect == 0) {
        return 0;
    }
    io_service_t parent = 0;
    if (IORegistryEntryGetParentEntry(connect, kIOServicePlane, &parent) == KERN_SUCCESS) {
        IOObjectRelease(connect);
        return parent;
    }
    IOObjectRelease(connect);
    return 0;
}

int32_t CandelaPublicDisplayGetOrientation(uint32_t displayID) {
    return (int32_t)lround(CGDisplayRotation(displayID));
}

bool CandelaPublicDisplayCanChangeOrientation(uint32_t displayID) {
    if (displayID == 0 || CGDisplayIsBuiltin(displayID) != 0) {
        return false;
    }
    io_service_t service = framebuffer(displayID);
    if (service == 0) {
        return false;
    }
    IOObjectRelease(service);
    return true;
}

bool CandelaPublicDisplaySetOrientation(uint32_t displayID, int32_t degrees) {
    if (!CandelaPublicDisplayCanChangeOrientation(displayID)) {
        return false;
    }
    io_service_t service = framebuffer(displayID);
    if (service == 0) {
        return false;
    }
    uint32_t option = kIOFBSetTransform | (scaleRotate(degrees) << 16);
    IOReturn status = IOServiceRequestProbe(service, option);
    IOObjectRelease(service);
    return status == kIOReturnSuccess;
}

static IOI2CConnectRef openI2C(uint32_t displayID) {
    io_service_t fb = framebuffer(displayID);
    if (fb == 0) {
        return NULL;
    }

    IOItemCount count = 0;
    if (IOFBGetI2CInterfaceCount(fb, &count) != kIOReturnSuccess || count == 0) {
        IOObjectRelease(fb);
        return NULL;
    }

    for (IOItemCount bus = 0; bus < count; bus++) {
        io_service_t interface = 0;
        if (IOFBCopyI2CInterfaceForBus(fb, bus, &interface) != kIOReturnSuccess || interface == 0) {
            continue;
        }
        IOI2CConnectRef connect = NULL;
        IOReturn status = IOI2CInterfaceOpen(interface, kNilOptions, &connect);
        IOObjectRelease(interface);
        if (status == kIOReturnSuccess && connect != NULL) {
            IOObjectRelease(fb);
            return connect;
        }
    }
    IOObjectRelease(fb);
    return NULL;
}

static IOOptionBits supportedReplyTransactionType(io_service_t interface) {
    CFTypeRef property = IORegistryEntryCreateCFProperty(
        interface,
        CFSTR(kIOI2CTransactionTypesKey),
        kCFAllocatorDefault,
        kNilOptions
    );
    if (property == NULL || CFGetTypeID(property) != CFNumberGetTypeID()) {
        if (property != NULL) {
            CFRelease(property);
        }
        return kIOI2CNoTransactionType;
    }

    uint64_t types = 0;
    bool read = CFNumberGetValue((CFNumberRef)property, kCFNumberSInt64Type, &types);
    CFRelease(property);
    if (!read) {
        return kIOI2CNoTransactionType;
    }
    if ((types & (1ULL << kIOI2CDDCciReplyTransactionType)) != 0) {
        return kIOI2CDDCciReplyTransactionType;
    }
    if ((types & (1ULL << kIOI2CSimpleTransactionType)) != 0) {
        return kIOI2CSimpleTransactionType;
    }
    return kIOI2CNoTransactionType;
}

static bool sendI2CRequestOnAnyBus(
    uint32_t displayID,
    const IOI2CRequest *template,
    bool selectReplyTransactionType
) {
    io_service_t fb = framebuffer(displayID);
    if (fb == 0) {
        return false;
    }

    IOItemCount count = 0;
    if (IOFBGetI2CInterfaceCount(fb, &count) != kIOReturnSuccess || count == 0) {
        IOObjectRelease(fb);
        return false;
    }

    bool succeeded = false;
    for (IOItemCount bus = 0; bus < count; bus++) {
        io_service_t interface = 0;
        if (IOFBCopyI2CInterfaceForBus(fb, bus, &interface) != kIOReturnSuccess || interface == 0) {
            continue;
        }

        IOOptionBits replyTransactionType = template->replyTransactionType;
        if (selectReplyTransactionType) {
            replyTransactionType = supportedReplyTransactionType(interface);
            if (replyTransactionType == kIOI2CNoTransactionType) {
                IOObjectRelease(interface);
                continue;
            }
        }

        IOI2CConnectRef connect = NULL;
        IOReturn opened = IOI2CInterfaceOpen(interface, kNilOptions, &connect);
        IOObjectRelease(interface);
        if (opened != kIOReturnSuccess || connect == NULL) {
            continue;
        }

        IOI2CRequest request = *template;
        request.replyTransactionType = replyTransactionType;
        IOReturn started = IOI2CSendRequest(connect, kNilOptions, &request);
        IOI2CInterfaceClose(connect, kNilOptions);
        if (started == kIOReturnSuccess && request.result == kIOReturnSuccess) {
            succeeded = true;
            break;
        }
    }

    IOObjectRelease(fb);
    return succeeded;
}

bool CandelaPublicI2CAvailable(uint32_t displayID) {
    IOI2CConnectRef connect = openI2C(displayID);
    if (connect == NULL) {
        return false;
    }
    IOI2CInterfaceClose(connect, kNilOptions);
    return true;
}

bool CandelaPublicI2CWrite(uint32_t displayID, const uint8_t *bytes, uint32_t count) {
    if (bytes == NULL || count == 0) {
        return false;
    }

    IOI2CRequest request;
    memset(&request, 0, sizeof(request));
    request.sendTransactionType = kIOI2CSimpleTransactionType;
    request.sendAddress = 0x6E;
    request.sendBuffer = (vm_address_t)(uintptr_t)bytes;
    request.sendBytes = count;
    request.replyTransactionType = kIOI2CNoTransactionType;
    request.minReplyDelay = 0;

    return sendI2CRequestOnAnyBus(displayID, &request, false);
}

bool CandelaPublicI2CRead(
    uint32_t displayID,
    const uint8_t *send,
    uint32_t sendCount,
    uint8_t *reply,
    uint32_t replyCount
) {
    if (send == NULL || reply == NULL || sendCount == 0 || replyCount == 0) {
        return false;
    }

    IOI2CRequest request;
    memset(&request, 0, sizeof(request));
    request.sendTransactionType = kIOI2CSimpleTransactionType;
    request.sendAddress = 0x6E;
    request.sendBuffer = (vm_address_t)(uintptr_t)send;
    request.sendBytes = sendCount;
    request.replyTransactionType = kIOI2CNoTransactionType;
    request.replyAddress = 0x6F;
    request.replySubAddress = 0x51;
    request.replyBuffer = (vm_address_t)(uintptr_t)reply;
    request.replyBytes = replyCount;
    request.minReplyDelay = 10;

    return sendI2CRequestOnAnyBus(displayID, &request, true);
}
