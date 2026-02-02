#import "reMarkable.h"
#import <Foundation/Foundation.h>
#import "Constant.h"
#import "MemoryUtils.h"
#import "Logger.h"
#import "ResourceUtils.h"
#ifdef BUILD_MODE_DEV
#import "DevHooks.h"
#endif
#ifdef BUILD_MODE_QMLREBUILD
#import "MessageBroker.h"
#import "HttpServer.h"
#endif
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

#ifdef BUILD_MODE_QMLREBUILD
static int (*original_qRegisterResourceData)(
    int,
    const unsigned char *,
    const unsigned char *,
    const unsigned char *) = NULL;
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

#ifdef BUILD_MODE_QMLREBUILD
    NSLogger(@"[reMarkable] Build mode: qmlrebuild");
    
    // Register MessageBroker QML type for dylib <-> QML communication
    messagebroker::registerQmlType();
    
    // Register native callback to receive signals from QML
    messagebroker::setNativeCallback([](const char *signal, const char *value) {
        NSLogger(@"[reMarkable] Native callback received signal '%s' with value '%s'", signal, value);
    });
    
    // Start HTTP server for export requests
    if (httpserver::start(8080)) {
        NSLogger(@"[reMarkable] HTTP server started on http://localhost:8080");
    } else {
        NSLogger(@"[reMarkable] Failed to start HTTP server");
    }
    
    [MemoryUtils hookSymbol:@"QtCore"
                        symbolName:@"__Z21qRegisterResourceDataiPKhS0_S0_"
                      hookFunction:(void *)hooked_qRegisterResourceData
                  originalFunction:(void **)&original_qRegisterResourceData
                         logPrefix:@"[reMarkable]"];

    // Send a delayed broadcast to QML (after UI has loaded)
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        messagebroker::broadcast("signalName", "Hello from dylib!");
    });
#endif

#ifdef BUILD_MODE_DEV
    NSLogger(@"[reMarkable] Build mode: dev/reverse engineering");
    // [MemoryUtils hookSymbol:@"QtCore"
    //                 symbolName:@"__ZN9QIODevice5writeEPKcx"
    //               hookFunction:(void *)hooked_qIODevice_write
    //           originalFunction:(void **)&original_qIODevice_write
    //                  logPrefix:@"[reMarkable]"];

    // // Hook function at address 0x10015A130
    // [MemoryUtils hookAddress:@"reMarkable"
    //            staticAddress:0x10015A130
    //             hookFunction:(void *)hooked_function_at_0x10015A130
    //         originalFunction:(void **)&original_function_at_0x10015A130
    //                logPrefix:@"[reMarkable]"];

    // // Hook function at address 0x10015BC90
    // [MemoryUtils hookAddress:@"reMarkable"
    //            staticAddress:0x10015BC90
    //             hookFunction:(void *)hooked_function_at_0x10015BC90
    //         originalFunction:(void **)&original_function_at_0x10015BC90
    //                logPrefix:@"[reMarkable]"];

    // // Hook function at address 0x10016D520
    // [MemoryUtils hookAddress:@"reMarkable"
    //            staticAddress:0x10016D520
    //             hookFunction:(void *)hooked_function_at_0x10016D520
    //         originalFunction:(void **)&original_function_at_0x10016D520
    //                logPrefix:@"[reMarkable]"];

    // // Hook function at address 0x1001B6EE0
    // [MemoryUtils hookAddress:@"reMarkable"
    //            staticAddress:0x1001B6EE0
    //             hookFunction:(void *)hooked_function_at_0x1001B6EE0
    //         originalFunction:(void **)&original_function_at_0x1001B6EE0
    //                logPrefix:@"[reMarkable]"];

    // PlatformHelpers.exportFile implementation WIP

    // // Hook function at address 0x100011790
    // [MemoryUtils hookAddress:@"reMarkable"
    //            staticAddress:0x100011790
    //             hookFunction:(void *)hooked_function_at_0x100011790
    //         originalFunction:(void **)&original_function_at_0x100011790
    //                logPrefix:@"[reMarkable]"];

    // // Hook function at address 0x100011CE0
    // [MemoryUtils hookAddress:@"reMarkable"
    //            staticAddress:0x100011CE0
    //             hookFunction:(void *)hooked_function_at_0x100011CE0
    //         originalFunction:(void **)&original_function_at_0x100011CE0
    //                logPrefix:@"[reMarkable]"];

    // [MemoryUtils hookSymbol:@"QtQml"
    //                 symbolName:@"__ZN11QQmlPrivate11qmlregisterENS_16RegistrationTypeEPv"
    //               hookFunction:(void *)hooked_qmlregister
    //           originalFunction:(void **)&original_qmlregister
    //                  logPrefix:@"[reMarkable]"];

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

#ifdef BUILD_MODE_QMLREBUILD

// See https://deepwiki.com/search/once-the-qrr-file-parsed-take_871f24a0-8636-4aee-bddf-7405b6e32584 for details on qmlrebuild replacement strategy

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

    NSLogger(@"[reMarkable] Registering Qt resource version %d tree:%p name:%p data:%p",
             version, tree, name, data);

    statArchive(&resource, 0);
    
    // Make a writable copy of the tree (we need to modify offsets)
    resource.tree = (uint8_t *)malloc(resource.treeSize);
    if (!resource.tree) {
        NSLogger(@"[reMarkable] Failed to allocate tree buffer");
        pthread_mutex_unlock(&gResourceMutex);
        return original_qRegisterResourceData(version, tree, name, data);
    }
    memcpy(resource.tree, tree, resource.treeSize);

    // Process nodes and mark replacements
    processNode(&resource, 0, "");
    NSLogger(@"[reMarkable] Processing done! Entries affected: %d, dataSize: %zu, originalDataSize: %zu", 
             resource.entriesAffected, resource.dataSize, resource.originalDataSize);

    const unsigned char *finalTree = tree;
    const unsigned char *finalData = data;
    uint8_t *newDataBuffer = NULL;

    if (resource.entriesAffected > 0) {
        NSLogger(@"[reMarkable] Rebuilding data tables... (entries: %d)", resource.entriesAffected);
        
        // Allocate new data buffer (original size + space for replacements)
        newDataBuffer = (uint8_t *)malloc(resource.dataSize);
        if (!newDataBuffer) {
            NSLogger(@"[reMarkable] Failed to allocate new data buffer (%zu bytes)", resource.dataSize);
            free(resource.tree);
            clearReplacementEntries();
            pthread_mutex_unlock(&gResourceMutex);
            return original_qRegisterResourceData(version, tree, name, data);
        }
        
        // Copy original data
        memcpy(newDataBuffer, data, resource.originalDataSize);
        
        // Copy replacement entries to their designated offsets
        struct ReplacementEntry *entry = getReplacementEntries();
        while (entry) {
            // Write size prefix (4 bytes, big-endian)
            writeUint32(newDataBuffer, (int)entry->copyToOffset, (uint32_t)entry->size);
            // Write data after size prefix
            memcpy(newDataBuffer + entry->copyToOffset + 4, entry->data, entry->size);
            
            NSLogger(@"[reMarkable] Copied replacement for node %d at offset %zu (%zu bytes)", 
                     entry->node, entry->copyToOffset, entry->size);
            
            entry = entry->next;
        }
        
        finalTree = resource.tree;
        finalData = newDataBuffer;
        
        NSLogger(@"[reMarkable] Data buffer rebuilt: original %zu bytes -> new %zu bytes", 
                 resource.originalDataSize, resource.dataSize);
    }

    int status = original_qRegisterResourceData(version, finalTree, name, finalData);
    
    // Cleanup
    clearReplacementEntries();
    if (resource.tree && resource.entriesAffected == 0) {
        free(resource.tree);
    }
    // Note: We intentionally don't free newDataBuffer or resource.tree when entriesAffected > 0
    // because Qt will use these buffers for the lifetime of the application
    
    pthread_mutex_unlock(&gResourceMutex);
    return status;
}
#endif // BUILD_MODE_QMLREBUILD

@end