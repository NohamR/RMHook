#import <Foundation/Foundation.h>
#include <QtCore/QString>
#include <QtNetwork/QSsl>

extern NSString *gConfiguredHostObjC;
extern NSNumber *gConfiguredPortObjC;
extern QString gConfiguredHost;
extern NSNumber *gConfiguredPort;
extern QString gConfiguredClientCertPath;
extern QString gConfiguredClientKeyPath;
extern QString gConfiguredCACertPath;
extern QSsl::KeyAlgorithm gConfiguredKeyAlgorithm;
extern bool gDisableSSLVerification;

void ConfigLoadOrCreate(void);
NSString *ConfigFilePath(void);
