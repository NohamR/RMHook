// Add this MessageBroker to ExportDialog.qml after the PopupDialog definition
// This should be added near the top of the component, after property definitions

import net.noham.MessageBroker

// ... existing properties ...

// MessageBroker for HTTP server export requests
MessageBroker {
    id: exportBroker
    listeningFor: ["exportFile"]
    
    onSignalReceived: (signal, message) => {
        console.log("[ExportDialog.MessageBroker] Received signal:", signal);
        console.log("[ExportDialog.MessageBroker] Message data:", message);
        
        try {
            // Parse JSON message from HTTP server
            const data = JSON.parse(message);
            console.log("[ExportDialog.MessageBroker] Parsed export request:", JSON.stringify(data));
            
            // Extract parameters
            const target = data.target || "";
            const documentId = data.id || data.documentId || "";
            const format = data.format !== undefined ? data.format : PlatformHelpers.ExportPdf;
            const password = data.password || "";
            const keepPassword = data.keepPassword !== undefined ? data.keepPassword : true;
            const grayscale = data.grayscale !== undefined ? data.grayscale : false;
            const pageSelection = data.pageSelection || [];
            
            console.log("[ExportDialog.MessageBroker] Export parameters:");
            console.log("[ExportDialog.MessageBroker]   target:", target);
            console.log("[ExportDialog.MessageBroker]   documentId:", documentId);
            console.log("[ExportDialog.MessageBroker]   format:", format);
            console.log("[ExportDialog.MessageBroker]   keepPassword:", keepPassword);
            console.log("[ExportDialog.MessageBroker]   grayscale:", grayscale);
            console.log("[ExportDialog.MessageBroker]   pageSelection:", JSON.stringify(pageSelection));
            
            // Validate required parameters
            if (!target) {
                console.error("[ExportDialog.MessageBroker] ERROR: Missing 'target' parameter");
                return;
            }
            if (!documentId) {
                console.error("[ExportDialog.MessageBroker] ERROR: Missing 'id' or 'documentId' parameter");
                return;
            }
            
            // Call PlatformHelpers.exportFile
            console.log("[ExportDialog.MessageBroker] Calling PlatformHelpers.exportFile...");
            
            if (pageSelection && pageSelection.length > 0) {
                console.log("[ExportDialog.MessageBroker] Exporting with page selection");
                PlatformHelpers.exportFile(target, documentId, format, password, keepPassword, grayscale, pageSelection);
            } else {
                console.log("[ExportDialog.MessageBroker] Exporting full document");
                PlatformHelpers.exportFile(target, documentId, format, password, keepPassword, grayscale);
            }
            
            console.log("[ExportDialog.MessageBroker] Export completed successfully");
            
        } catch (error) {
            console.error("[ExportDialog.MessageBroker] ERROR parsing export request:", error);
            console.error("[ExportDialog.MessageBroker] Message was:", message);
        }
    }
}
