#ifdef BUILD_MODE_DEV

#import "DevHooks.h"
#import "Logger.h"
#import <Foundation/Foundation.h>
#include <stdint.h>
#include <string.h>

#include <QtCore/QIODevice>
#include <QtCore/QObject>

// Original function pointers
ssize_t (*original_qIODevice_write)(QIODevice *self, const char *data, int64_t maxSize) = NULL;

int64_t (*original_qmlregister)(
    int64_t a1,
    int64_t a2,
    int64_t a3,
    int64_t a4,
    int64_t a5,
    int64_t a6,
    int a7,
    int64_t a8,
    int a9,
    int64_t a10) = NULL;

int64_t (*original_function_at_0x100011790)(uint64_t *a1) = NULL;
int64_t (*original_function_at_0x100011CE0)(int64_t a1, const QObject *a2, unsigned char a3, int64_t a4, QtSharedPointer::ExternalRefCountData *a5) = NULL;
int64_t (*original_function_at_0x10015A130)(int64_t a1, int64_t a2) = NULL;
void (*original_function_at_0x10015BC90)(int64_t a1, int64_t a2) = NULL;
int64_t (*original_function_at_0x10016D520)(int64_t a1, int64_t *a2, unsigned int a3, int64_t a4) = NULL;
void (*original_function_at_0x1001B6EE0)(int64_t a1, int64_t *a2, unsigned int a3) = NULL;

#pragma mark - Helper Functions

void logMemory(const char *label, void *address, size_t length) {
    if (!address) {
        NSLogger(@"[RMHook]   %s: (null)", label);
        return;
    }
    
    unsigned char *ptr = (unsigned char *)address;
    NSMutableString *hexLine = [NSMutableString stringWithFormat:@"[RMHook]   %s: ", label];
    
    for (size_t i = 0; i < length; i++) {
        [hexLine appendFormat:@"%02x ", ptr[i]];
        if ((i + 1) % 16 == 0 && i < length - 1) {
            NSLogger(@"%@", hexLine);
            hexLine = [NSMutableString stringWithString:@"[RMHook]                    "];
        }
    }
    
    // Log remaining bytes if any
    if ([hexLine length] > 28) {  // More than just the prefix
        NSLogger(@"%@", hexLine);
    }
}

void logStackTrace(const char *label) {
    NSLogger(@"[RMHook] %s - Stack trace:", label);
    NSArray<NSString *> *callStack = [NSThread callStackSymbols];
    NSUInteger count = [callStack count];
    
    for (NSUInteger i = 0; i < count; i++) {
        NSString *frame = callStack[i];
        NSLogger(@"[RMHook]   #%lu: %@", (unsigned long)i, frame);
    }
}

#pragma mark - Hook Implementations

extern "C" ssize_t hooked_qIODevice_write(
    QIODevice *self,
    const char *data,
    int64_t maxSize) {
    NSLogger(@"[RMHook] QIODevice::write called with maxSize: %lld", (long long)maxSize);
    
    logStackTrace("QIODevice::write call stack");
    logMemory("Data to write", (void *)data, (size_t)(maxSize < 64 ? maxSize : 64));
    
    if (original_qIODevice_write) {
        ssize_t result = original_qIODevice_write(self, data, maxSize);
        NSLogger(@"[RMHook] QIODevice::write result: %zd", result);
        return result;
    }
    NSLogger(@"[RMHook] WARNING: Original QIODevice::write not available, returning 0");
    return 0;
}

extern "C" int64_t hooked_function_at_0x100011790(uint64_t *a1) {
    NSLogger(@"[RMHook] Hook at 0x100011790 called!");
    NSLogger(@"[RMHook]   a1 = %p", a1);

    if (a1) {
        NSLogger(@"[RMHook]   *a1 = 0x%llx", (unsigned long long)*a1);
        logMemory("Memory at a1", (void *)a1, 64);
        logMemory("Memory at *a1", (void *)(*a1), 64);
    } else {
        NSLogger(@"[RMHook]   a1 is NULL");
    }

    if (original_function_at_0x100011790) {
        int64_t result = original_function_at_0x100011790(a1);
        NSLogger(@"[RMHook]   result = 0x%llx", (unsigned long long)result);
        return result;
    }

    NSLogger(@"[RMHook] WARNING: Original function at 0x100011790 not available, returning 0");
    return 0;
}

extern "C" int64_t hooked_function_at_0x100011CE0(
    int64_t a1,
    const QObject *a2,
    unsigned char a3,
    int64_t a4,
    QtSharedPointer::ExternalRefCountData *a5) {
    // This function appears to be a QML type registration wrapper
    // It calls QQmlPrivate::qmlregister(3, &registrationData)
    // 
    // Based on IDA analysis:
    // - a1: stored at offset +0x8 in registration struct (likely type metadata ptr)
    // - a2: NOT actually a QObject* - low bits used as: ((_WORD)a2 << 8) | a3
    //       This suggests a2's low 16 bits are a version/revision number
    // - a3: combined with a2 to form v17 (flags/version field)
    // - a4: stored at offset +0x18 (likely URI or type info pointer)
    // - a5: ExternalRefCountData* for shared pointer ref counting
    
    NSLogger(@"[RMHook] ========================================");
    NSLogger(@"[RMHook] Hook at 0x100011CE0 (QML Type Registration)");
    NSLogger(@"[RMHook] ========================================");
    
    NSLogger(@"[RMHook]   a1 (typeMetadata?)  = 0x%llx", (unsigned long long)a1);
    
    uint16_t a2_low = (uint16_t)(uintptr_t)a2;
    uint16_t combined_v17 = (a2_low << 8) | a3;
    NSLogger(@"[RMHook]   a2 (raw)            = %p (0x%llx)", a2, (unsigned long long)(uintptr_t)a2);
    NSLogger(@"[RMHook]   a2 low 16 bits      = 0x%04x (%u)", a2_low, a2_low);
    NSLogger(@"[RMHook]   a3 (flags/version)  = 0x%02x (%u)", a3, a3);
    NSLogger(@"[RMHook]   v17 = (a2<<8)|a3    = 0x%04x (%u)", combined_v17, combined_v17);
    NSLogger(@"[RMHook]   a4 (typeInfo/URI?)  = 0x%llx", (unsigned long long)a4);
    NSLogger(@"[RMHook]   a5 (refCountData)   = %p", a5);
    
    if (a1) {
        logMemory("Memory at a1 (typeMetadata)", (void *)a1, 64);
        void **vtable = (void **)a1;
        NSLogger(@"[RMHook]   a1 vtable/first ptr = %p", *vtable);
    }
    
    if (a4) {
        logMemory("Memory at a4 (typeInfo)", (void *)a4, 64);
        const char *maybeStr = (const char *)a4;
        bool isPrintable = true;
        int len = 0;
        for (int i = 0; i < 64 && maybeStr[i]; i++) {
            if (maybeStr[i] < 0x20 || maybeStr[i] > 0x7e) {
                isPrintable = false;
                break;
            }
            len++;
        }
        if (isPrintable && len > 0) {
            NSLogger(@"[RMHook]   a4 as string: \"%.*s\"", len, maybeStr);
        }
    }
    
    if (a5) {
        logMemory("Memory at a5 (refCountData)", (void *)a5, 32);
    }
    
    logStackTrace("QML Registration context");

    if (original_function_at_0x100011CE0) {
        int64_t result = original_function_at_0x100011CE0(a1, a2, a3, a4, a5);
        NSLogger(@"[RMHook]   result (qmlregister return) = %u (0x%x)", (unsigned int)result, (unsigned int)result);
        NSLogger(@"[RMHook] ========================================");
        return result;
    }

    NSLogger(@"[RMHook] WARNING: Original function at 0x100011CE0 not available, returning 0");
    return 0;
}

extern "C" int64_t hooked_function_at_0x10015A130(int64_t a1, int64_t a2) {
    NSLogger(@"[RMHook] Hook at 0x10015A130 called!");
    NSLogger(@"[RMHook]   a1 = 0x%llx", (unsigned long long)a1);
    NSLogger(@"[RMHook]   a2 = 0x%llx", (unsigned long long)a2);

    logMemory("Memory at a1", (void *)a1, 64);
    logMemory("Memory at a2", (void *)a2, 64);

    if (original_function_at_0x10015A130) {
        int64_t result = original_function_at_0x10015A130(a1, a2);
        NSLogger(@"[RMHook]   result = 0x%llx", (unsigned long long)result);
        return result;
    }

    NSLogger(@"[RMHook] WARNING: Original function at 0x10015A130 not available, returning 0");
    return 0;
}

extern "C" void hooked_function_at_0x10015BC90(int64_t a1, int64_t a2) {
    NSLogger(@"[RMHook] Hook at 0x10015BC90 called!");
    NSLogger(@"[RMHook]   a1 = 0x%llx", (unsigned long long)a1);
    NSLogger(@"[RMHook]   a2 = 0x%llx", (unsigned long long)a2);

    logMemory("Memory at a1", (void *)a1, 64);
    logMemory("Memory at a2", (void *)a2, 64);

    if (original_function_at_0x10015BC90) {
        original_function_at_0x10015BC90(a1, a2);
        NSLogger(@"[RMHook]   original function returned (void)");
        return;
    }

    NSLogger(@"[RMHook] WARNING: Original function at 0x10015BC90 not available");
}

extern "C" int64_t hooked_function_at_0x10016D520(int64_t a1, int64_t *a2, unsigned int a3, int64_t a4) {
    NSLogger(@"[RMHook] Hook at 0x10016D520 called!");
    NSLogger(@"[RMHook]   a1 = 0x%llx", (unsigned long long)a1);
    NSLogger(@"[RMHook]   a2 = %p", a2);
    if (a2) {
        NSLogger(@"[RMHook]   *a2 = 0x%llx", (unsigned long long)*a2);
    }
    NSLogger(@"[RMHook]   a3 = %u (0x%x)", a3, a3);
    NSLogger(@"[RMHook]   a4 = 0x%llx", (unsigned long long)a4);
    
    logMemory("Memory at a1", (void *)a1, 64);
    logMemory("Memory at a2", (void *)a2, 64);
    
    if (a2 && *a2 != 0) {
        logMemory("Memory at *a2", (void *)*a2, 64);
    }
    
    logMemory("Memory at a4", (void *)a4, 64);
    
    if (original_function_at_0x10016D520) {
        int64_t result = original_function_at_0x10016D520(a1, a2, a3, a4);
        NSLogger(@"[RMHook]   result = 0x%llx", (unsigned long long)result);
        return result;
    }
    
    NSLogger(@"[RMHook] WARNING: Original function not available, returning 0");
    return 0;
}

extern "C" void hooked_function_at_0x1001B6EE0(int64_t a1, int64_t *a2, unsigned int a3) {
    NSLogger(@"[RMHook] Hook at 0x1001B6EE0 called!");
    NSLogger(@"[RMHook]   a1 = 0x%llx", (unsigned long long)a1);
    
    // At a1 (PdfExporter object):
    // +0x10 contains a QString (likely document name)
    NSLogger(@"[RMHook] Reading QString at a1+0x10:");
    logMemory("a1 + 0x10 (raw)", (void *)(a1 + 0x10), 64);

    void **qstrPtr = (void **)(a1 + 0x10);
    void *dataPtr = *qstrPtr;

    if (!dataPtr) {
        NSLogger(@"[RMHook] QString has null data pointer");
        return;
    }

    // Try reading potential size fields near dataPtr
    int32_t size = 0;
    for (int delta = 4; delta <= 32; delta += 4) {
        int32_t candidate = *(int32_t *)((char *)dataPtr - delta);
        if (candidate > 0 && candidate < 10000) {
            size = candidate;
            NSLogger(@"[RMHook] QString plausible size=%d (found at -%d)", size, delta);
            break;
        }
    }

    if (size > 0) {
        NSString *qstringValue = [[NSString alloc] initWithCharacters:(unichar *)dataPtr length:size];
        NSLogger(@"[RMHook] QString value: \"%@\"", qstringValue);
    } else {
        NSLogger(@"[RMHook] QString: could not find valid size");
    }
    
    NSLogger(@"[RMHook]   a2 = %p", a2);
    if (a2) {
        NSLogger(@"[RMHook]   *a2 = 0x%llx", (unsigned long long)*a2);
    }
    NSLogger(@"[RMHook]   a3 = %u (0x%x)", a3, a3);
    
    if (original_function_at_0x1001B6EE0) {
        original_function_at_0x1001B6EE0(a1, a2, a3);
        NSLogger(@"[RMHook] Original function at 0x1001B6EE0 executed");
    } else {
        NSLogger(@"[RMHook] WARNING: Original function not available");
    }
}

extern "C" int64_t hooked_qmlregister(
    int64_t a1,
    int64_t a2,
    int64_t a3,
    int64_t a4,
    int64_t a5,
    int64_t a6,
    int a7,
    int64_t a8,
    int a9,
    int64_t a10) {
    
    NSLogger(@"[RMHook] ========================================");
    NSLogger(@"[RMHook] QQmlPrivate::qmlregister called!");
    NSLogger(@"[RMHook] ========================================");
    NSLogger(@"[RMHook]   a1 (RegistrationType) = 0x%llx (%lld)", (unsigned long long)a1, (long long)a1);
    NSLogger(@"[RMHook]   a2  = 0x%llx (%lld)", (unsigned long long)a2, (long long)a2);
    NSLogger(@"[RMHook]   a3  = 0x%llx (%lld)", (unsigned long long)a3, (long long)a3);
    NSLogger(@"[RMHook]   a4  = 0x%llx (%lld)", (unsigned long long)a4, (long long)a4);
    NSLogger(@"[RMHook]   a5  = 0x%llx (%lld)", (unsigned long long)a5, (long long)a5);
    NSLogger(@"[RMHook]   a6  = 0x%llx (%lld)", (unsigned long long)a6, (long long)a6);
    NSLogger(@"[RMHook]   a7  = 0x%x (%d)", a7, a7);
    NSLogger(@"[RMHook]   a8  = 0x%llx (%lld)", (unsigned long long)a8, (long long)a8);
    NSLogger(@"[RMHook]   a9  = 0x%x (%d)", a9, a9);
    NSLogger(@"[RMHook]   a10 = 0x%llx (%lld)", (unsigned long long)a10, (long long)a10);
    
    // Check for PlatformHelpers registration
    // a1 == 0 means TypeRegistration (object registration)
    // a4 must be a valid pointer (not a small integer like 0, 1, 2, etc.)
    if (a1 == 0 && a4 > 0x10000) {
        const char *typeName = (const char *)a4;
        
        int len = 0;
        bool isValid = true;
        for (int i = 0; i < 256; i++) {
            char c = typeName[i];
            if (c == '\0') {
                break;
            }
            if (c < 0x20 || c > 0x7e) {
                isValid = false;
                break;
            }
            len++;
        }
        
        if (isValid && len > 0) {
            NSLogger(@"[RMHook]   typeName (a4) = \"%.*s\"", len, typeName);
            
            if (len == 15 && strncmp(typeName, "PlatformHelpers", 15) == 0) {
                NSLogger(@"[RMHook] !!! FOUND PlatformHelpers type registration !!!");
                NSLogger(@"[RMHook]   factory ptr (a2) = %p", (void *)a2);
                NSLogger(@"[RMHook]   a3 (metaObject?) = %p", (void *)a3);
                NSLogger(@"[RMHook]   a5 = %p", (void *)a5);
                NSLogger(@"[RMHook]   a6 = %p", (void *)a6);
                logMemory("Factory ptr memory", (void *)a2, 64);
                logMemory("a3 memory (metaObject?)", (void *)a3, 64);
                logStackTrace("PlatformHelpers registration");
            }
        }
    }
    
    // Try to interpret a2 as memory region for other registration types
    if (a2 > 0x10000 && a1 != 0) {
        logMemory("Memory at a2", (void *)a2, 64);
        const char *maybeStr = (const char *)a2;
        bool isPrintable = true;
        int len = 0;
        for (int i = 0; i < 128 && maybeStr[i]; i++) {
            if (maybeStr[i] < 0x20 || maybeStr[i] > 0x7e) {
                isPrintable = false;
                break;
            }
            len++;
        }
        if (isPrintable && len > 0) {
            NSLogger(@"[RMHook]   a2 as string: \"%.*s\"", len, maybeStr);
        }
    }
    
    int64_t result = 0;
    if (original_qmlregister) {
        result = original_qmlregister(a1, a2, a3, a4, a5, a6, a7, a8, a9, a10);
        NSLogger(@"[RMHook]   result = 0x%llx (%lld)", (unsigned long long)result, (long long)result);
    } else {
        NSLogger(@"[RMHook] WARNING: Original qmlregister not available!");
    }
    
    NSLogger(@"[RMHook] ========================================");
    return result;
}

#endif // BUILD_MODE_DEV
