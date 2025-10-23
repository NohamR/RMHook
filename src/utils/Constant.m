#import <Foundation/Foundation.h>
#import "Constant.h"
#import <Cocoa/Cocoa.h>
#import "Logger.h"

@implementation Constant

static NSString *_currentAppPath;

+ (void)initialize {
    if (self == [Constant class]) {
        NSLogger(@"[Constant] Initializing...");
        
        NSBundle *app = [NSBundle mainBundle];
        _currentAppPath = [[app bundlePath] copy];
        
        NSLogger(@"[Constant] App path: %@", _currentAppPath);
    }
}

+ (NSString *)getCurrentAppPath {
    return _currentAppPath;
}

@end
