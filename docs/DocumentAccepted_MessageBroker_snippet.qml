// Add this MessageBroker to a QML component that has access to PlatformHelpers
// This listens for documentAccepted signals from the HTTP server
// and calls PlatformHelpers.documentAccepted()

import net.noham.MessageBroker

MessageBroker {
    id: documentAcceptedBroker
    listeningFor: ["documentAccepted"]
    
    onSignalReceived: (signal, message) => {
        console.log("[DocumentAccepted.MessageBroker] Received signal:", signal);
        console.log("[DocumentAccepted.MessageBroker] Message data:", message);
        
        try {
            // Parse JSON message from HTTP server
            const data = JSON.parse(message);
            console.log("[DocumentAccepted.MessageBroker] Parsed request:", JSON.stringify(data));
            
            // Extract parameters with defaults
            const url = data.url || "";
            const password = data.password || "";
            const directoryId = data.directoryId || "";
            const flag1 = data.flag1 !== undefined ? data.flag1 : false;
            const flag2 = data.flag2 !== undefined ? data.flag2 : false;
            
            console.log("[DocumentAccepted.MessageBroker] Parameters:");
            console.log("[DocumentAccepted.MessageBroker]   url:", url);
            console.log("[DocumentAccepted.MessageBroker]   password:", password ? "(set)" : "(empty)");
            console.log("[DocumentAccepted.MessageBroker]   directoryId:", directoryId);
            console.log("[DocumentAccepted.MessageBroker]   flag1:", flag1);
            console.log("[DocumentAccepted.MessageBroker]   flag2:", flag2);
            
            // Validate required parameters
            if (!url) {
                console.error("[DocumentAccepted.MessageBroker] ERROR: Missing 'url' parameter");
                return;
            }
            if (!directoryId) {
                console.error("[DocumentAccepted.MessageBroker] ERROR: Missing 'directoryId' parameter");
                return;
            }
            
            // Call PlatformHelpers.documentAccepted
            console.log("[DocumentAccepted.MessageBroker] Calling PlatformHelpers.documentAccepted...");
            PlatformHelpers.documentAccepted(url, password, directoryId, flag1, flag2);
            console.log("[DocumentAccepted.MessageBroker] Document accepted successfully");
            
        } catch (error) {
            console.error("[DocumentAccepted.MessageBroker] ERROR parsing request:", error);
            console.error("[DocumentAccepted.MessageBroker] Message was:", message);
        }
    }
}
