#import <Cocoa/Cocoa.h>
#import "AppDelegate.h"

@interface AppDelegate (OpenHostSmokeTest)
- (NSString *)legacyMenuRepresentedObjectWithCommand:(NSString *)command
                                               theme:(NSString *)theme
                                               title:(NSString *)title
                                              window:(NSString *)window
                                                name:(NSString *)name;
- (NSArray *)legacyMenuComponentsFromRepresentedObject:(id)representedObject;
- (NSArray *)dictionaryMenuComponentsFromRepresentedObject:(id)representedObject;
- (NSArray *)menuComponentsFromRepresentedObject:(id)representedObject;
- (void)buildMenu:(NSArray *)data addToMenu:(NSMenu *)menu;
- (void)openHost:(NSMenuItem *)sender;
@end

static int RunOpenHostSmoke(AppDelegate *delegate, id representedObject, NSString *title) {
    NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:title
                                                  action:@selector(openHost:)
                                           keyEquivalent:@""];
    [item setRepresentedObject:representedObject];
    [delegate openHost:item];
    return 0;
}

int main(void) {
    @autoreleasepool {
        AppDelegate *delegate = [[AppDelegate alloc] init];
        [delegate setValue:@"terminal.app" forKey:@"terminalPref"];
        [delegate setValue:@"tab" forKey:@"openInPref"];

        NSString *legacyRepresentedObject = [delegate legacyMenuRepresentedObjectWithCommand:@"echo shuttle-openhost-smoke-legacy"
                                                                                      theme:nil
                                                                                      title:nil
                                                                                     window:nil
                                                                                       name:@"Smoke"];
        NSArray *legacyComponents = [delegate legacyMenuComponentsFromRepresentedObject:legacyRepresentedObject];
        if ([legacyComponents count] < 5) {
            NSLog(@"legacy representedObject did not parse into five components");
            return 2;
        }
        RunOpenHostSmoke(delegate, legacyRepresentedObject, @"Smoke Legacy");

        NSDictionary *dictionaryRepresentedObject = @{
            @"cmd": @"echo shuttle-openhost-smoke-dictionary",
            @"name": @"Smoke Dictionary",
            @"inTerminal": @"new"
        };
        NSArray *dictionaryComponents = [delegate dictionaryMenuComponentsFromRepresentedObject:dictionaryRepresentedObject];
        if ([dictionaryComponents count] < 5) {
            NSLog(@"dictionary representedObject did not parse into five components");
            return 3;
        }
        RunOpenHostSmoke(delegate, dictionaryRepresentedObject, @"Smoke Dictionary");

        NSMenu *menu = [[NSMenu alloc] initWithTitle:@"Smoke Menu"];
        NSArray *menuData = @[
            @{
                @"name": @"[aaa]Smoke Built",
                @"cmd": @"echo shuttle-openhost-smoke-built",
                @"title": @"Built Smoke",
                @"inTerminal": @"new"
            }
        ];
        [delegate buildMenu:menuData addToMenu:menu];

        NSMenuItem *builtItem = [menu itemWithTitle:@"Smoke Built"];
        if (!builtItem) {
            NSLog(@"buildMenu did not create the expected menu item");
            return 4;
        }
        if (![[builtItem representedObject] isKindOfClass:[NSDictionary class]]) {
            NSLog(@"buildMenu did not use dictionary representedObject");
            return 5;
        }
        NSArray *builtComponents = [delegate menuComponentsFromRepresentedObject:[builtItem representedObject]];
        if ([builtComponents count] < 5 || ![builtComponents[0] isEqualToString:@"echo shuttle-openhost-smoke-built"]) {
            NSLog(@"buildMenu representedObject did not parse into the expected command");
            return 6;
        }
        RunOpenHostSmoke(delegate, [builtItem representedObject], [builtItem title]);

        [delegate setValue:@" Virtual " forKey:@"openInPref"];
        NSDictionary *globalWindowRepresentedObject = @{
            @"cmd": @"echo shuttle-openhost-smoke-global-window",
            @"name": @"Smoke Global Window"
        };
        RunOpenHostSmoke(delegate, globalWindowRepresentedObject, @"Smoke Global Window");
    }

    return 0;
}
