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

// Mirrors the status menu in MainMenu.xib: separator, Settings, About, Quit.
static NSMenu *MakeStatusMenu(void) {
    NSMenu *menu = [[NSMenu alloc] initWithTitle:@""];
    [menu addItem:[NSMenuItem separatorItem]];
    [menu addItemWithTitle:@"Settings" action:nil keyEquivalent:@""];
    [menu addItemWithTitle:@"About" action:nil keyEquivalent:@""];
    [menu addItemWithTitle:@"Quit" action:nil keyEquivalent:@""];
    return menu;
}

static AppDelegate *MakeDelegate(NSString *configPath, NSMenu *menu, FakeLaunchAtLoginController *launchAtLogin) {
    AppDelegate *delegate = [[AppDelegate alloc] init];
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
