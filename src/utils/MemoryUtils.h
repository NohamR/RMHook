#import <Foundation/Foundation.h>

@interface MemoryUtils : NSObject

/**
 * Hooks a function by symbol name with automatic fallback from symtbl_solve to symexp_solve.
 *
 * @param imageName The name of the image/library to search in (e.g., "QtNetwork").
 * @param symbolName The mangled symbol name to hook.
 * @param hookFunction The function to replace the original with.
 * @param originalFunction Pointer to store the original function address.
 * @param logPrefix Prefix for log messages (optional, can be nil).
 * @return YES if the hook was successfully installed, NO otherwise.
 */
+ (BOOL)hookSymbol:(NSString *)imageName
        symbolName:(NSString *)symbolName
      hookFunction:(void *)hookFunction
  originalFunction:(void **)originalFunction
         logPrefix:(NSString *)logPrefix;

/**
 * Hooks a function by symbol name with delay support.
 *
 * @param delayInSeconds The delay in seconds before installing the hook (use 0 for immediate hooking).
 */
+ (BOOL)hookSymbol:(NSString *)imageName
        symbolName:(NSString *)symbolName
      hookFunction:(void *)hookFunction
  originalFunction:(void **)originalFunction
         logPrefix:(NSString *)logPrefix
    delayInSeconds:(NSTimeInterval)delayInSeconds;

/**
 * Hooks a function at a specific address after calculating ASLR slide.
 *
 * @param imageName The name of the image/library (e.g., "QtNetwork" or "reMarkable").
 * @param staticAddress The static address from the binary (before ASLR).
 * @param hookFunction The function to replace the original with.
 * @param originalFunction Pointer to store the original function address.
 * @param logPrefix Prefix for log messages (optional, can be nil).
 * @return YES if the hook was successfully installed, NO otherwise.
 */
+ (BOOL)hookAddress:(NSString *)imageName
      staticAddress:(uintptr_t)staticAddress
       hookFunction:(void *)hookFunction
   originalFunction:(void **)originalFunction
          logPrefix:(NSString *)logPrefix;

@end
