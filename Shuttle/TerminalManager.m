//
//  TerminalManager.m
//  Shuttle
//

#import <Foundation/Foundation.h>
#import "TerminalManager.h"

@implementation TerminalManager

+ (instancetype)sharedManager {
    static TerminalManager *sharedManager = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedManager = [[self alloc] init];
    });
    return sharedManager;
}

- (void)executeCommand:(NSString *)command
          terminalType:(TerminalType)terminalType
            windowMode:(WindowMode)windowMode
                 theme:(NSString *)theme
                 title:(NSString *)title {
    [self executeCommandDirectly:command
                    terminalType:terminalType
                      windowMode:windowMode
                           theme:theme
                           title:title];
}

- (void)executeInTerminal:(NSString *)command windowMode:(WindowMode)windowMode theme:(NSString *)theme title:(NSString *)title {
    NSString *script;

    // 准备终端的不同执行模式
    if (windowMode == WindowModeNew) {
        // 在新窗口中执行
        script = [NSString stringWithFormat:@"tell application \"Terminal\"\n"
                  "  activate\n"
                  "  do script \"\"\n"
                  "  set newWindow to front window\n"
                  "  do script \"%@\" in newWindow\n"
                  "  try\n"
                  "    set current settings of newWindow to settings set \"%@\"\n"
                  "  end try\n"
                  "  set custom title of newWindow to \"%@\"\n"
                  "end tell",
                  [self escapeString:command],
                  [self escapeString:theme],
                  [self escapeString:title]];
    } else if (windowMode == WindowModeCurrent) {
        // 在当前窗口中执行
        script = [NSString stringWithFormat:@"tell application \"Terminal\"\n"
                  "  reopen\n"
                  "  activate\n"
                  "  do script \"%@\" in front window\n"
                  "end tell",
                  [self escapeString:command]];
    } else { // WindowModeTab
        // 在新标签页中执行
        script = [NSString stringWithFormat:@"tell application \"Terminal\"\n"
                  "  activate\n"
                  "  tell application \"System Events\"\n"
                  "    tell process \"Terminal\"\n"
                  "      keystroke \"t\" using {command down}\n"
                  "    end tell\n"
                  "  end tell\n"
                  "  do script \"%@\" in front window\n"
                  "  set current settings of front window to settings set \"%@\"\n"
                  "  set custom title of front window to \"%@\"\n"
                  "end tell",
                  [self escapeString:command],
                  [self escapeString:theme],
                  [self escapeString:title]];
    }

    // 使用 NSAppleScript 执行脚本，而不是依赖外部 .scpt 文件
    NSAppleScript *appleScript = [[NSAppleScript alloc] initWithSource:script];
    NSDictionary *error = nil;
    [appleScript executeAndReturnError:&error];

    if (error) {
        NSLog(@"Error executing Terminal script: %@", error);
    }
}

- (void)executeInITerm:(NSString *)command windowMode:(WindowMode)windowMode theme:(NSString *)theme title:(NSString *)title {
    NSString *script;

    // 准备 iTerm 的不同执行模式
    if (windowMode == WindowModeNew) {
        // 在新窗口中执行
        script = [NSString stringWithFormat:@"tell application \"iTerm\"\n"
                  "  activate\n"
                  "  try\n"
                  "    create window with profile \"%@\"\n"
                  "  on error\n"
                  "    create window with profile \"Default\"\n"
                  "  end try\n"
                  "  tell the current window\n"
                  "    tell the current session\n"
                  "      set name to \"%@\"\n"
                  "      write text \"%@\"\n"
                  "    end tell\n"
                  "  end tell\n"
                  "end tell",
                  [self escapeString:theme],
                  [self escapeString:title],
                  [self escapeString:command]];
    } else if (windowMode == WindowModeCurrent) {
        // 在当前窗口中执行
        script = [NSString stringWithFormat:@"tell application \"iTerm\"\n"
                  "  reopen\n"
                  "  activate\n"
                  "  tell the current window\n"
                  "    tell the current session\n"
                  "      write text \"%@\"\n"
                  "    end tell\n"
                  "  end tell\n"
                  "end tell",
                  [self escapeString:command]];
    } else { // WindowModeTab
        // 在新标签页中执行
        script = [NSString stringWithFormat:@"tell application \"iTerm\"\n"
                  "  activate\n"
                  "  tell the current window\n"
                  "    try\n"
                  "      create tab with profile \"%@\"\n"
                  "    on error\n"
                  "      create tab with profile \"Default\"\n"
                  "    end try\n"
                  "    tell the current tab\n"
                  "      tell the current session\n"
                  "        set name to \"%@\"\n"
                  "        write text \"%@\"\n"
                  "      end tell\n"
                  "    end tell\n"
                  "  end tell\n"
                  "end tell",
                  [self escapeString:theme],
                  [self escapeString:title],
                  [self escapeString:command]];
    }

    // 使用 NSAppleScript 执行脚本，而不是依赖外部 .scpt 文件
    NSAppleScript *appleScript = [[NSAppleScript alloc] initWithSource:script];
    NSDictionary *error = nil;
    [appleScript executeAndReturnError:&error];

    if (error) {
        NSLog(@"Error executing iTerm script: %@", error);
    }
}

- (void)executeCommandInBackground:(NSString *)command title:(NSString *)title {
    // 使用 NSTask 替代 screen 命令
    NSTask *task = [[NSTask alloc] init];
    [task setLaunchPath:@"/usr/bin/screen"];

    // 构建 screen 命令参数
    NSString *screenTitle = ([title length] > 0) ? title : @"Shuttle";
    NSString *shellCommand = command ?: @"";
    NSArray *arguments = @[@"-d", @"-m", @"-S", screenTitle, @"/bin/sh", @"-c", shellCommand];
    [task setArguments:arguments];

    // 启动任务
    NSError *error = nil;
    if (![task launchAndReturnError:&error]) {
        NSLog(@"Error executing background command: %@", error);
    }
}

// 辅助方法：转义字符串用于 AppleScript
- (NSString *)escapeString:(NSString *)string {
    if (!string) return @"";

    NSString *escaped = [string stringByReplacingOccurrencesOfString:@"\\" withString:@"\\\\"];
    escaped = [escaped stringByReplacingOccurrencesOfString:@"\"" withString:@"\\\""];
    escaped = [escaped stringByReplacingOccurrencesOfString:@"\n" withString:@"\\n"];
    escaped = [escaped stringByReplacingOccurrencesOfString:@"\r" withString:@"\\r"];
    escaped = [escaped stringByReplacingOccurrencesOfString:@"\t" withString:@"\\t"];

    return escaped;
}

- (void)executeCommandDirectly:(NSString *)command
                  terminalType:(TerminalType)terminalType
                    windowMode:(WindowMode)windowMode
                         theme:(NSString *)theme
                         title:(NSString *)title {

    if (windowMode == WindowModeVirtual) {
        [self executeCommandInBackground:command title:(title ?: @"Shuttle")];
        return;
    }

    if (terminalType == TerminalTypeDefault) {
        // 执行 Terminal.app 命令
        [self executeInTerminalDirectly:command windowMode:windowMode theme:theme title:title];
    } else {
        // 执行 iTerm 命令
        [self executeInITermDirectly:command windowMode:windowMode theme:theme title:title];
    }
}

- (NSString *)escapeShellCommand:(NSString *)command {
    if (!command) return @"";

    // 转义单引号
    NSString *escaped = [command stringByReplacingOccurrencesOfString:@"'" withString:@"'\\''"];
    // 确保转义其他特殊字符
    return escaped;
}

- (BOOL)runOSAScript:(NSString *)script context:(NSString *)context {
    NSTask *osascriptTask = [[NSTask alloc] init];
    NSPipe *errorPipe = [NSPipe pipe];
    [osascriptTask setLaunchPath:@"/usr/bin/osascript"];
    [osascriptTask setArguments:@[@"-e", script]];
    [osascriptTask setStandardError:errorPipe];

    NSError *error = nil;
    if (![osascriptTask launchAndReturnError:&error]) {
        NSLog(@"Error executing %@ AppleScript: %@", context, error);
        return NO;
    }

    [osascriptTask waitUntilExit];

    if ([osascriptTask terminationStatus] != 0) {
        NSData *errorData = [[errorPipe fileHandleForReading] readDataToEndOfFile];
        NSString *errorOutput = [[NSString alloc] initWithData:errorData encoding:NSUTF8StringEncoding];
        NSLog(@"Error executing %@ AppleScript: %@", context, errorOutput);
        return NO;
    }

    return YES;
}

- (void)executeInITermDirectly:(NSString *)command windowMode:(WindowMode)windowMode theme:(NSString *)theme title:(NSString *)title {
    NSString *escapedCommand = [self escapeString:command];
    NSString *escapedTheme = [self escapeString:theme ?: @"Default"];
    NSString *escapedTitle = [self escapeString:title ?: @"Shuttle"];
    NSString *profileCreation = [NSString stringWithFormat:@"\"%@\"", escapedTheme];
    NSString *osascriptCommand = nil;

    if (windowMode == WindowModeNew) {
        osascriptCommand = [NSString stringWithFormat:
            @"tell application \"iTerm\"\n"
             "  activate\n"
             "  try\n"
             "    create window with profile %@\n"
             "  on error\n"
             "    create window with default profile\n"
             "  end try\n"
             "  tell current window\n"
             "    tell current session\n"
             "      set name to \"%@\"\n"
             "      write text \"%@\"\n"
             "    end tell\n"
             "  end tell\n"
             "end tell",
             profileCreation, escapedTitle, escapedCommand];
    } else if (windowMode == WindowModeTab) {
        osascriptCommand = [NSString stringWithFormat:
            @"tell application \"iTerm\"\n"
             "  activate\n"
             "  if (count of windows) = 0 then\n"
             "    try\n"
             "      create window with profile %@\n"
             "    on error\n"
             "      create window with default profile\n"
             "    end try\n"
             "  end if\n"
             "  tell current window\n"
             "    try\n"
             "      create tab with profile %@\n"
             "    on error\n"
             "      create tab with default profile\n"
             "    end try\n"
             "    tell current session\n"
             "      set name to \"%@\"\n"
             "      write text \"%@\"\n"
             "    end tell\n"
             "  end tell\n"
             "end tell",
             profileCreation, profileCreation, escapedTitle, escapedCommand];
    } else {
        osascriptCommand = [NSString stringWithFormat:
            @"tell application \"iTerm\"\n"
             "  reopen\n"
             "  activate\n"
             "  if (count of windows) = 0 then\n"
             "    try\n"
             "      create window with profile %@\n"
             "    on error\n"
             "      create window with default profile\n"
             "    end try\n"
             "  end if\n"
             "  tell current window\n"
             "    tell current session\n"
             "      write text \"%@\"\n"
             "    end tell\n"
             "  end tell\n"
             "end tell",
             profileCreation, escapedCommand];
    }

    [self runOSAScript:osascriptCommand context:@"iTerm"];
}

- (void)executeInTerminalDirectly:(NSString *)command windowMode:(WindowMode)windowMode theme:(NSString *)theme title:(NSString *)title {
    NSString *escapedCommand = [self escapeString:command];
    NSString *escapedTheme = [self escapeString:theme ?: @"Basic"];
    NSString *escapedTitle = [self escapeString:title ?: @"Shuttle"];

    NSString *osascriptCommand = nil;

    if (windowMode == WindowModeNew) {
        osascriptCommand = [NSString stringWithFormat:
            @"tell application \"Terminal\"\n"
             "  do script \"%@\"\n"
             "  set targetWindow to front window\n"
             "  try\n"
             "    set current settings of targetWindow to settings set \"%@\"\n"
             "  end try\n"
             "  try\n"
             "    set custom title of targetWindow to \"%@\"\n"
             "  end try\n"
             "  activate\n"
             "end tell\n"
             "try\n"
             "tell application \"System Events\"\n"
             "  tell process \"Terminal\"\n"
             "    set frontmost to true\n"
             "  end tell\n"
             "end tell\n"
             "end try",
             escapedCommand, escapedTheme, escapedTitle];

    } else if (windowMode == WindowModeTab) {
        osascriptCommand = [NSString stringWithFormat:
            @"tell application \"Terminal\"\n"
             "  if (count of windows) = 0 then\n"
             "    do script \"%@\"\n"
             "  else\n"
             "    activate\n"
             "    set openedTab to false\n"
             "    try\n"
             "    tell application \"System Events\"\n"
             "      tell process \"Terminal\"\n"
             "        set frontmost to true\n"
             "        keystroke \"t\" using {command down}\n"
             "      end tell\n"
             "    end tell\n"
             "    set openedTab to true\n"
             "    end try\n"
             "    delay 0.2\n"
             "    if openedTab then\n"
             "      do script \"%@\" in front window\n"
             "    else\n"
             "      do script \"%@\"\n"
             "    end if\n"
             "  end if\n"
             "  set targetWindow to front window\n"
             "  try\n"
             "    set current settings of targetWindow to settings set \"%@\"\n"
             "  end try\n"
             "  try\n"
             "    set custom title of targetWindow to \"%@\"\n"
             "  end try\n"
             "  activate\n"
             "end tell\n"
             "try\n"
             "tell application \"System Events\"\n"
             "  tell process \"Terminal\"\n"
             "    set frontmost to true\n"
             "  end tell\n"
             "end tell\n"
             "end try",
             escapedCommand, escapedCommand, escapedCommand, escapedTheme, escapedTitle];

    } else {
        osascriptCommand = [NSString stringWithFormat:
            @"tell application \"Terminal\"\n"
             "  if (count of windows) = 0 then\n"
             "    do script \"%@\"\n"
             "  else\n"
             "    activate\n"
             "    do script \"%@\" in front window\n"
             "  end if\n"
             "  activate\n"
             "end tell\n"
             "try\n"
             "tell application \"System Events\"\n"
             "  tell process \"Terminal\"\n"
             "    set frontmost to true\n"
             "  end tell\n"
             "end tell\n"
             "end try",
             escapedCommand, escapedCommand];
    }

    [self runOSAScript:osascriptCommand context:@"Terminal"];
}

@end
