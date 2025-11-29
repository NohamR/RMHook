#import "reMarkable.h"
#import <Foundation/Foundation.h>
#import "Constant.h"
#import "MemoryUtils.h"
#import "Logger.h"
#import "ResourceUtils.h"
#import <objc/runtime.h>
#import <Cocoa/Cocoa.h>
#include <stdint.h>
#include <limits.h>
#include <pthread.h>
#include <stdlib.h>
#include <string.h>
#include <dispatch/dispatch.h>

#include <QtNetwork/QNetworkAccessManager>
#include <QtNetwork/QNetworkRequest>
#include <QtNetwork/QNetworkReply>
#include <QtCore/QDebug>
#include <QtCore/QIODevice>
#include <QtCore/QUrl>
#include <QtCore/QString>
#include <QtCore/Qt>
#include <QtWebSockets/QWebSocket>
#include <QtCore/QSettings>
#include <QtCore/QVariant>
#include <QtCore/QAnyStringView>

static NSString *const kReMarkableConfigFileName = @"rmfakecloud.config";
static NSString *const kReMarkableConfigHostKey = @"host";
static NSString *const kReMarkableConfigPortKey = @"port";
static NSString *const kReMarkableDefaultHost = @"example.com";
static NSNumber *const kReMarkableDefaultPort = @(443);

static NSString *gConfiguredHost = @"example.com";
static NSNumber *gConfiguredPort = @(443);
static pthread_mutex_t gResourceMutex = PTHREAD_MUTEX_INITIALIZER;

static NSString *ReMarkablePreferencesDirectory(void);

static NSString *ReMarkablePreferencesDirectory(void) {
    NSArray<NSString *> *libraryPaths = NSSearchPathForDirectoriesInDomains(NSLibraryDirectory, NSUserDomainMask, YES);
    NSString *libraryDir = [libraryPaths firstObject];
    if (![libraryDir length]) {
        libraryDir = [NSHomeDirectory() stringByAppendingPathComponent:@"Library"];
    }
    return [libraryDir stringByAppendingPathComponent:@"Preferences"];
}

static NSString *ReMarkableConfigFilePath(void) {
    return [ReMarkablePreferencesDirectory() stringByAppendingPathComponent:kReMarkableConfigFileName];
}

static BOOL ReMarkableWriteConfig(NSString *path, NSDictionary<NSString *, id> *config) {
    NSError *error = nil;
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:config options:NSJSONWritingPrettyPrinted error:&error];
    if (!jsonData || error) {
        NSLogger(@"[reMarkable] Failed to serialize config: %@", error);
        return NO;
    }
    if (![jsonData writeToFile:path atomically:YES]) {
        NSLogger(@"[reMarkable] Failed to write config file at %@", path);
        return NO;
    }
    return YES;
}

static void ReMarkableLoadOrCreateConfig(void) {
    NSString *configPath = ReMarkableConfigFilePath();
    NSString *directory = [configPath stringByDeletingLastPathComponent];
    NSFileManager *fileManager = [NSFileManager defaultManager];
    BOOL isDirectory = NO;
    NSError *error = nil;

    if (![fileManager fileExistsAtPath:directory isDirectory:&isDirectory] || !isDirectory) {
        if (![fileManager createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:&error]) {
            NSLogger(@"[reMarkable] Failed to create config directory %@: %@", directory, error);
        }
    }

    NSDictionary<NSString *, id> *defaults = @{kReMarkableConfigHostKey : kReMarkableDefaultHost,
                                               kReMarkableConfigPortKey : kReMarkableDefaultPort};

    if ([fileManager fileExistsAtPath:configPath isDirectory:&isDirectory] && !isDirectory) {
        NSData *data = [NSData dataWithContentsOfFile:configPath];
        if ([data length] > 0) {
            NSError *jsonError = nil;
            id jsonObject = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];
            if (!jsonError && [jsonObject isKindOfClass:[NSDictionary class]]) {
                NSDictionary *configDict = (NSDictionary *)jsonObject;
                NSString *hostValue = configDict[kReMarkableConfigHostKey];
                NSNumber *portValue = configDict[kReMarkableConfigPortKey];

                NSString *resolvedHost = ([hostValue isKindOfClass:[NSString class]] && [hostValue length]) ? hostValue : kReMarkableDefaultHost;
                NSInteger portCandidate = kReMarkableDefaultPort.integerValue;
                if ([portValue respondsToSelector:@selector(integerValue)]) {
                    NSInteger candidate = [portValue integerValue];
                    if (candidate > 0 && candidate <= 65535) {
                        portCandidate = candidate;
                    } else {
                        NSLogger(@"[reMarkable] Ignoring invalid port value %@, falling back to default.", portValue);
                    }
                }

                gConfiguredHost = [resolvedHost copy];
                gConfiguredPort = @(portCandidate);
                NSLogger(@"[reMarkable] Loaded config from %@ with host %@ and port %@", configPath, gConfiguredHost, gConfiguredPort);
                return;
            } else {
                NSLogger(@"[reMarkable] Failed to parse config file %@: %@", configPath, jsonError);
            }
        } else {
            NSLogger(@"[reMarkable] Config file %@ was empty, rewriting with defaults.", configPath);
        }
    }

    if (ReMarkableWriteConfig(configPath, defaults)) {
        NSLogger(@"[reMarkable] Created default config at %@", configPath);
    }
    gConfiguredHost = [kReMarkableDefaultHost copy];
    gConfiguredPort = kReMarkableDefaultPort;
}

static inline QString QStringFromNSStringSafe(NSString *string) {
    if (!string) {
        return QString();
    }
    return QString::fromUtf8([string UTF8String]);
}

@interface MenuActionController : NSObject
@property (strong, nonatomic) NSURL *targetURL;
- (void)openURLAction:(id)sender;
+ (void)addCustomHelpMenuEntry:(NSString *)title withURL:(NSString *)url;
+ (void)addCustomHelpMenuEntry:(NSString *)title withURL:(NSString *)url withDelay:(NSTimeInterval)delay;
@end

@implementation MenuActionController

- (void)openURLAction:(id)sender {
    if (self.targetURL) {
        [[NSWorkspace sharedWorkspace] openURL:self.targetURL];
        NSLogger(@"[+] URL opened successfully: %@", self.targetURL);
    }
}

+ (void)addCustomHelpMenuEntry:(NSString *)title withURL:(NSString *)url {
    [self addCustomHelpMenuEntry:title withURL:url withDelay:1.0];
}

+ (void)addCustomHelpMenuEntry:(NSString *)title withURL:(NSString *)url withDelay:(NSTimeInterval)delay {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        MenuActionController *controller = [[MenuActionController alloc] init];
        controller.targetURL = [NSURL URLWithString:url];
        
        NSMenu *mainMenu = [NSApp mainMenu];
        if (!mainMenu) {
            NSLogger(@"[-] Main menu not found");
            return;
        }
        
        NSMenuItem *helpMenuItem = nil;
        for (NSMenuItem *item in [mainMenu itemArray]) {
            if ([[item title] isEqualToString:@"Help"]) {
                helpMenuItem = item;
                break;
            }
        }
        
        if (!helpMenuItem) {
            NSLogger(@"[-] Help menu item not found");
            return;
        }
        
        NSMenu *helpMenu = [helpMenuItem submenu];
        if (!helpMenu) {
            NSLogger(@"[-] Help submenu not found");
            return;
        }
        
        if ([helpMenu numberOfItems] > 0) {
            [helpMenu addItem:[NSMenuItem separatorItem]];
        }
        
        NSMenuItem *customMenuItem = [[NSMenuItem alloc] initWithTitle:title 
                                                              action:@selector(openURLAction:) 
                                                       keyEquivalent:@""];
        [customMenuItem setTarget:controller];
        [helpMenu addItem:customMenuItem];
        
        objc_setAssociatedObject(helpMenu, 
                                [title UTF8String], 
                                controller, 
                                OBJC_ASSOCIATION_RETAIN);
        
        NSLogger(@"[+] Custom menu item '%@' added successfully", title);
    });
}

@end

@interface reMarkableDylib : NSObject

- (BOOL)hook;

@end

@implementation reMarkable

+ (void)load {
    NSLogger(@"reMarkable dylib loaded successfully");
    
    // Initialize the hook
    reMarkableDylib *dylib = [[reMarkableDylib alloc] init];
    [dylib hook];
    
#ifdef BUILD_MODE_RMFAKECLOUD
    // Add custom Help menu entry to open config file
    NSString *configPath = ReMarkableConfigFilePath();
    NSString *fileURL = [NSString stringWithFormat:@"file://%@", configPath];
    [MenuActionController addCustomHelpMenuEntry:@"Open rmfakecloud config" 
                                         withURL:fileURL 
                                       withDelay:2.0];
#endif
}

@end

@implementation reMarkableDylib

#ifdef BUILD_MODE_RMFAKECLOUD
static QNetworkReply *(*original_qNetworkAccessManager_createRequest)(
    QNetworkAccessManager *self,
    QNetworkAccessManager::Operation op,
    const QNetworkRequest &request,
    QIODevice *outgoingData) = NULL;

static void (*original_qWebSocket_open)(
    QWebSocket *self,
    const QNetworkRequest &request) = NULL;
#endif

#ifdef BUILD_MODE_QMLDIFF
static int (*original_qRegisterResourceData)(
    int,
    const unsigned char *,
    const unsigned char *,
    const unsigned char *) = NULL;
#endif

#ifdef BUILD_MODE_DEV
static ssize_t (*original_qIODevice_write)(
    QIODevice *self,
    const char *data,
    qint64 maxSize) = NULL;

// Hook for function at 0x10016D520
static int64_t (*original_function_at_0x10016D520)(int64_t a1, int64_t *a2, unsigned int a3, int64_t a4) = NULL;

// Hook for function at 0x1001B6EE0
static void (*original_function_at_0x1001B6EE0)(int64_t a1, int64_t *a2, unsigned int a3) = NULL;
#endif

#if defined(BUILD_MODE_DEV)
// Memory logging helper function
static void logMemory(const char *label, void *address, size_t length) {
    if (!address) {
        NSLogger(@"[reMarkable]   %s: (null)", label);
        return;
    }
    
    unsigned char *ptr = (unsigned char *)address;
    NSMutableString *hexLine = [NSMutableString stringWithFormat:@"[reMarkable]   %s: ", label];
    
    for (size_t i = 0; i < length; i++) {
        [hexLine appendFormat:@"%02x ", ptr[i]];
        if ((i + 1) % 16 == 0 && i < length - 1) {
            NSLogger(@"%@", hexLine);
            hexLine = [NSMutableString stringWithString:@"[reMarkable]                    "];
        }
    }
    
    // Log remaining bytes if any
    if ([hexLine length] > 28) {  // More than just the prefix
        NSLogger(@"%@", hexLine);
    }
}

// Stack trace logging helper function
static void logStackTrace(const char *label) {
    NSLogger(@"[reMarkable] %s - Stack trace:", label);
    NSArray<NSString *> *callStack = [NSThread callStackSymbols];
    NSUInteger count = [callStack count];
    
    // Skip first 2 frames (this function and the immediate caller's logging statement)
    for (NSUInteger i = 0; i < count; i++) {
        NSString *frame = callStack[i];
        NSLogger(@"[reMarkable]   #%lu: %@", (unsigned long)i, frame);
    }
}
#endif

#ifdef BUILD_MODE_RMFAKECLOUD
static inline bool shouldPatchURL(const QString &host) {
    if (host.isEmpty()) {
        return false;
    }

    return QString(R"""(
        hwr-production-dot-remarkable-production.appspot.com
        service-manager-production-dot-remarkable-production.appspot.com
        local.appspot.com
        my.remarkable.com
        ping.remarkable.com
        internal.cloud.remarkable.com
        eu.tectonic.remarkable.com
        backtrace-proxy.cloud.remarkable.engineering
        dev.ping.remarkable.com
        dev.tectonic.remarkable.com
        dev.internal.cloud.remarkable.com
        eu.internal.tctn.cloud.remarkable.com
        webapp-prod.cloud.remarkable.engineering
    )""")
        .contains(host, Qt::CaseInsensitive);
}
#endif

- (BOOL)hook {
    NSLogger(@"[reMarkable] Starting hooks...");

#ifdef BUILD_MODE_RMFAKECLOUD
    NSLogger(@"[reMarkable] Build mode: rmfakecloud");
    ReMarkableLoadOrCreateConfig();
    NSLogger(@"[reMarkable] Using override host %@ and port %@", gConfiguredHost, gConfiguredPort);

    [MemoryUtils hookSymbol:@"QtNetwork"
                        symbolName:@"__ZN21QNetworkAccessManager13createRequestENS_9OperationERK15QNetworkRequestP9QIODevice"
                      hookFunction:(void *)hooked_qNetworkAccessManager_createRequest
                  originalFunction:(void **)&original_qNetworkAccessManager_createRequest
                         logPrefix:@"[reMarkable]"];

    [MemoryUtils hookSymbol:@"QtWebSockets"
                        symbolName:@"__ZN10QWebSocket4openERK15QNetworkRequest"
                      hookFunction:(void *)hooked_qWebSocket_open
                  originalFunction:(void **)&original_qWebSocket_open
                         logPrefix:@"[reMarkable]"];
#endif

#ifdef BUILD_MODE_QMLDIFF
    NSLogger(@"[reMarkable] Build mode: qmldiff");
    [MemoryUtils hookSymbol:@"QtCore"
                        symbolName:@"__Z21qRegisterResourceDataiPKhS0_S0_"
                      hookFunction:(void *)hooked_qRegisterResourceData
                  originalFunction:(void **)&original_qRegisterResourceData
                         logPrefix:@"[reMarkable]"];
#endif

#ifdef BUILD_MODE_DEV
    NSLogger(@"[reMarkable] Build mode: dev/reverse engineering");
    [MemoryUtils hookSymbol:@"QtCore"
                    symbolName:@"__ZN9QIODevice5writeEPKcx"
                  hookFunction:(void *)hooked_qIODevice_write
              originalFunction:(void **)&original_qIODevice_write
                     logPrefix:@"[reMarkable]"];

    // Hook function at address 0x10016D520
    [MemoryUtils hookAddress:@"reMarkable"
               staticAddress:0x10016D520
                hookFunction:(void *)hooked_function_at_0x10016D520
            originalFunction:(void **)&original_function_at_0x10016D520
                   logPrefix:@"[reMarkable]"];

    // Hook function at address 0x1001B6EE0
    [MemoryUtils hookAddress:@"reMarkable"
               staticAddress:0x1001B6EE0
                hookFunction:(void *)hooked_function_at_0x1001B6EE0
            originalFunction:(void **)&original_function_at_0x1001B6EE0
                   logPrefix:@"[reMarkable]"];
#endif

    return YES;
}

#ifdef BUILD_MODE_RMFAKECLOUD
extern "C" QNetworkReply* hooked_qNetworkAccessManager_createRequest(
    QNetworkAccessManager* self,
    QNetworkAccessManager::Operation op,
    const QNetworkRequest& req,
    QIODevice* outgoingData
) {
    const QString host = req.url().host();
    if (shouldPatchURL(host)) {
        // Clone request to keep original immutable
        QNetworkRequest newReq(req);
        QUrl newUrl = req.url();
        const QString overrideHost = QStringFromNSStringSafe(gConfiguredHost);
        newUrl.setHost(overrideHost);
        newUrl.setPort([gConfiguredPort intValue]);
        newReq.setUrl(newUrl);

        if (original_qNetworkAccessManager_createRequest) {
            return original_qNetworkAccessManager_createRequest(self, op, newReq, outgoingData);
        }
        return nullptr;
    }

    if (original_qNetworkAccessManager_createRequest) {
        return original_qNetworkAccessManager_createRequest(self, op, req, outgoingData);
    }
    return nullptr;
}

extern "C" void hooked_qWebSocket_open(
    QWebSocket* self,
    const QNetworkRequest& req
) {
    if (!original_qWebSocket_open) {
        return;
    }

    const QString host = req.url().host();
    if (shouldPatchURL(host)) {
        QUrl newUrl = req.url();
        const QString overrideHost = QStringFromNSStringSafe(gConfiguredHost);
        newUrl.setHost(overrideHost);
        newUrl.setPort([gConfiguredPort intValue]);

        QNetworkRequest newReq(req);
        newReq.setUrl(newUrl);

        original_qWebSocket_open(self, newReq);
        return;
    }

    original_qWebSocket_open(self, req);
}
#endif // BUILD_MODE_RMFAKECLOUD

#ifdef BUILD_MODE_QMLDIFF
extern "C" int hooked_qRegisterResourceData(
    int version,
    const unsigned char *tree,
    const unsigned char *name,
    const unsigned char *data
) {
    if (!original_qRegisterResourceData) {
        return 0;
    }

    pthread_mutex_lock(&gResourceMutex);

    struct ResourceRoot resource = {
        .data = (uint8_t *)data,
        .name = (uint8_t *)name,
        .tree = (uint8_t *)tree,
        .treeSize = 0,
        .dataSize = 0,
        .originalDataSize = 0,
        .nameSize = 0,
        .entriesAffected = 0,
    };

    statArchive(&resource, 0);
    processNode(&resource, 0, "");
    resource.tree = (uint8_t *)malloc(resource.treeSize);
    if (resource.tree) {
        memcpy(resource.tree, tree, resource.treeSize);
    }

    NSLogger(@"[reMarkable] Registering Qt resource version %d tree:%p (size:%zu) name:%p (size:%zu) data:%p (size:%zu)",
             version, tree, resource.treeSize, name, resource.nameSize, data, resource.dataSize);

    int status = original_qRegisterResourceData(version, tree, name, data);
    pthread_mutex_unlock(&gResourceMutex);
    if (resource.tree) {
        free(resource.tree);
    }
    return status;
}
#endif // BUILD_MODE_QMLDIFF

#ifdef BUILD_MODE_DEV
extern "C" ssize_t hooked_qIODevice_write(
    QIODevice *self,
    const char *data,
    qint64 maxSize) {
    NSLogger(@"[reMarkable] QIODevice::write called with maxSize: %lld", (long long)maxSize);
    
    // Log the call stack
    logStackTrace("QIODevice::write call stack");
    
    // Log the data to write
    logMemory("Data to write", (void *)data, (size_t)(maxSize < 64 ? maxSize : 64));
    
    if (original_qIODevice_write) {
        ssize_t result = original_qIODevice_write(self, data, maxSize);
        NSLogger(@"[reMarkable] QIODevice::write result: %zd", result);
        return result;
    }
    NSLogger(@"[reMarkable] WARNING: Original QIODevice::write not available, returning 0");
    return 0;
}

extern "C" int64_t hooked_function_at_0x10016D520(int64_t a1, int64_t *a2, unsigned int a3, int64_t a4) {
    NSLogger(@"[reMarkable] Hook at 0x10016D520 called!");
    NSLogger(@"[reMarkable]   a1 = 0x%llx", (unsigned long long)a1);
    NSLogger(@"[reMarkable]   a2 = %p", a2);
    if (a2) {
        NSLogger(@"[reMarkable]   *a2 = 0x%llx", (unsigned long long)*a2);
    }
    NSLogger(@"[reMarkable]   a3 = %u (0x%x)", a3, a3);
    NSLogger(@"[reMarkable]   a4 = 0x%llx", (unsigned long long)a4);
    
    // Log memory contents using helper function
    logMemory("Memory at a1", (void *)a1, 64);
    logMemory("Memory at a2", (void *)a2, 64);
    
    if (a2 && *a2 != 0) {
        logMemory("Memory at *a2", (void *)*a2, 64);
    }
    
    logMemory("Memory at a4", (void *)a4, 64);
    
    if (original_function_at_0x10016D520) {
        int64_t result = original_function_at_0x10016D520(a1, a2, a3, a4);
        NSLogger(@"[reMarkable]   result = 0x%llx", (unsigned long long)result);
        return result;
    }
    
    NSLogger(@"[reMarkable] WARNING: Original function not available, returning 0");
    return 0;
}

extern "C" void hooked_function_at_0x1001B6EE0(int64_t a1, int64_t *a2, unsigned int a3) {
    NSLogger(@"[reMarkable] Hook at 0x1001B6EE0 called!");
    NSLogger(@"[reMarkable]   a1 = 0x%llx", (unsigned long long)a1);
    
    // At a1 (PdfExporter object at 0x7ff4c17391e0):
    // +0x10   0x000600043EC10    QString (likely document name)
    NSLogger(@"[reMarkable] Reading QString at a1+0x10:");
    logMemory("a1 + 0x10 (raw)", (void *)(a1 + 0x10), 64);

    void **qstrPtr = (void **)(a1 + 0x10);
    void *dataPtr = *qstrPtr;

    if (!dataPtr) {
        NSLogger(@"[reMarkable] QString has null data pointer");
        return;
    }

    // try reading potential size fields near dataPtr
    int32_t size = 0;
    for (int delta = 4; delta <= 32; delta += 4) {
        int32_t candidate = *(int32_t *)((char *)dataPtr - delta);
        if (candidate > 0 && candidate < 10000) {
            size = candidate;
            NSLogger(@"[reMarkable] QString plausible size=%d (found at -%d)", size, delta);
            break;
        }
    }

    if (size > 0) {
        NSString *qstringValue = [[NSString alloc] initWithCharacters:(unichar *)dataPtr length:size];
        NSLogger(@"[reMarkable] QString value: \"%@\"", qstringValue);
    } else {
        NSLogger(@"[reMarkable] QString: could not find valid size");
    }
    
    NSLogger(@"[reMarkable]   a2 = %p", a2);
    if (a2) {
        NSLogger(@"[reMarkable]   *a2 = 0x%llx", (unsigned long long)*a2);
    }
    NSLogger(@"[reMarkable]   a3 = %u (0x%x)", a3, a3);
    
    if (original_function_at_0x1001B6EE0) {
        original_function_at_0x1001B6EE0(a1, a2, a3);
        NSLogger(@"[reMarkable] Original function at 0x1001B6EE0 executed");
    } else {
        NSLogger(@"[reMarkable] WARNING: Original function not available");
    }
}
#endif // BUILD_MODE_DEV

@end