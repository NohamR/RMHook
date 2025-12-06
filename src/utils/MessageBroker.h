// Credits: asivery/rm-xovi-extensions 
// (https://github.com/asivery/rm-xovi-extensions/blob/master/xovi-message-broker/src/XoviMessageBroker.h)
// Simplified for RMHook dylib <-> QML communication

#pragma once

#include <QObject>
#include <QStringList>
#include <QString>
#include <QDebug>
#include <QtQml/QQmlEngine>

// Forward declaration
class MessageBroker;

// Native callback type for C++ listeners
typedef void (*NativeSignalCallback)(const char *signal, const char *value);

namespace messagebroker {
    void addBroadcastListener(MessageBroker *ref);
    void removeBroadcastListener(MessageBroker *ref);
    void broadcast(const char *signal, const char *value);
    void registerQmlType();
    
    // Register a native C++ callback to receive all signals
    void setNativeCallback(NativeSignalCallback callback);
}

class MessageBroker : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QStringList listeningFor READ getListeningFor WRITE setListeningFor)

public:
    explicit MessageBroker(QObject *parent = nullptr) : QObject(parent) {
        messagebroker::addBroadcastListener(this);
    }

    ~MessageBroker() {
        messagebroker::removeBroadcastListener(this);
    }

    // Send a signal from QML to all listeners (including C++ side)
    Q_INVOKABLE void sendSignal(const QString &signal, const QString &message) {
        QByteArray signalUtf8 = signal.toUtf8();
        QByteArray messageUtf8 = message.toUtf8();
        messagebroker::broadcast(signalUtf8.constData(), messageUtf8.constData());
    }

    void setListeningFor(const QStringList &l) {
        _listeningFor = l;
    }

    const QStringList& getListeningFor() const {
        return _listeningFor;
    }

signals:
    void signalReceived(const QString &signal, const QString &message);

private:
    QStringList _listeningFor;
};