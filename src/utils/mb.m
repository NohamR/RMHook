// Example usage of MessageBroker from C++/Objective-C

#include <QObject>
#include <QProcess>
#include <QString>
#include <QQmlApplicationEngine>
#include "MessageBroker.h"

// Example: Register MessageBroker QML type (called from dylib init)
void initMessageBroker() {
    messagebroker::registerQmlType();
}

// Example: Send a signal from C++ to QML
void sendSignal() {
    messagebroker::broadcast("demoSignal", "Hello from C!");
}