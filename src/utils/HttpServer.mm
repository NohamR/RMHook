// HTTP Server for RMHook - native macOS implementation using CFSocket

#import <Foundation/Foundation.h>
#import <CoreFoundation/CoreFoundation.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <unistd.h>
#include "HttpServer.h"
#include "MessageBroker.h"
#include "Logger.h"

static CFSocketRef g_serverSocket = NULL;
static uint16_t g_serverPort = 0;
static bool g_isRunning = false;

// Forward declarations
static void handleClientConnection(int clientSocket);
static void sendResponse(int clientSocket, int statusCode, NSString *body, NSString *contentType);
static void handleExportFileRequest(int clientSocket, NSDictionary *jsonData);
static void handleDocumentAcceptedRequest(int clientSocket, NSDictionary *jsonData);

// Socket callback
static void socketCallback(CFSocketRef socket, CFSocketCallBackType type, 
                          CFDataRef address, const void *data, void *info)
{
    if (type == kCFSocketAcceptCallBack) {
        CFSocketNativeHandle clientSocket = *(CFSocketNativeHandle *)data;
        NSLogger(@"[HttpServer] New connection accepted, socket: %d", clientSocket);
        
        // Handle client in background
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            handleClientConnection(clientSocket);
        });
    }
}

static void handleClientConnection(int clientSocket)
{
    @autoreleasepool {
        // Read request
        char buffer[4096];
        ssize_t bytesRead = recv(clientSocket, buffer, sizeof(buffer) - 1, 0);
        
        if (bytesRead <= 0) {
            close(clientSocket);
            return;
        }
        
        buffer[bytesRead] = '\0';
        NSString *request = [NSString stringWithUTF8String:buffer];
        
        NSLogger(@"[HttpServer] Received request (%ld bytes)", (long)bytesRead);
        
        // Parse request line
        NSArray *lines = [request componentsSeparatedByString:@"\r\n"];
        if (lines.count == 0) {
            sendResponse(clientSocket, 400, @"{\"error\": \"Invalid request\"}", @"application/json");
            close(clientSocket);
            return;
        }
        
        NSArray *requestLine = [lines[0] componentsSeparatedByString:@" "];
        if (requestLine.count < 3) {
            sendResponse(clientSocket, 400, @"{\"error\": \"Invalid request line\"}", @"application/json");
            close(clientSocket);
            return;
        }
        
        NSString *method = requestLine[0];
        NSString *path = requestLine[1];
        
        NSLogger(@"[HttpServer] %@ %@", method, path);
        
        // Find body (after \r\n\r\n)
        NSRange bodyRange = [request rangeOfString:@"\r\n\r\n"];
        NSString *body = nil;
        if (bodyRange.location != NSNotFound) {
            body = [request substringFromIndex:bodyRange.location + 4];
        }
        
        // Route requests
        if ([path isEqualToString:@"/exportFile"] && [method isEqualToString:@"POST"]) {
            if (!body || body.length == 0) {
                sendResponse(clientSocket, 400, @"{\"error\": \"Missing request body\"}", @"application/json");
                close(clientSocket);
                return;
            }
            
            NSData *jsonData = [body dataUsingEncoding:NSUTF8StringEncoding];
            NSError *error = nil;
            id json = [NSJSONSerialization JSONObjectWithData:jsonData options:0 error:&error];
            
            if (error || ![json isKindOfClass:[NSDictionary class]]) {
                NSString *errorMsg = [NSString stringWithFormat:@"{\"error\": \"Invalid JSON: %@\"}", 
                                     error ? error.localizedDescription : @"Not an object"];
                sendResponse(clientSocket, 400, errorMsg, @"application/json");
                close(clientSocket);
                return;
            }
            
            handleExportFileRequest(clientSocket, (NSDictionary *)json);
            
        } else if ([path isEqualToString:@"/documentAccepted"] && [method isEqualToString:@"POST"]) {
            if (!body || body.length == 0) {
                sendResponse(clientSocket, 400, @"{\"error\": \"Missing request body\"}", @"application/json");
                close(clientSocket);
                return;
            }
            
            NSData *jsonData = [body dataUsingEncoding:NSUTF8StringEncoding];
            NSError *error = nil;
            id json = [NSJSONSerialization JSONObjectWithData:jsonData options:0 error:&error];
            
            if (error || ![json isKindOfClass:[NSDictionary class]]) {
                NSString *errorMsg = [NSString stringWithFormat:@"{\"error\": \"Invalid JSON: %@\"}", 
                                     error ? error.localizedDescription : @"Not an object"];
                sendResponse(clientSocket, 400, errorMsg, @"application/json");
                close(clientSocket);
                return;
            }
            
            handleDocumentAcceptedRequest(clientSocket, (NSDictionary *)json);
            
        } else if ([path isEqualToString:@"/health"] || [path isEqualToString:@"/"]) {
            sendResponse(clientSocket, 200, @"{\"status\": \"ok\", \"service\": \"RMHook HTTP Server\"}", @"application/json");
            
        } else {
            sendResponse(clientSocket, 404, @"{\"error\": \"Endpoint not found\"}", @"application/json");
        }
        
        close(clientSocket);
    }
}

static void handleExportFileRequest(int clientSocket, NSDictionary *jsonData)
{
    NSLogger(@"[HttpServer] Processing /exportFile request");
    
    // Convert to JSON string for MessageBroker
    NSError *error = nil;
    NSData *jsonDataEncoded = [NSJSONSerialization dataWithJSONObject:jsonData 
                                                               options:0 
                                                                 error:&error];
    
    if (error) {
        NSString *errorMsg = [NSString stringWithFormat:@"{\"error\": \"Failed to encode JSON: %@\"}", 
                             error.localizedDescription];
        sendResponse(clientSocket, 500, errorMsg, @"application/json");
        return;
    }
    
    NSString *jsonStr = [[NSString alloc] initWithData:jsonDataEncoded encoding:NSUTF8StringEncoding];
    NSLogger(@"[HttpServer] Broadcasting exportFile signal with data: %@", jsonStr);
    
    // Broadcast to MessageBroker
    messagebroker::broadcast("exportFile", [jsonStr UTF8String]);
    
    // Send success response
    sendResponse(clientSocket, 200, 
                @"{\"status\": \"success\", \"message\": \"Export request sent to application\"}", 
                @"application/json");
}

static void handleDocumentAcceptedRequest(int clientSocket, NSDictionary *jsonData)
{
    NSLogger(@"[HttpServer] Processing /documentAccepted request");
    
    // Convert to JSON string for MessageBroker
    NSError *error = nil;
    NSData *jsonDataEncoded = [NSJSONSerialization dataWithJSONObject:jsonData 
                                                               options:0 
                                                                 error:&error];
    
    if (error) {
        NSString *errorMsg = [NSString stringWithFormat:@"{\"error\": \"Failed to encode JSON: %@\"}", 
                             error.localizedDescription];
        sendResponse(clientSocket, 500, errorMsg, @"application/json");
        return;
    }
    
    NSString *jsonStr = [[NSString alloc] initWithData:jsonDataEncoded encoding:NSUTF8StringEncoding];
    NSLogger(@"[HttpServer] Broadcasting documentAccepted signal with data: %@", jsonStr);
    
    // Broadcast to MessageBroker
    messagebroker::broadcast("documentAccepted", [jsonStr UTF8String]);
    
    // Send success response
    sendResponse(clientSocket, 200, 
                @"{\"status\": \"success\", \"message\": \"Document accepted request sent to application\"}", 
                @"application/json");
}

static void sendResponse(int clientSocket, int statusCode, NSString *body, NSString *contentType)
{
    NSString *statusText;
    switch (statusCode) {
        case 200: statusText = @"OK"; break;
        case 400: statusText = @"Bad Request"; break;
        case 404: statusText = @"Not Found"; break;
        case 500: statusText = @"Internal Server Error"; break;
        default: statusText = @"Unknown"; break;
    }
    
    NSData *bodyData = [body dataUsingEncoding:NSUTF8StringEncoding];
    
    NSString *response = [NSString stringWithFormat:
        @"HTTP/1.1 %d %@\r\n"
        @"Content-Type: %@; charset=utf-8\r\n"
        @"Content-Length: %lu\r\n"
        @"Access-Control-Allow-Origin: *\r\n"
        @"Connection: close\r\n"
        @"\r\n"
        @"%@",
        statusCode, statusText, contentType, (unsigned long)bodyData.length, body
    ];
    
    NSData *responseData = [response dataUsingEncoding:NSUTF8StringEncoding];
    send(clientSocket, responseData.bytes, responseData.length, 0);
}

namespace httpserver {
    
bool start(uint16_t port)
{
    if (g_isRunning) {
        NSLogger(@"[HttpServer] Server already running on port %d", g_serverPort);
        return true;
    }
    
    // Create socket
    CFSocketContext context = {0, NULL, NULL, NULL, NULL};
    g_serverSocket = CFSocketCreate(kCFAllocatorDefault, 
                                    PF_INET, 
                                    SOCK_STREAM, 
                                    IPPROTO_TCP,
                                    kCFSocketAcceptCallBack, 
                                    socketCallback, 
                                    &context);
    
    if (!g_serverSocket) {
        NSLogger(@"[HttpServer] Failed to create socket");
        return false;
    }
    
    // Set socket options
    int yes = 1;
    setsockopt(CFSocketGetNative(g_serverSocket), SOL_SOCKET, SO_REUSEADDR, &yes, sizeof(yes));
    
    // Bind to address
    struct sockaddr_in addr;
    memset(&addr, 0, sizeof(addr));
    addr.sin_len = sizeof(addr);
    addr.sin_family = AF_INET;
    addr.sin_port = htons(port);
    addr.sin_addr.s_addr = htonl(INADDR_LOOPBACK); // localhost only
    
    CFDataRef addressData = CFDataCreate(kCFAllocatorDefault, 
                                        (const UInt8 *)&addr, 
                                        sizeof(addr));
    
    CFSocketError error = CFSocketSetAddress(g_serverSocket, addressData);
    CFRelease(addressData);
    
    if (error != kCFSocketSuccess) {
        NSLogger(@"[HttpServer] Failed to bind to port %d (error: %ld)", port, (long)error);
        CFRelease(g_serverSocket);
        g_serverSocket = NULL;
        return false;
    }
    
    // Add to run loop
    CFRunLoopSourceRef source = CFSocketCreateRunLoopSource(kCFAllocatorDefault, g_serverSocket, 0);
    CFRunLoopAddSource(CFRunLoopGetMain(), source, kCFRunLoopCommonModes);
    CFRelease(source);
    
    g_serverPort = port;
    g_isRunning = true;
    
    NSLogger(@"[HttpServer] HTTP server started successfully on http://localhost:%d", port);
    return true;
}

void stop()
{
    if (!g_isRunning) {
        return;
    }
    
    if (g_serverSocket) {
        CFSocketInvalidate(g_serverSocket);
        CFRelease(g_serverSocket);
        g_serverSocket = NULL;
    }
    
    g_isRunning = false;
    NSLogger(@"[HttpServer] HTTP server stopped");
}

bool isRunning()
{
    return g_isRunning;
}

} // namespace httpserver
