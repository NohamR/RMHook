#import <Foundation/Foundation.h>
#import "MemoryUtils.h"
#import <mach-o/dyld.h>
#import "Logger.h"
#import "tinyhook.h"

@implementation MemoryUtils

+ (int)indexForImageWithName:(NSString *)imageName {
    uint32_t imageCount = _dyld_image_count();
    for (uint32_t i = 0; i < imageCount; i++) {
        const char* currentImageName = _dyld_get_image_name(i);
        NSString *currentImageNameString = [NSString stringWithUTF8String:currentImageName];
        
        if ([currentImageNameString.lastPathComponent isEqualToString:imageName]) {
            return i;
        }
    }
    
    return -1;
}

+ (BOOL)hookSymbol:(NSString *)imageName
        symbolName:(NSString *)symbolName
      hookFunction:(void *)hookFunction
  originalFunction:(void **)originalFunction
         logPrefix:(NSString *)logPrefix {
    return [self hookSymbol:imageName
                 symbolName:symbolName
               hookFunction:hookFunction
           originalFunction:originalFunction
                  logPrefix:logPrefix
             delayInSeconds:0];
}

+ (BOOL)hookSymbol:(NSString *)imageName
        symbolName:(NSString *)symbolName
      hookFunction:(void *)hookFunction
  originalFunction:(void **)originalFunction
         logPrefix:(NSString *)logPrefix
    delayInSeconds:(NSTimeInterval)delayInSeconds {
    
    if (delayInSeconds > 0) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delayInSeconds * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [self performHookSymbol:imageName
                         symbolName:symbolName
                       hookFunction:hookFunction
                   originalFunction:originalFunction
                          logPrefix:logPrefix];
        });
        return YES;
    } else {
        return [self performHookSymbol:imageName
                            symbolName:symbolName
                          hookFunction:hookFunction
                      originalFunction:originalFunction
                             logPrefix:logPrefix];
    }
}

+ (BOOL)performHookSymbol:(NSString *)imageName
               symbolName:(NSString *)symbolName
             hookFunction:(void *)hookFunction
         originalFunction:(void **)originalFunction
                logPrefix:(NSString *)logPrefix {
    
    NSLogger(@"%@ Starting hook installation for %@", logPrefix, symbolName);
    
    int imageIndex = [self indexForImageWithName:imageName];
    if (imageIndex < 0) {
        NSLogger(@"%@ ERROR: Image %@ not found", logPrefix, imageName);
        return NO;
    }
    
    void* symbolAddress = NULL;
    
    // Try to find the symbol address using symtbl_solve first
    symbolAddress = symtbl_solve(imageIndex, [symbolName UTF8String]);
    
    if (symbolAddress) {
        NSLogger(@"%@ %@ found with symtbl_solve at address: %p", logPrefix, symbolName, symbolAddress);
    } else {
        NSLogger(@"%@ %@ not found with symtbl_solve, trying symexp_solve...", logPrefix, symbolName);
        symbolAddress = symexp_solve(imageIndex, [symbolName UTF8String]);
        
        if (symbolAddress) {
            NSLogger(@"%@ %@ found with symexp_solve at address: %p", logPrefix, symbolName, symbolAddress);
        } else {
            NSLogger(@"%@ ERROR: Unable to find symbol %@", logPrefix, symbolName);
            return NO;
        }
    }
    
    // Install the hook using tiny_hook and get the original function trampoline if requested
    int hookResult = tiny_hook(symbolAddress, hookFunction, originalFunction);
    
    if (hookResult == 0) {
        NSLogger(@"%@ Hook successfully installed for %@", logPrefix, symbolName);
        return YES;
    } else {
        NSLogger(@"%@ ERROR: Failed to install hook for %@ (code: %d)", logPrefix, symbolName, hookResult);
        return NO;
    }
}

@end
