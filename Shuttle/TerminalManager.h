//
//  TerminalManager.h
//  Shuttle
//

#import <Foundation/Foundation.h>

typedef NS_ENUM(NSInteger, TerminalType) {
    TerminalTypeDefault,
    TerminalTypeITerm
};

typedef NS_ENUM(NSInteger, WindowMode) {
    WindowModeNew,
    WindowModeCurrent,
    WindowModeTab,
    WindowModeVirtual
};

@interface TerminalManager : NSObject

+ (instancetype)sharedManager;

// 在终端中执行命令
- (void)executeCommand:(NSString *)command 
           terminalType:(TerminalType)terminalType 
             windowMode:(WindowMode)windowMode 
                  theme:(NSString *)theme 
                  title:(NSString *)title;

@end
