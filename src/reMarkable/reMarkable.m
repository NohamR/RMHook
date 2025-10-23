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
    
    // Add custom Help menu entry to open config file
    NSString *configPath = ReMarkableConfigFilePath();
    NSString *fileURL = [NSString stringWithFormat:@"file://%@", configPath];
    [MenuActionController addCustomHelpMenuEntry:@"Open rmfakecloud config" 
                                         withURL:fileURL 
                                       withDelay:2.0];
}

@end

@implementation reMarkableDylib

static QNetworkReply *(*original_qNetworkAccessManager_createRequest)(
    QNetworkAccessManager *self,
    QNetworkAccessManager::Operation op,
    const QNetworkRequest &request,
    QIODevice *outgoingData) = NULL;

static void (*original_qWebSocket_open)(
    QWebSocket *self,
    const QNetworkRequest &request) = NULL;

static int (*original_qRegisterResourceData)(
    int,
    const unsigned char *,
    const unsigned char *,
    const unsigned char *) = NULL;

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

- (BOOL)hook {
    NSLogger(@"[reMarkable] Starting hooks...");

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

    // WIP: Implement resource data registration hooking
    // [MemoryUtils hookSymbol:@"QtCore"
    //                     symbolName:@"__Z21qRegisterResourceDataiPKhS0_S0_"
    //                   hookFunction:(void *)hooked_qRegisterResourceData
    //               originalFunction:(void **)&original_qRegisterResourceData
    //                      logPrefix:@"[reMarkable]"];

    return YES;
}

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

@end