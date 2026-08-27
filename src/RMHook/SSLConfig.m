#import "SSLConfig.h"
#import "Config.h"
#import "Logger.h"
#include <QtNetwork/QSslConfiguration>
#include <QtNetwork/QSslCertificate>
#include <QtNetwork/QSslKey>
#include <QtNetwork/QSslSocket>
#include <QtCore/QFile>
#include <QtCore/QIODevice>

static QSslCertificate gClientCert;
static QSslKey gClientKey;
static QSslCertificate gCACert;
static bool gSSLInitialized = false;

void SSLConfigLoad(void) {
    if (gSSLInitialized) return;

    if (!gConfiguredClientCertPath.isEmpty() && !gConfiguredClientKeyPath.isEmpty()) {
        QString certPath = gConfiguredClientCertPath;
        QString keyPath = gConfiguredClientKeyPath;

        QFile certFile(QString::fromUtf8(certPath.toUtf8()));
        if (certFile.open(QIODevice::ReadOnly)) {
            gClientCert = QSslCertificate(certFile.readAll(), QSsl::Pem);
            certFile.close();
            if (gClientCert.isNull()) {
                NSLogger(@"[RMHook] Failed to parse client certificate from %s", certPath.toUtf8().constData());
            } else {
                NSLogger(@"[RMHook] Loaded client certificate from %s", certPath.toUtf8().constData());
            }
        } else {
            NSLogger(@"[RMHook] Failed to open client certificate file %s", certPath.toUtf8().constData());
        }

        QFile keyFile(QString::fromUtf8(keyPath.toUtf8()));
        if (keyFile.open(QIODevice::ReadOnly)) {
            gClientKey = QSslKey(keyFile.readAll(), QSsl::Rsa, QSsl::Pem, QSsl::PrivateKey);
            keyFile.close();
            if (gClientKey.isNull()) {
                NSLogger(@"[RMHook] Failed to parse client key from %s", keyPath.toUtf8().constData());
            } else {
                NSLogger(@"[RMHook] Loaded client key from %s", keyPath.toUtf8().constData());
            }
        } else {
            NSLogger(@"[RMHook] Failed to open client key file %s", keyPath.toUtf8().constData());
        }
    }

    if (!gConfiguredCACertPath.isEmpty()) {
        QString caPath = gConfiguredCACertPath;
        QFile caFile(QString::fromUtf8(caPath.toUtf8()));
        if (caFile.open(QIODevice::ReadOnly)) {
            gCACert = QSslCertificate(caFile.readAll(), QSsl::Pem);
            caFile.close();
            if (gCACert.isNull()) {
                NSLogger(@"[RMHook] Failed to parse CA certificate from %s", caPath.toUtf8().constData());
            } else {
                NSLogger(@"[RMHook] Loaded CA certificate from %s", caPath.toUtf8().constData());
            }
        } else {
            NSLogger(@"[RMHook] Failed to open CA certificate file %s", caPath.toUtf8().constData());
        }
    }

    gSSLInitialized = true;
}

void SSLConfigApplyToRequest(QNetworkRequest &request) {
    if (!gSSLInitialized) return;

    QSslConfiguration sslConfig = QSslConfiguration::defaultConfiguration();

    if (!gClientCert.isNull() && !gClientKey.isNull()) {
        QList<QSslCertificate> localCerts = sslConfig.localCertificateChain();
        localCerts.append(gClientCert);
        sslConfig.setLocalCertificateChain(localCerts);
        sslConfig.setPrivateKey(gClientKey);
    }

    if (!gCACert.isNull()) {
        QList<QSslCertificate> caCerts = sslConfig.caCertificates();
        caCerts.append(gCACert);
        sslConfig.setCaCertificates(caCerts);
    }

    if (gDisableSSLVerification) {
        sslConfig.setPeerVerifyMode(QSslSocket::VerifyNone);
    }

    request.setSslConfiguration(sslConfig);
}
