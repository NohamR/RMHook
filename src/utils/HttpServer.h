// HTTP Server for RMHook - native macOS implementation
#pragma once

#import <Foundation/Foundation.h>

#ifdef __cplusplus
extern "C" {
#endif

namespace httpserver {
    // Start HTTP server on specified port
    bool start(uint16_t port = 8080);
    
    // Stop HTTP server
    void stop();
    
    // Check if server is running
    bool isRunning();
}

#ifdef __cplusplus
}
#endif
