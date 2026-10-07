//
//  TerminalManager.m
//  Shuttle
//

#import <Foundation/Foundation.h>
#import <Cocoa/Cocoa.h>
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

- (NSString *)stringFromOSAScript:(NSString *)script context:(NSString *)context {
    NSTask *osascriptTask = [[NSTask alloc] init];
    NSPipe *outputPipe = [NSPipe pipe];
    NSPipe *errorPipe = [NSPipe pipe];
    [osascriptTask setLaunchPath:@"/usr/bin/osascript"];
    [osascriptTask setArguments:@[@"-e", script]];
    [osascriptTask setStandardOutput:outputPipe];
    [osascriptTask setStandardError:errorPipe];

    NSError *error = nil;
    if (![osascriptTask launchAndReturnError:&error]) {
        NSLog(@"Error executing %@ AppleScript: %@", context, error);
        return nil;
    }

    [osascriptTask waitUntilExit];

    if ([osascriptTask terminationStatus] != 0) {
        NSData *errorData = [[errorPipe fileHandleForReading] readDataToEndOfFile];
        NSString *errorOutput = [[NSString alloc] initWithData:errorData encoding:NSUTF8StringEncoding];
        NSLog(@"Error executing %@ AppleScript: %@", context, errorOutput);
        return nil;
    }

    NSData *outputData = [[outputPipe fileHandleForReading] readDataToEndOfFile];
    NSString *output = [[NSString alloc] initWithData:outputData encoding:NSUTF8StringEncoding];
    return [output stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

// tty 上只剩登录 shell 本身时认为该会话是干净的空 shell，可以安全关闭
- (BOOL)isBareShellOnTTY:(NSString *)ttyPath {
    NSString *tty = [ttyPath lastPathComponent];
    if ([tty length] == 0) {
        return NO;
    }

    NSTask *psTask = [[NSTask alloc] init];
    NSPipe *outputPipe = [NSPipe pipe];
    [psTask setLaunchPath:@"/bin/ps"];
    [psTask setArguments:@[@"-t", tty, @"-o", @"comm="]];
    [psTask setStandardOutput:outputPipe];

    NSError *error = nil;
    if (![psTask launchAndReturnError:&error]) {
        return NO;
    }
    [psTask waitUntilExit];

    NSData *outputData = [[outputPipe fileHandleForReading] readDataToEndOfFile];
    NSString *output = [[NSString alloc] initWithData:outputData encoding:NSUTF8StringEncoding];
    NSArray *lines = [output componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]];
    NSSet *shells = [NSSet setWithArray:@[@"login", @"zsh", @"bash", @"sh", @"fish", @"tcsh", @"csh", @"dash", @"ksh"]];

    BOOL sawProcess = NO;
    for (NSString *line in lines) {
        NSString *name = [[line stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]] lastPathComponent];
        if ([name length] == 0) {
            continue;
        }
        if ([name hasPrefix:@"-"]) {
            name = [name substringFromIndex:1];
        }
        if (![shells containsObject:name]) {
            return NO;
        }
        sawProcess = YES;
    }
    return sawProcess;
}

// iTerm 未运行时的处理：先让 iTerm 启动并等它自己的启动窗口/会话恢复完成，
// 再决定是直接建主题窗口，还是在启动窗口里建主题 tab。直接在脚本里 create window
// 会和 iTerm 自己的启动窗口叠加，出现两个窗口（旧 bug）。
- (void)coldStartITermWithProfile:(NSString *)profileCreation title:(NSString *)escapedTitle command:(NSString *)escapedCommand {
    // 整个冷启动流程放在一次 osascript 里完成（重复 spawn osascript 轮询太慢）：
    // activate 触发 iTerm 启动并等它自己的启动窗口出现；等不到（启动设置为不开窗口）
    // 就自己建主题窗口执行命令；等到了则只记录启动窗口的 tab 数和 tty 返回，
    // 由 ObjC 决定复用还是另开 tab
    NSString *script = [NSString stringWithFormat:
        @"tell application \"iTerm\"\n"
         "  activate\n"
         "  repeat 30 times\n"
         "    if (count of windows) > 0 then exit repeat\n"
         "    delay 0.1\n"
         "  end repeat\n"
         "  if (count of windows) = 0 then\n"
         "    try\n"
         "      create window with profile %@\n"
         "    on error\n"
         "      create window with default profile\n"
         "    end try\n"
         "    tell current session of current window\n"
         "      set name to \"%@\"\n"
         "      write text \"%@\"\n"
         "    end tell\n"
         "    return \"created|\"\n"
         "  end if\n"
         "  set w to current window\n"
         "  set ttyName to \"\"\n"
         "  try\n"
         "    set ttyName to (tty of current session of w)\n"
         "  end try\n"
         "  return ((count of tabs of w) as text) & \"|\" & ttyName\n"
         "end tell",
         profileCreation, escapedTitle, escapedCommand];

    NSString *result = [self stringFromOSAScript:script context:@"iTerm"];
    NSArray *parts = [result componentsSeparatedByString:@"|"];
    if ([parts count] != 2) {
        return;
    }

    // 启动窗口只有一个 tab 且是干净的空 shell 时直接复用它执行命令（不会多出 tab）。
    // 新 shell 启动后头一秒 rc 脚本的子进程（docker/python 等）还在 tty 上，
    // 等它安定下来再判断；一直安定不下来的是恢复的旧会话，不能动
    NSString *startupTTY = parts[1];
    BOOL reuseStartupTab = NO;
    if ([parts[0] integerValue] == 1 && [startupTTY length] > 0) {
        for (int attempt = 0; attempt < 10; attempt++) {
            if ([self isBareShellOnTTY:startupTTY]) {
                reuseStartupTab = YES;
                break;
            }
            usleep(200000);
        }
    }

    if (reuseStartupTab) {
        NSString *reuseScript = [NSString stringWithFormat:
            @"tell application \"iTerm\"\n"
             "  tell current window\n"
             "    repeat with t in tabs\n"
             "      repeat with s in sessions of t\n"
             "        if tty of s is \"%@\" then\n"
             "          tell s\n"
             "            set name to \"%@\"\n"
             "            write text \"%@\"\n"
             "          end tell\n"
             "          return\n"
             "        end if\n"
             "      end repeat\n"
             "    end repeat\n"
             "  end tell\n"
             "end tell",
             startupTTY, escapedTitle, escapedCommand];
        [self runOSAScript:reuseScript context:@"iTerm"];
        return;
    }

    // 启动窗口被恢复的旧会话占用（或有多个 tab）：另开主题 tab，不动旧会话
    NSString *tabScript = [NSString stringWithFormat:
        @"tell application \"iTerm\"\n"
         "  tell current window\n"
         "    try\n"
         "      create tab with profile %@\n"
         "    on error\n"
         "      create tab with default profile\n"
         "    end try\n"
         "  end tell\n"
         "  tell current session of current window\n"
         "    set name to \"%@\"\n"
         "    write text \"%@\"\n"
         "  end tell\n"
         "end tell",
         profileCreation, escapedTitle, escapedCommand];
    [self runOSAScript:tabScript context:@"iTerm"];
}

- (void)executeInITermDirectly:(NSString *)command windowMode:(WindowMode)windowMode theme:(NSString *)theme title:(NSString *)title {
    NSString *escapedCommand = [self escapeString:command];
    NSString *escapedTheme = [self escapeString:theme ?: @"Default"];
    NSString *escapedTitle = [self escapeString:title ?: @"Shuttle"];
    NSString *profileCreation = [NSString stringWithFormat:@"\"%@\"", escapedTheme];

    BOOL wasRunning = [[NSRunningApplication runningApplicationsWithBundleIdentifier:@"com.googlecode.iterm2"] count] > 0;
    if (!wasRunning) {
        // 冷启动时窗口/tab 模式没有区别：都只需要得到一个带命令的会话
        [self coldStartITermWithProfile:profileCreation title:escapedTitle command:escapedCommand];
        return;
    }

    NSString *osascriptCommand = nil;

    if (windowMode == WindowModeNew) {
        osascriptCommand = [NSString stringWithFormat:
            @"tell application \"iTerm\"\n"
             "  try\n"
             "    create window with profile %@\n"
             "  on error\n"
             "    create window with default profile\n"
             "  end try\n"
             "  tell current session of current window\n"
             "    set name to \"%@\"\n"
             "    write text \"%@\"\n"
             "  end tell\n"
             "  activate\n"
             "end tell",
             profileCreation, escapedTitle, escapedCommand];
    } else if (windowMode == WindowModeTab) {
        osascriptCommand = [NSString stringWithFormat:
            @"tell application \"iTerm\"\n"
             "  if (count of windows) = 0 then\n"
             "    try\n"
             "      create window with profile %@\n"
             "    on error\n"
             "      create window with default profile\n"
             "    end try\n"
             "  else\n"
             "    tell current window\n"
             "      try\n"
             "        create tab with profile %@\n"
             "      on error\n"
             "        create tab with default profile\n"
             "      end try\n"
             "    end tell\n"
             "  end if\n"
             "  tell current session of current window\n"
             "    set name to \"%@\"\n"
             "    write text \"%@\"\n"
             "  end tell\n"
             "  activate\n"
             "end tell",
             profileCreation, profileCreation, escapedTitle, escapedCommand];
    } else {
        osascriptCommand = [NSString stringWithFormat:
            @"tell application \"iTerm\"\n"
             "  if (count of windows) = 0 then\n"
             "    try\n"
             "      create window with profile %@\n"
             "    on error\n"
             "      create window with default profile\n"
             "    end try\n"
             "  end if\n"
             "  tell current session of current window\n"
             "    write text \"%@\"\n"
             "  end tell\n"
             "  activate\n"
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
