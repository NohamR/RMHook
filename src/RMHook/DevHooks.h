#ifndef DEV_HOOKS_H
#define DEV_HOOKS_H

#ifdef BUILD_MODE_DEV

#import <Foundation/Foundation.h>
#include <stdint.h>

// Forward declarations for Qt types
class QIODevice;
class QObject;
namespace QtSharedPointer {
    struct ExternalRefCountData;
}

extern ssize_t (*original_qIODevice_write)(QIODevice *self, const char *data, int64_t maxSize);
extern int64_t (*original_qmlregister)(int64_t, int64_t, int64_t, int64_t, int64_t, int64_t, int, int64_t, int, int64_t);
extern int64_t (*original_function_at_0x100011790)(uint64_t *a1);
extern int64_t (*original_function_at_0x100011CE0)(int64_t, const QObject *, unsigned char, int64_t, QtSharedPointer::ExternalRefCountData *);
extern int64_t (*original_function_at_0x10015A130)(int64_t, int64_t);
extern void (*original_function_at_0x10015BC90)(int64_t, int64_t);
extern int64_t (*original_function_at_0x10016D520)(int64_t, int64_t *, unsigned int, int64_t);
extern void (*original_function_at_0x1001B6EE0)(int64_t, int64_t *, unsigned int);

#ifdef __cplusplus
extern "C" {
#endif

ssize_t hooked_qIODevice_write(QIODevice *self, const char *data, int64_t maxSize);
int64_t hooked_qmlregister(int64_t, int64_t, int64_t, int64_t, int64_t, int64_t, int, int64_t, int, int64_t);
int64_t hooked_function_at_0x100011790(uint64_t *a1);
int64_t hooked_function_at_0x100011CE0(int64_t, const QObject *, unsigned char, int64_t, QtSharedPointer::ExternalRefCountData *);
int64_t hooked_function_at_0x10015A130(int64_t, int64_t);
void hooked_function_at_0x10015BC90(int64_t, int64_t);
int64_t hooked_function_at_0x10016D520(int64_t, int64_t *, unsigned int, int64_t);
void hooked_function_at_0x1001B6EE0(int64_t, int64_t *, unsigned int);

#ifdef __cplusplus
}
#endif

void logMemory(const char *label, void *address, size_t length);
void logStackTrace(const char *label);

#endif // BUILD_MODE_DEV

#endif // DEV_HOOKS_H