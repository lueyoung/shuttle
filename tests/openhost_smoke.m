#import <Cocoa/Cocoa.h>
#import "AppDelegate.h"

@interface AppDelegate (OpenHostSmokeTest)
- (NSString *)legacyMenuRepresentedObjectWithCommand:(NSString *)command
                                               theme:(NSString *)theme
                                               title:(NSString *)title
                                              window:(NSString *)window
                                                name:(NSString *)name;
- (NSArray *)legacyMenuComponentsFromRepresentedObject:(id)representedObject;
- (void)openHost:(NSMenuItem *)sender;
@end

int main(void) {
    @autoreleasepool {
        AppDelegate *delegate = [[AppDelegate alloc] init];
        [delegate setValue:@"terminal.app" forKey:@"terminalPref"];
        [delegate setValue:@"tab" forKey:@"openInPref"];

        NSString *representedObject = [delegate legacyMenuRepresentedObjectWithCommand:@"echo shuttle-openhost-smoke"
                                                                                 theme:nil
                                                                                 title:nil
                                                                                window:nil
                                                                                  name:@"Smoke"];
        NSArray *components = [delegate legacyMenuComponentsFromRepresentedObject:representedObject];
        if ([components count] < 5) {
            NSLog(@"legacy representedObject did not parse into five components");
            return 2;
        }

        NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:@"Smoke"
                                                      action:@selector(openHost:)
                                               keyEquivalent:@""];
        [item setRepresentedObject:representedObject];
        [delegate openHost:item];
    }

    return 0;
}
