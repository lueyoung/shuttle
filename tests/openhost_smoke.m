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
    }

    return 0;
}
