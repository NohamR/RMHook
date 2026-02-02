import net.noham.MessageBroker

MessageBroker {
    id: demoBroker
    listeningFor: ["demoSignal"]

    onSignalReceived: (signal, message) => {
        console.log("Got message", signal, message);
    }
}

MouseArea {
    onClicked: () => {
        demoBroker.sendSignal("mySignalName", "Hello from QML!");
    }
}