#import "Config.h"
#import "Logger.h"
#include <QtCore/QString>

static NSString *const kConfigFileName = @"rmfakecloud.config";
static NSString *const kConfigHostKey = @"host";
static NSString *const kConfigPortKey = @"port";
static NSString *const kConfigClientCertKey = @"client_cert";
static NSString *const kConfigClientKeyKey = @"client_key";
static NSString *const kConfigCACertKey = @"ca_cert";
static NSString *const kConfigKeyAlgorithmKey = @"key_algorithm";
static NSString *const kConfigDisableSSLVerifyKey = @"disable_ssl_verification";
static NSString *const kDefaultHost = @"example.com";
static NSNumber *const kDefaultPort = @(443);

NSString *gConfiguredHostObjC = @"example.com";
NSNumber *gConfiguredPortObjC = @(443);
QString gConfiguredHost = QString::fromUtf8("example.com");
NSNumber *gConfiguredPort = @(443);
QString gConfiguredClientCertPath;
QString gConfiguredClientKeyPath;
QString gConfiguredCACertPath;
QSsl::KeyAlgorithm gConfiguredKeyAlgorithm = QSsl::Rsa;
bool gDisableSSLVerification = false;

static NSString *PreferencesDirectory(void) {
    NSArray<NSString *> *libraryPaths = NSSearchPathForDirectoriesInDomains(NSLibraryDirectory, NSUserDomainMask, YES);
    NSString *libraryDir = [libraryPaths firstObject];
    if (![libraryDir length]) {
        libraryDir = [NSHomeDirectory() stringByAppendingPathComponent:@"Library"];
    }
    return [libraryDir stringByAppendingPathComponent:@"Preferences"];
}

NSString *ConfigFilePath(void) {
    return [PreferencesDirectory() stringByAppendingPathComponent:kConfigFileName];
}

static BOOL WriteConfig(NSString *path, NSDictionary<NSString *, id> *config) {
    NSError *error = nil;
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:config options:NSJSONWritingPrettyPrinted error:&error];
    if (!jsonData || error) {
        NSLogger(@"[RMHook] Failed to serialize config: %@", error);
        return NO;
    }
    if (![jsonData writeToFile:path atomically:YES]) {
        NSLogger(@"[RMHook] Failed to write config file at %@", path);
        return NO;
    }
    return YES;
}

static inline QString QStringFromNSStringSafe(NSString *string) {
    if (!string) {
        return QString();
    }
    return QString::fromUtf8([string UTF8String]);
}

void ConfigLoadOrCreate(void) {
    NSString *configPath = ConfigFilePath();
    NSString *directory = [configPath stringByDeletingLastPathComponent];
    NSFileManager *fileManager = [NSFileManager defaultManager];
    BOOL isDirectory = NO;
    NSError *error = nil;

    if (![fileManager fileExistsAtPath:directory isDirectory:&isDirectory] || !isDirectory) {
        if (![fileManager createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:&error]) {
            NSLogger(@"[RMHook] Failed to create config directory %@: %@", directory, error);
        }
    }

    NSDictionary<NSString *, id> *defaults = @{kConfigHostKey : kDefaultHost,
                                               kConfigPortKey : kDefaultPort};

    if ([fileManager fileExistsAtPath:configPath isDirectory:&isDirectory] && !isDirectory) {
        NSData *data = [NSData dataWithContentsOfFile:configPath];
        if ([data length] > 0) {
            NSError *jsonError = nil;
            id jsonObject = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];
            if (!jsonError && [jsonObject isKindOfClass:[NSDictionary class]]) {
                NSDictionary *configDict = (NSDictionary *)jsonObject;
                NSString *hostValue = configDict[kConfigHostKey];
                NSNumber *portValue = configDict[kConfigPortKey];

                NSString *resolvedHost = ([hostValue isKindOfClass:[NSString class]] && [hostValue length]) ? hostValue : kDefaultHost;
                NSInteger portCandidate = kDefaultPort.integerValue;
                if ([portValue respondsToSelector:@selector(integerValue)]) {
                    NSInteger candidate = [portValue integerValue];
                    if (candidate > 0 && candidate <= 65535) {
                        portCandidate = candidate;
                    } else {
                        NSLogger(@"[RMHook] Ignoring invalid port value %@, falling back to default.", portValue);
                    }
                }

                gConfiguredHostObjC = [resolvedHost copy];
                gConfiguredPortObjC = @(portCandidate);
                gConfiguredHost = QStringFromNSStringSafe(resolvedHost);
                gConfiguredPort = @(portCandidate);

                NSString *certPathValue = configDict[kConfigClientCertKey];
                NSString *keyPathValue = configDict[kConfigClientKeyKey];
                NSString *caPathValue = configDict[kConfigCACertKey];
                NSNumber *disableSSLValue = configDict[kConfigDisableSSLVerifyKey];

                if ([certPathValue isKindOfClass:[NSString class]] && [certPathValue length]) {
                    gConfiguredClientCertPath = QStringFromNSStringSafe(certPathValue);
                }
                if ([keyPathValue isKindOfClass:[NSString class]] && [keyPathValue length]) {
                    gConfiguredClientKeyPath = QStringFromNSStringSafe(keyPathValue);
                }
                if ([caPathValue isKindOfClass:[NSString class]] && [caPathValue length]) {
                    gConfiguredCACertPath = QStringFromNSStringSafe(caPathValue);
                }
                NSString *keyAlgoValue = configDict[kConfigKeyAlgorithmKey];
                if ([keyAlgoValue isKindOfClass:[NSString class]] && [keyAlgoValue length]) {
                    NSString *lower = [keyAlgoValue lowercaseString];
                    if ([lower isEqualToString:@"ec"]) {
                        gConfiguredKeyAlgorithm = QSsl::Ec;
                    } else if ([lower isEqualToString:@"dsa"]) {
                        gConfiguredKeyAlgorithm = QSsl::Dsa;
                    } else if ([lower isEqualToString:@"dh"]) {
                        gConfiguredKeyAlgorithm = QSsl::Dh;
                    } else if ([lower isEqualToString:@"opaque"]) {
                        gConfiguredKeyAlgorithm = QSsl::Opaque;
                    } else {
                        gConfiguredKeyAlgorithm = QSsl::Rsa;
                    }
                }
                if ([disableSSLValue respondsToSelector:@selector(boolValue)]) {
                    gDisableSSLVerification = [disableSSLValue boolValue];
                }

                NSLogger(@"[RMHook] Loaded config from %@ with host %@ and port %@", configPath, gConfiguredHostObjC, gConfiguredPortObjC);
                return;
            } else {
                NSLogger(@"[RMHook] Failed to parse config file %@: %@", configPath, jsonError);
            }
        } else {
            NSLogger(@"[RMHook] Config file %@ was empty, rewriting with defaults.", configPath);
        }
    }

    if (WriteConfig(configPath, defaults)) {
        NSLogger(@"[RMHook] Created default config at %@", configPath);
    }
    gConfiguredHostObjC = [kDefaultHost copy];
    gConfiguredPortObjC = kDefaultPort;
    gConfiguredHost = QString::fromUtf8("example.com");
    gConfiguredPort = kDefaultPort;
}
