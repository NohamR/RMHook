#import "RMHook.h"
#import <Foundation/Foundation.h>
#import "Constant.h"
#import "MemoryUtils.h"
#import "Logger.h"
#import "ResourceUtils.h"
#import "Config.h"
#import "SSLConfig.h"
#ifdef BUILD_MODE_DEV
#import "DevHooks.h"
#endif
#ifdef BUILD_MODE_QMLREBUILD
#import "MessageBroker.h"
#endif
#import <objc/runtime.h>
#import <Cocoa/Cocoa.h>
#include <stdint.h>
#include <limits.h>
#include <pthread.h>
#include <stdlib.h>
#include <string.h>
#include <dispatch/dispatch.h>
#include <string>

#include <QtNetwork/QNetworkAccessManager>
#include <QtNetwork/QNetworkRequest>
#include <QtNetwork/QNetworkReply>
#include <QtCore/QDebug>
#include <QtCore/QIODevice>
#include <QtCore/QUrl>
#include <QtCore/QString>
#include <QtCore/Qt>
#include <QtWebSockets/QWebSocket>

static pthread_mutex_t gResourceMutex = PTHREAD_MUTEX_INITIALIZER;

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

@interface RMHookDylib : NSObject

- (BOOL)hook;

@end

@implementation RMHook

+ (void)load {
    NSLogger(@"RMHook dylib loaded successfully");
    
    RMHookDylib *dylib = [[RMHookDylib alloc] init];
    [dylib hook];
    
#ifdef BUILD_MODE_RMFAKECLOUD
    NSString *configPath = ConfigFilePath();
    NSString *fileURL = [NSString stringWithFormat:@"file://%@", configPath];
    [MenuActionController addCustomHelpMenuEntry:@"Open rmfakecloud config" 
                                         withURL:fileURL 
                                       withDelay:2.0];
#endif
}

@end

@implementation RMHookDylib

#ifdef BUILD_MODE_RMFAKECLOUD
static QNetworkReply *(*original_qNetworkAccessManager_createRequest)(
    QNetworkAccessManager *self,
    QNetworkAccessManager::Operation op,
    const QNetworkRequest &request,
    QIODevice *outgoingData) = NULL;

static void (*original_qWebSocket_open)(
    QWebSocket *self,
    const QNetworkRequest &request) = NULL;

typedef void* MQTTAsync;
typedef void* MQTTAsync_createOptions;

static int (*original_MQTTAsync_createWithOptions)(
    MQTTAsync *handle,
    const char *serverURI,
    const char *clientId,
    int persistence_type,
    void *persistence_context,
    MQTTAsync_createOptions *options) = NULL;
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

static inline QString QStringFromNSStringSafe(NSString *string) {
    if (!string) {
        return QString();
    }
    return QString::fromUtf8([string UTF8String]);
}

- (BOOL)hook {
    NSLogger(@"[RMHook] Starting hooks...");

#ifdef BUILD_MODE_RMFAKECLOUD
    NSLogger(@"[RMHook] Build mode: rmfakecloud");
    ConfigLoadOrCreate();
    SSLConfigLoad();
    NSLogger(@"[RMHook] Using override host %@ and port %@", gConfiguredHostObjC, gConfiguredPortObjC);

    [MemoryUtils hookSymbol:@"QtNetwork"
                        symbolName:@"__ZN21QNetworkAccessManager13createRequestENS_9OperationERK15QNetworkRequestP9QIODevice"
                      hookFunction:(void *)hooked_qNetworkAccessManager_createRequest
                  originalFunction:(void **)&original_qNetworkAccessManager_createRequest
                         logPrefix:@"[RMHook]"];

    [MemoryUtils hookSymbol:@"QtWebSockets"
                        symbolName:@"__ZN10QWebSocket4openERK15QNetworkRequest"
                      hookFunction:(void *)hooked_qWebSocket_open
                  originalFunction:(void **)&original_qWebSocket_open
                         logPrefix:@"[RMHook]"];

    [MemoryUtils hookSymbol:@"libpaho-mqtt3as.1.dylib"
                        symbolName:@"_MQTTAsync_createWithOptions"
                      hookFunction:(void *)hooked_MQTTAsync_createWithOptions
                  originalFunction:(void **)&original_MQTTAsync_createWithOptions
                         logPrefix:@"[RMHook]"];
#endif

#ifdef BUILD_MODE_QMLREBUILD
    NSLogger(@"[RMHook] Build mode: qmlrebuild");
    
    messagebroker::registerQmlType();
    
    messagebroker::setNativeCallback([](const char *signal, const char *value) {
        NSLogger(@"[RMHook] Native callback received signal '%s' with value '%s'", signal, value);
    });
    
    [MemoryUtils hookSymbol:@"QtCore"
                        symbolName:@"__Z21qRegisterResourceDataiPKhS0_S0_"
                      hookFunction:(void *)hooked_qRegisterResourceData
                  originalFunction:(void **)&original_qRegisterResourceData
                         logPrefix:@"[RMHook]"];

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        messagebroker::broadcast("signalName", "Hello from dylib!");
    });
#endif

#ifdef BUILD_MODE_DEV
    NSLogger(@"[RMHook] Build mode: dev/reverse engineering");
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
        QNetworkRequest newReq(req);
        QUrl newUrl = req.url();
        const QString overrideHost = QStringFromNSStringSafe(gConfiguredHostObjC);
        newUrl.setHost(overrideHost);
        newUrl.setPort([gConfiguredPortObjC intValue]);
        newReq.setUrl(newUrl);

        SSLConfigApplyToRequest(newReq);

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
        const QString overrideHost = QStringFromNSStringSafe(gConfiguredHostObjC);
        newUrl.setHost(overrideHost);
        newUrl.setPort([gConfiguredPortObjC intValue]);

        QNetworkRequest newReq(req);
        newReq.setUrl(newUrl);

        SSLConfigApplyToRequest(newReq);

        original_qWebSocket_open(self, newReq);
        return;
    }

    original_qWebSocket_open(self, req);
}

static std::string PatchMqttUri(const char* uri)
{
    if (!uri) return {};
    const std::string original(uri);

    size_t schemeEnd = original.find("://");
    size_t hostStart = (schemeEnd != std::string::npos) ? schemeEnd + 3 : 0;
    size_t hostEnd   = original.find_first_of(":/", hostStart);
    if (hostEnd == std::string::npos) hostEnd = original.size();

    const std::string origHost = original.substr(hostStart, hostEnd - hostStart);

    static const char* kSuffixes[] = {
        ".remarkable.com",
        ".remarkable.engineering",
        nullptr
    };
    bool shouldPatch = false;
    for (int i = 0; kSuffixes[i]; ++i)
    {
        const std::string suffix(kSuffixes[i]);
        if (origHost.size() >= suffix.size() &&
            origHost.compare(origHost.size() - suffix.size(),
                             suffix.size(), suffix) == 0)
        {
            shouldPatch = true;
            break;
        }
    }
    if (!shouldPatch) return {};

    std::string patched = original;
    std::string proxyHost = [gConfiguredHostObjC UTF8String];
    patched.replace(hostStart, hostEnd - hostStart, proxyHost);

    size_t colonPos = patched.find(':', hostStart + proxyHost.size());
    if (colonPos != std::string::npos)
    {
        size_t numEnd = patched.find_first_not_of("0123456789", colonPos + 1);
        if (numEnd == std::string::npos) numEnd = patched.size();
        patched.replace(colonPos + 1, numEnd - colonPos - 1,
                        std::to_string([gConfiguredPortObjC intValue]));
    }
    return patched;
}

extern "C" int hooked_MQTTAsync_createWithOptions(
    MQTTAsync *handle,
    const char *serverURI,
    const char *clientId,
    int persistence_type,
    void *persistence_context,
    MQTTAsync_createOptions *options)
{
    if (!original_MQTTAsync_createWithOptions) {
        return -1;
    }

    std::string patchedUri = PatchMqttUri(serverURI);
    if (!patchedUri.empty()) {
        NSLogger(@"[RMHook] Patching MQTT URI from %s to %s", serverURI, patchedUri.c_str());
        return original_MQTTAsync_createWithOptions(handle, patchedUri.c_str(), clientId, persistence_type, persistence_context, options);
    }

    return original_MQTTAsync_createWithOptions(handle, serverURI, clientId, persistence_type, persistence_context, options);
}
#endif // BUILD_MODE_RMFAKECLOUD

#ifdef BUILD_MODE_QMLREBUILD

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

    NSLogger(@"[RMHook] Registering Qt resource version %d tree:%p name:%p data:%p",
             version, tree, name, data);

    statArchive(&resource, 0);
    
    resource.tree = (uint8_t *)malloc(resource.treeSize);
    if (!resource.tree) {
        NSLogger(@"[RMHook] Failed to allocate tree buffer");
        pthread_mutex_unlock(&gResourceMutex);
        return original_qRegisterResourceData(version, tree, name, data);
    }
    memcpy(resource.tree, tree, resource.treeSize);

    processNode(&resource, 0, "");
    NSLogger(@"[RMHook] Processing done! Entries affected: %d, dataSize: %zu, originalDataSize: %zu", 
             resource.entriesAffected, resource.dataSize, resource.originalDataSize);

    const unsigned char *finalTree = tree;
    const unsigned char *finalData = data;
    uint8_t *newDataBuffer = NULL;

    if (resource.entriesAffected > 0) {
        NSLogger(@"[RMHook] Rebuilding data tables... (entries: %d)", resource.entriesAffected);
        
        newDataBuffer = (uint8_t *)malloc(resource.dataSize);
        if (!newDataBuffer) {
            NSLogger(@"[RMHook] Failed to allocate new data buffer (%zu bytes)", resource.dataSize);
            free(resource.tree);
            clearReplacementEntries();
            pthread_mutex_unlock(&gResourceMutex);
            return original_qRegisterResourceData(version, tree, name, data);
        }
        
        memcpy(newDataBuffer, data, resource.originalDataSize);
        
        struct ReplacementEntry *entry = getReplacementEntries();
        while (entry) {
            writeUint32(newDataBuffer, (int)entry->copyToOffset, (uint32_t)entry->size);
            memcpy(newDataBuffer + entry->copyToOffset + 4, entry->data, entry->size);
            
            NSLogger(@"[RMHook] Copied replacement for node %d at offset %zu (%zu bytes)", 
                     entry->node, entry->copyToOffset, entry->size);
            
            entry = entry->next;
        }
        
        finalTree = resource.tree;
        finalData = newDataBuffer;
        
        NSLogger(@"[RMHook] Data buffer rebuilt: original %zu bytes -> new %zu bytes", 
                 resource.originalDataSize, resource.dataSize);
    }

    int status = original_qRegisterResourceData(version, finalTree, name, finalData);
    
    clearReplacementEntries();
    if (resource.tree && resource.entriesAffected == 0) {
        free(resource.tree);
    }
    
    pthread_mutex_unlock(&gResourceMutex);
    return status;
}
#endif // BUILD_MODE_QMLREBUILD

@end
