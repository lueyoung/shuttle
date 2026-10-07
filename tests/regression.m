//
//  regression.m
//  Shuttle
//
//  Regression cases for config loading, ssh_config parsing and menu building.
//  Built and run by tests/test_regression.py:
//    regression --list    print the case names
//    regression <case>    run one case (no argument runs every case)
//

#import <Cocoa/Cocoa.h>
#import "AppDelegate.h"

@interface AppDelegate (RegressionTest)
- (void)buildMenu:(NSArray *)data addToMenu:(NSMenu *)menu;
- (NSDictionary *)parseSSHConfig:(NSString *)filepath;
- (NSArray<NSString *> *)defaultSSHConfigFiles;
@end

// Reads ssh config from the files a case provides instead of the real ones on this machine.
@interface RegressionAppDelegate : AppDelegate
@property (nonatomic, copy) NSArray<NSString *> *sshConfigFiles;
@end

@implementation RegressionAppDelegate
- (NSArray<NSString *> *)defaultSSHConfigFiles {
    return self.sshConfigFiles ?: @[];
}
@end

// Stands in for LaunchAtLoginController so the cases never touch SMAppService.
@interface FakeLaunchAtLoginController : NSObject
@property (nonatomic) BOOL launchAtLogin;
@property (nonatomic, readonly) NSInteger setCount;
@end

@implementation FakeLaunchAtLoginController
- (void)setLaunchAtLogin:(BOOL)launchAtLogin {
    _launchAtLogin = launchAtLogin;
    _setCount++;
}
@end

static const NSUInteger StaticMenuItemCount = 4;
static NSMutableArray<NSString *> *failures;
static NSMutableArray<NSString *> *temporaryDirectories;

#define EXPECT(condition, ...) do { \
    if (!(condition)) { \
        [failures addObject:[NSString stringWithFormat:@"line %d: %@", __LINE__, [NSString stringWithFormat:__VA_ARGS__]]]; \
    } \
} while (0)

static NSString *TestsDirectory(void) {
    return [[NSString stringWithUTF8String:__FILE__] stringByDeletingLastPathComponent];
}

static NSString *MakeTemporaryDirectory(void) {
    NSString *name = [@"shuttle-regression-" stringByAppendingString:[[NSUUID UUID] UUIDString]];
    NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:name];
    [[NSFileManager defaultManager] createDirectoryAtPath:path withIntermediateDirectories:YES attributes:nil error:NULL];
    [temporaryDirectories addObject:path];
    return path;
}

static NSString *WriteFile(NSString *directory, NSString *name, NSString *contents) {
    NSString *path = [directory stringByAppendingPathComponent:name];
    [contents writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:NULL];
    return path;
}

// Moves a file's modification date so a rewrite is always seen as newer.
static void SetModificationDate(NSString *path, NSTimeInterval secondsFromNow) {
    NSDictionary *attributes = @{NSFileModificationDate: [NSDate dateWithTimeIntervalSinceNow:secondsFromNow]};
    [[NSFileManager defaultManager] setAttributes:attributes ofItemAtPath:path error:NULL];
}

// Mirrors the status menu in MainMenu.xib: separator, Settings, About, Quit.
static NSMenu *MakeStatusMenu(void) {
    NSMenu *menu = [[NSMenu alloc] initWithTitle:@""];
    [menu addItem:[NSMenuItem separatorItem]];
    [menu addItemWithTitle:@"Settings" action:nil keyEquivalent:@""];
    [menu addItemWithTitle:@"About" action:nil keyEquivalent:@""];
    [menu addItemWithTitle:@"Quit" action:nil keyEquivalent:@""];
    return menu;
}

static RegressionAppDelegate *MakeDelegate(NSString *configPath, NSMenu *menu, FakeLaunchAtLoginController *launchAtLogin) {
    RegressionAppDelegate *delegate = [[RegressionAppDelegate alloc] init];
    [delegate setValue:menu forKey:@"menu"];
    [delegate setValue:configPath forKey:@"shuttleConfigFile"];
    [delegate setValue:[configPath stringByAppendingString:@".missing-alt"] forKey:@"shuttleAltConfigFile"];
    [delegate setValue:@NO forKey:@"parseAltJSON"];
    [delegate setValue:launchAtLogin forKey:@"launchAtLoginController"];
    return delegate;
}

// Item titles, with separators written as "---".
static NSArray<NSString *> *Titles(NSArray<NSMenuItem *> *items) {
    NSMutableArray *titles = [NSMutableArray array];
    for (NSMenuItem *item in items) {
        [titles addObject:[item isSeparatorItem] ? @"---" : [item title]];
    }
    return titles;
}

// Titles of the items loadMenu added in front of the static status menu items.
static NSArray<NSString *> *DynamicTitles(NSMenu *menu) {
    NSArray *items = [menu itemArray];
    NSUInteger dynamicCount = [items count] > StaticMenuItemCount ? [items count] - StaticMenuItemCount : 0;
    return Titles([items subarrayWithRange:NSMakeRange(0, dynamicCount)]);
}

#pragma mark - Cases

static void SSHConfigFixtureParsesIncludeAndShuttleNames(void) {
    AppDelegate *delegate = [[AppDelegate alloc] init];
    NSDictionary *servers = [delegate parseSSHConfig:[TestsDirectory() stringByAppendingPathComponent:@".ssh/config"]];

    EXPECT(servers[@"included.example.com"] != nil, @"host from the Include directive is missing: %@", [servers allKeys]);
    EXPECT([servers[@"dev01.example.net"][@"name"] isEqualToString:@"Work/dev01.example.net (my dev box)"],
           @"unexpected shuttle.name for dev01: %@", servers[@"dev01.example.net"]);
    EXPECT([servers[@"test02.example.net"][@"name"] isEqualToString:@"Work/Production/test02.example.net (database)"],
           @"unexpected shuttle.name for test02: %@", servers[@"test02.example.net"]);
}

static void BuildMenuOrdersGroupsSortPrefixesAndSeparators(void) {
    NSArray *data = @[
        @{@"name": @"[bbb]Second", @"cmd": @"echo second"},
        @{@"name": @"[aaa]First[---]", @"cmd": @"echo first"},
        @{@"Group": @[@{@"name": @"Inner", @"cmd": @"echo inner"}]}
    ];
    NSMenu *menu = [[NSMenu alloc] initWithTitle:@""];
    [[[AppDelegate alloc] init] buildMenu:data addToMenu:menu];

    NSArray *titles = Titles([menu itemArray]);
    EXPECT([titles isEqualToArray:(@[@"Group", @"First", @"---", @"Second"])], @"unexpected menu order: %@", titles);

    NSArray *groupTitles = Titles([[[menu itemWithTitle:@"Group"] submenu] itemArray]);
    EXPECT([groupTitles isEqualToArray:@[@"Inner"]], @"unexpected group contents: %@", groupTitles);

    NSMenuItem *first = [menu itemWithTitle:@"First"];
    EXPECT([first action] == @selector(openHost:), @"leaf item does not trigger openHost:");
    EXPECT([[first representedObject][@"cmd"] isEqualToString:@"echo first"],
           @"unexpected represented object: %@", [first representedObject]);
}

static void MenuLoadsHostsFromConfig(void) {
    NSString *config = WriteFile(MakeTemporaryDirectory(), @"shuttle.json",
                                 @"{\"show_ssh_config_hosts\": false, \"hosts\": ["
                                  "{\"name\": \"Alpha\", \"cmd\": \"echo alpha\"},"
                                  "{\"Group\": [{\"name\": \"Beta\", \"cmd\": \"echo beta\"}]}]}");
    NSMenu *menu = MakeStatusMenu();
    AppDelegate *delegate = MakeDelegate(config, menu, [[FakeLaunchAtLoginController alloc] init]);

    [delegate menuWillOpen:menu];

    NSArray *titles = DynamicTitles(menu);
    EXPECT([titles isEqualToArray:(@[@"Group", @"Alpha"])], @"unexpected hosts: %@", titles);
    EXPECT([menu numberOfItems] == (NSInteger)StaticMenuItemCount + 2, @"static items changed: %@", Titles([menu itemArray]));
}

static void MissingConfigShowsErrorItem(void) {
    NSString *config = [MakeTemporaryDirectory() stringByAppendingPathComponent:@"does-not-exist.json"];
    NSMenu *menu = MakeStatusMenu();
    AppDelegate *delegate = MakeDelegate(config, menu, [[FakeLaunchAtLoginController alloc] init]);

    [delegate menuWillOpen:menu];

    NSArray *titles = DynamicTitles(menu);
    EXPECT([titles isEqualToArray:@[@"Error parsing config"]], @"missing config shows %@", titles);
}

static void InvalidConfigShowsErrorItem(void) {
    NSString *directory = MakeTemporaryDirectory();
    NSDictionary *configs = @{
        @"not JSON": WriteFile(directory, @"broken.json", @"{\"hosts\": ["),
        @"array root": WriteFile(directory, @"array.json", @"[]")
    };

    for (NSString *label in configs) {
        NSMenu *menu = MakeStatusMenu();
        AppDelegate *delegate = MakeDelegate(configs[label], menu, [[FakeLaunchAtLoginController alloc] init]);

        [delegate menuWillOpen:menu];

        NSArray *titles = DynamicTitles(menu);
        EXPECT([titles isEqualToArray:@[@"Error parsing config"]], @"%@ config shows %@", label, titles);
    }
}

static void MenuIsNotRebuiltWhenNothingChanged(void) {
    NSString *directory = MakeTemporaryDirectory();
    NSString *sshConfig = WriteFile(directory, @"ssh_config", @"Host fixture-host\n  HostName example.com\n");

    for (NSString *showSSHHosts in @[@"false", @"true"]) {
        NSString *json = [NSString stringWithFormat:@"{\"show_ssh_config_hosts\": %@, \"hosts\": "
                          "[{\"name\": \"Alpha\", \"cmd\": \"echo alpha\"}]}", showSSHHosts];
        NSString *config = WriteFile(directory, @"shuttle.json", json);
        NSMenu *menu = MakeStatusMenu();
        FakeLaunchAtLoginController *launchAtLogin = [[FakeLaunchAtLoginController alloc] init];
        RegressionAppDelegate *delegate = MakeDelegate(config, menu, launchAtLogin);
        delegate.sshConfigFiles = @[sshConfig];

        [delegate menuWillOpen:menu];
        NSMenuItem *firstItem = [menu itemAtIndex:0];
        [delegate menuWillOpen:menu];
        [delegate menuWillOpen:menu];

        EXPECT([menu itemAtIndex:0] == firstItem, @"menu rebuilt on every open (show_ssh_config_hosts=%@)", showSSHHosts);
        EXPECT(launchAtLogin.setCount == 0, @"launch at login set %ld times although it never changed (show_ssh_config_hosts=%@)",
               (long)launchAtLogin.setCount, showSSHHosts);
    }
}

static void SSHConfigChangeRebuildsMenu(void) {
    NSString *directory = MakeTemporaryDirectory();
    NSString *sshConfig = WriteFile(directory, @"ssh_config", @"Host first-host\n");
    NSString *config = WriteFile(directory, @"shuttle.json", @"{\"show_ssh_config_hosts\": true, \"hosts\": []}");
    NSMenu *menu = MakeStatusMenu();
    RegressionAppDelegate *delegate = MakeDelegate(config, menu, [[FakeLaunchAtLoginController alloc] init]);
    delegate.sshConfigFiles = @[sshConfig];

    [delegate menuWillOpen:menu];
    EXPECT([DynamicTitles(menu) isEqualToArray:@[@"first-host"]], @"unexpected ssh hosts: %@", DynamicTitles(menu));

    WriteFile(directory, @"ssh_config", @"Host second-host\n");
    SetModificationDate(sshConfig, 10);
    [delegate menuWillOpen:menu];
    EXPECT([DynamicTitles(menu) isEqualToArray:@[@"second-host"]], @"ssh config change not picked up: %@", DynamicTitles(menu));
}

static void LaunchAtLoginAppliedOnlyWhenChanged(void) {
    NSString *directory = MakeTemporaryDirectory();
    NSString *enabled = @"{\"launch_at_login\": true, \"show_ssh_config_hosts\": false, \"hosts\": []}";
    NSString *config = WriteFile(directory, @"shuttle.json", enabled);
    NSMenu *menu = MakeStatusMenu();
    FakeLaunchAtLoginController *launchAtLogin = [[FakeLaunchAtLoginController alloc] init];
    RegressionAppDelegate *delegate = MakeDelegate(config, menu, launchAtLogin);

    [delegate menuWillOpen:menu];
    EXPECT(launchAtLogin.launchAtLogin && launchAtLogin.setCount == 1, @"launch at login not enabled once (set %ld times)",
           (long)launchAtLogin.setCount);

    WriteFile(directory, @"shuttle.json", enabled);
    SetModificationDate(config, 10);
    [delegate menuWillOpen:menu];
    EXPECT(launchAtLogin.setCount == 1, @"unchanged launch_at_login applied again (set %ld times)", (long)launchAtLogin.setCount);

    WriteFile(directory, @"shuttle.json", @"{\"launch_at_login\": false, \"show_ssh_config_hosts\": false, \"hosts\": []}");
    SetModificationDate(config, 20);
    [delegate menuWillOpen:menu];
    EXPECT(!launchAtLogin.launchAtLogin && launchAtLogin.setCount == 2, @"launch at login not disabled (set %ld times)",
           (long)launchAtLogin.setCount);
}

static void DeletedConfigShowsErrorItem(void) {
    NSString *config = WriteFile(MakeTemporaryDirectory(), @"shuttle.json",
                                 @"{\"show_ssh_config_hosts\": false, \"hosts\": [{\"name\": \"Alpha\", \"cmd\": \"echo alpha\"}]}");
    NSMenu *menu = MakeStatusMenu();
    RegressionAppDelegate *delegate = MakeDelegate(config, menu, [[FakeLaunchAtLoginController alloc] init]);

    [delegate menuWillOpen:menu];
    EXPECT([DynamicTitles(menu) isEqualToArray:@[@"Alpha"]], @"unexpected hosts: %@", DynamicTitles(menu));

    [[NSFileManager defaultManager] removeItemAtPath:config error:NULL];
    [delegate menuWillOpen:menu];
    EXPECT([DynamicTitles(menu) isEqualToArray:@[@"Error parsing config"]], @"deleted config shows %@", DynamicTitles(menu));
}

static void BooleanSettingsTolerateWrongTypes(void) {
    NSString *directory = MakeTemporaryDirectory();
    NSString *sshConfig = WriteFile(directory, @"ssh_config", @"Host ssh-host\n");
    // JSON value used for both launch_at_login and show_ssh_config_hosts, then the expected
    // launch_at_login and show_ssh_config_hosts. An empty value leaves both keys out.
    NSArray *rows = @[
        @[@"", @NO, @YES],
        @[@"null", @NO, @YES],
        @[@"[]", @NO, @YES],
        @[@"{}", @NO, @YES],
        @[@"true", @YES, @YES],
        @[@"false", @NO, @NO],
        @[@"\"true\"", @YES, @YES],
        @[@"\"false\"", @NO, @NO]
    ];

    for (NSArray *row in rows) {
        NSString *value = row[0];
        NSString *label = [value length] > 0 ? value : @"(missing)";
        NSString *settings = [value length] > 0
            ? [NSString stringWithFormat:@"\"launch_at_login\": %@, \"show_ssh_config_hosts\": %@, ", value, value]
            : @"";
        NSString *json = [NSString stringWithFormat:@"{%@\"hosts\": [{\"name\": \"Alpha\", \"cmd\": \"echo alpha\"}]}", settings];
        NSString *config = WriteFile(directory, @"shuttle.json", json);
        NSMenu *menu = MakeStatusMenu();
        FakeLaunchAtLoginController *launchAtLogin = [[FakeLaunchAtLoginController alloc] init];
        RegressionAppDelegate *delegate = MakeDelegate(config, menu, launchAtLogin);
        delegate.sshConfigFiles = @[sshConfig];

        @try {
            [delegate menuWillOpen:menu];
        } @catch (NSException *exception) {
            EXPECT(NO, @"%@ raised %@", label, [exception reason]);
            continue;
        }

        NSArray *titles = DynamicTitles(menu);
        EXPECT([titles containsObject:@"Alpha"], @"%@: hosts missing: %@", label, titles);
        EXPECT(launchAtLogin.launchAtLogin == [row[1] boolValue], @"%@: launch_at_login became %d", label, launchAtLogin.launchAtLogin);
        EXPECT([titles containsObject:@"ssh-host"] == [row[2] boolValue], @"%@: ssh hosts shown = %d", label,
               [titles containsObject:@"ssh-host"]);
    }
}

static void SSHConfigHostWithoutAliasIsSkipped(void) {
    NSString *sshConfig = WriteFile(MakeTemporaryDirectory(), @"ssh_config",
                                    @"Host real-host\n"
                                     "  # shuttle.name = Real Host\n"
                                     "Host =\n"
                                     "  # shuttle.name = Should Not Apply\n"
                                     "Host=\n"
                                     "Host other-host\n");
    AppDelegate *delegate = [[AppDelegate alloc] init];
    NSDictionary *servers = nil;

    @try {
        servers = [delegate parseSSHConfig:sshConfig];
    } @catch (NSException *exception) {
        EXPECT(NO, @"parsing raised %@", [exception reason]);
        return;
    }

    NSArray *hosts = [[servers allKeys] sortedArrayUsingSelector:@selector(compare:)];
    EXPECT([hosts isEqualToArray:(@[@"other-host", @"real-host"])], @"unexpected hosts: %@", hosts);
    EXPECT([servers[@"real-host"][@"name"] isEqualToString:@"Real Host"],
           @"shuttle.name after an empty Host leaked into the previous host: %@", servers[@"real-host"]);
}

static void SSHConfigHostPatternsAreNotShown(void) {
    NSString *directory = MakeTemporaryDirectory();
    NSString *sshConfig = WriteFile(directory, @"ssh_config",
                                    @"Host web?\n"
                                     "Host !bastion jump\n"
                                     "Host *.example.com\n"
                                     "Host *.corp\n"
                                     "  # shuttle.name = Corp\n"
                                     "Host real-host\n");
    NSString *config = WriteFile(directory, @"shuttle.json", @"{\"show_ssh_config_hosts\": true, \"hosts\": []}");
    NSMenu *menu = MakeStatusMenu();
    RegressionAppDelegate *delegate = MakeDelegate(config, menu, [[FakeLaunchAtLoginController alloc] init]);
    delegate.sshConfigFiles = @[sshConfig];

    [delegate menuWillOpen:menu];

    NSArray *titles = DynamicTitles(menu);
    EXPECT([titles isEqualToArray:@[@"real-host"]], @"host patterns shown as hosts: %@", titles);
}

#pragma mark - Runner

typedef struct {
    const char *name;
    void (*run)(void);
} RegressionCase;

static const RegressionCase cases[] = {
    {"ssh_config_fixture_parses_include_and_shuttle_names", SSHConfigFixtureParsesIncludeAndShuttleNames},
    {"build_menu_orders_groups_sort_prefixes_and_separators", BuildMenuOrdersGroupsSortPrefixesAndSeparators},
    {"menu_loads_hosts_from_config", MenuLoadsHostsFromConfig},
    {"missing_config_shows_error_item", MissingConfigShowsErrorItem},
    {"invalid_config_shows_error_item", InvalidConfigShowsErrorItem},
    {"menu_is_not_rebuilt_when_nothing_changed", MenuIsNotRebuiltWhenNothingChanged},
    {"ssh_config_change_rebuilds_menu", SSHConfigChangeRebuildsMenu},
    {"launch_at_login_applied_only_when_changed", LaunchAtLoginAppliedOnlyWhenChanged},
    {"deleted_config_shows_error_item", DeletedConfigShowsErrorItem},
    {"boolean_settings_tolerate_wrong_types", BooleanSettingsTolerateWrongTypes},
    {"ssh_config_host_without_alias_is_skipped", SSHConfigHostWithoutAliasIsSkipped},
    {"ssh_config_host_patterns_are_not_shown", SSHConfigHostPatternsAreNotShown},
};

static BOOL RunCase(RegressionCase regressionCase) {
    failures = [NSMutableArray array];
    @autoreleasepool {
        @try {
            regressionCase.run();
        } @catch (NSException *exception) {
            [failures addObject:[NSString stringWithFormat:@"uncaught %@: %@", [exception name], [exception reason]]];
        }
    }

    for (NSString *failure in failures) {
        printf("FAIL %s %s\n", regressionCase.name, [failure UTF8String]);
    }
    if ([failures count] == 0) {
        printf("ok   %s\n", regressionCase.name);
    }
    return [failures count] == 0;
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        size_t caseCount = sizeof(cases) / sizeof(cases[0]);
        if (argc > 1 && strcmp(argv[1], "--list") == 0) {
            for (size_t i = 0; i < caseCount; i++) {
                printf("%s\n", cases[i].name);
            }
            return 0;
        }

        temporaryDirectories = [NSMutableArray array];
        BOOL matched = NO;
        BOOL passed = YES;
        for (size_t i = 0; i < caseCount; i++) {
            if (argc > 1 && strcmp(argv[1], cases[i].name) != 0) {
                continue;
            }
            matched = YES;
            passed = RunCase(cases[i]) && passed;
        }

        for (NSString *directory in temporaryDirectories) {
            [[NSFileManager defaultManager] removeItemAtPath:directory error:NULL];
        }

        if (!matched) {
            fprintf(stderr, "unknown case: %s\n", argv[1]);
            return 2;
        }
        return passed ? 0 : 1;
    }
}
