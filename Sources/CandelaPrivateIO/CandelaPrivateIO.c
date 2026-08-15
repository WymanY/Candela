#include "CandelaPrivateIO.h"

#include <objc/message.h>
#include <objc/runtime.h>
#include <dlfcn.h>
#include <dispatch/dispatch.h>
#include <math.h>
#include <CoreGraphics/CoreGraphics.h>

static bool loadMonitorPanel(void) {
    static dispatch_once_t once;
    static bool loaded = false;
    dispatch_once(&once, ^{
        void *handle = dlopen(
            "/System/Library/PrivateFrameworks/MonitorPanel.framework/MonitorPanel",
            RTLD_LAZY | RTLD_LOCAL
        );
        loaded = handle != NULL;
        if (!loaded) {
            handle = dlopen(
                "/System/Library/PrivateFrameworks/MonitorPanel.framework/Versions/A/MonitorPanel",
                RTLD_LAZY | RTLD_LOCAL
            );
            loaded = handle != NULL;
        }
    });
    return loaded;
}

static id sharedDisplayMgr(void) {
    if (!loadMonitorPanel()) {
        return nil;
    }
    Class cls = objc_getClass("MPDisplayMgr");
    if (cls == Nil) {
        return nil;
    }
    return ((id (*)(Class, SEL))objc_msgSend)(cls, sel_registerName("sharedMgr"));
}

// Owned by MPDisplayMgr. Do not release.
static id mpDisplay(uint32_t displayID) {
    if (displayID == 0) {
        return nil;
    }
    id mgr = sharedDisplayMgr();
    if (mgr == nil) {
        return nil;
    }
    return ((id (*)(id, SEL, int))objc_msgSend)(
        mgr,
        sel_registerName("displayWithID:"),
        (int)displayID
    );
}

bool CandelaDisplayCanChangeOrientation(uint32_t displayID) {
    id display = mpDisplay(displayID);
    if (display == nil) {
        return false;
    }
    return ((BOOL (*)(id, SEL))objc_msgSend)(
        display,
        sel_registerName("canChangeOrientation")
    );
}

int32_t CandelaDisplayGetOrientation(uint32_t displayID) {
    id display = mpDisplay(displayID);
    if (display == nil) {
        return (int32_t)lround(CGDisplayRotation(displayID));
    }
    return ((int (*)(id, SEL))objc_msgSend)(
        display,
        sel_registerName("orientation")
    );
}

bool CandelaDisplaySetOrientation(uint32_t displayID, int32_t degrees) {
    id display = mpDisplay(displayID);
    if (display == nil) {
        return false;
    }
    ((void (*)(id, SEL, int))objc_msgSend)(
        display,
        sel_registerName("setOrientation:"),
        (int)degrees
    );
    return true;
}
