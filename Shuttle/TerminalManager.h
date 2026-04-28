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

// 在后台执行命令（使用 NSTask 替代 screen）
- (void)executeCommandInBackground:(NSString *)command title:(NSString *)title;

// 直接执行方法（不使用AppleScript）
- (void)executeCommandDirectly:(NSString *)command
                  terminalType:(TerminalType)terminalType
                    windowMode:(WindowMode)windowMode
                         theme:(NSString *)theme
                         title:(NSString *)title;

// 辅助方法声明
- (void)executeInTerminalDirectly:(NSString *)command
                       windowMode:(WindowMode)windowMode
                            theme:(NSString *)theme
                            title:(NSString *)title;

- (void)executeInITermDirectly:(NSString *)command
                    windowMode:(WindowMode)windowMode
                         theme:(NSString *)theme
                         title:(NSString *)title;

- (NSString *)escapeShellCommand:(NSString *)command;

@end
