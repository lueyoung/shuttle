//
//  AppDelegate.m
//  Shuttle
//

#import "AppDelegate.h"
#import "AboutWindowController.h"
#import "TerminalManager.h"
#import <glob.h>

static NSString *const ShuttleLegacyMenuSeparator = @"¬_¬";
static NSString *const ShuttleOpenHostDryRunEnvironmentKey = @"SHUTTLE_OPENHOST_DRY_RUN";

@implementation AppDelegate

- (void) awakeFromNib {

    // The location for the JSON path file. This is a simple file that contains the hard path to the *.json settings file.
    shuttleJSONPathPref = [NSHomeDirectory() stringByAppendingPathComponent:@".shuttle.path"];
    shuttleJSONPathAlt = [NSHomeDirectory() stringByAppendingPathComponent:@".shuttle-alt.path"];

    //if file shuttle.path exists in ~/.shuttle.path then read this file as it should contain the custom path to *.json
    if( [[NSFileManager defaultManager] fileExistsAtPath:shuttleJSONPathPref] ) {

        //Read the shuttle.path file which contains the path to the json file
        NSString *jsonConfigPath = [NSString stringWithContentsOfFile:shuttleJSONPathPref encoding:NSUTF8StringEncoding error:NULL];

        //Remove the white space if any.
        jsonConfigPath = [ jsonConfigPath stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];

        shuttleConfigFile = jsonConfigPath;
    }else{
        // The path for the configuration file (by default: ~/.shuttle.json)
        shuttleConfigFile = [NSHomeDirectory() stringByAppendingPathComponent:@".shuttle.json"];

        // if the config file does not exist, create a default one
        if ( ![[NSFileManager defaultManager] fileExistsAtPath:shuttleConfigFile] ) {
            NSString *cgFileInResource = [[NSBundle mainBundle] pathForResource:@"shuttle.default" ofType:@"json"];
            NSError *copyError = nil;
            if (cgFileInResource && ![[NSFileManager defaultManager] copyItemAtPath:cgFileInResource toPath:shuttleConfigFile error:&copyError]) {
                NSLog(@"Could not create default config %@: %@", shuttleConfigFile, copyError);
            }
        }
    }

    // if the custom alternate json file exists then read the file and use set the output as the alt path.
    if ( [[NSFileManager defaultManager] fileExistsAtPath:shuttleJSONPathAlt] ) {

        //Read shuttle-alt.path file which contains the custom path to the alternate json file
        NSString *jsonConfigAltPath = [NSString stringWithContentsOfFile:shuttleJSONPathAlt encoding:NSUTF8StringEncoding error:NULL];

        //Remove whitespace if any
        jsonConfigAltPath = [ jsonConfigAltPath stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];

        //set the global var that contains the alternate path
        shuttleAltConfigFile = jsonConfigAltPath;

        //flag the bool for later parsing
        parseAltJSON = YES;
    }else{
        //the custom alt path does not exist. Assume the default for alt path; if existing flag for later parsing
        shuttleAltConfigFile = [NSHomeDirectory() stringByAppendingPathComponent:@".shuttle-alt.json"];

        if ( [[NSFileManager defaultManager] fileExistsAtPath:shuttleAltConfigFile] ){
            //the default path exists. Flag for later parsing
            parseAltJSON = YES;
        }else{
            //The user does not want to parse an additional json file.
            parseAltJSON = NO;
        }
    }

    // Define Icons
    //only regular icon is needed for 10.10 and higher. OS X changes the icon for us.
    regularIcon = [NSImage imageNamed:@"StatusIcon"];
    altIcon = [NSImage imageNamed:@"StatusIconAlt"];

    // Create the status bar item
    statusItem = [[NSStatusBar systemStatusBar] statusItemWithLength:NSSquareStatusItemLength];
    [statusItem setMenu:menu];
    if (statusItem.button) {
        statusItem.button.image = regularIcon;
    }

    // Check for AppKit Version, add support for darkmode if > 10.9
    BOOL oldAppKitVersion = (floor(NSAppKitVersionNumber) <= 1265);

    // 10.10 or higher, dont load the alt image let OS X style it.
    if (!oldAppKitVersion)
    {
        regularIcon.template = YES;
    }
    // Load the alt image for OS X < 10.10
    else{
        if (statusItem.button) {
            statusItem.button.alternateImage = altIcon;
        }
    }

    launchAtLoginController = [[LaunchAtLoginController alloc] init];
    // Needed to trigger the menuWillOpen event
    [menu setDelegate:self];
}

- (BOOL) needUpdateFor: (NSString*) file with: (NSDate*) old {

    if (![[NSFileManager defaultManager] fileExistsAtPath:[file stringByExpandingTildeInPath]])
        return false;

    if (old == NULL)
        return true;

    NSDate *date = [self getMTimeFor:file];
    return [date compare: old] == NSOrderedDescending;
}

- (NSDate*) getMTimeFor: (NSString*) file {
    NSDictionary *attributes = [[NSFileManager defaultManager] attributesOfItemAtPath:[file stringByExpandingTildeInPath]
                                                                                error:nil];
    return [attributes fileModificationDate];
}

- (NSString *)stringValueForKey:(NSString *)key inDictionary:(NSDictionary *)dictionary defaultValue:(NSString *)defaultValue {
    id value = dictionary[key];
    return [value isKindOfClass:[NSString class]] ? [value lowercaseString] : defaultValue;
}

- (NSString *)legacyMenuRepresentedObjectWithCommand:(NSString *)command
                                               theme:(NSString *)theme
                                               title:(NSString *)title
                                              window:(NSString *)window
                                                name:(NSString *)name {
    return [NSString stringWithFormat:@"%@%@%@%@%@%@%@%@%@",
            command, ShuttleLegacyMenuSeparator,
            theme, ShuttleLegacyMenuSeparator,
            title, ShuttleLegacyMenuSeparator,
            window, ShuttleLegacyMenuSeparator,
            name];
}

- (NSArray *)legacyMenuComponentsFromRepresentedObject:(id)representedObject {
    if (![representedObject isKindOfClass:[NSString class]]) {
        return nil;
    }

    NSArray *components = [representedObject componentsSeparatedByString:ShuttleLegacyMenuSeparator];
    return ([components count] >= 5) ? components : nil;
}

- (NSString *)legacyMenuComponentValue:(id)value {
    return [value isKindOfClass:[NSString class]] ? value : @"(null)";
}

- (NSArray *)dictionaryMenuComponentsFromRepresentedObject:(id)representedObject {
    if (![representedObject isKindOfClass:[NSDictionary class]]) {
        return nil;
    }

    NSDictionary *dictionary = representedObject;
    id command = dictionary[@"cmd"];
    id name = dictionary[@"name"];
    if (![command isKindOfClass:[NSString class]] || ![name isKindOfClass:[NSString class]]) {
        return nil;
    }

    return @[
        [self legacyMenuComponentValue:command],
        [self legacyMenuComponentValue:dictionary[@"theme"]],
        [self legacyMenuComponentValue:dictionary[@"title"]],
        [self legacyMenuComponentValue:dictionary[@"inTerminal"]],
        [self legacyMenuComponentValue:name]
    ];
}

- (NSArray *)menuComponentsFromRepresentedObject:(id)representedObject {
    NSArray *legacyComponents = [self legacyMenuComponentsFromRepresentedObject:representedObject];
    if (legacyComponents) {
        return legacyComponents;
    }

    return [self dictionaryMenuComponentsFromRepresentedObject:representedObject];
}

- (BOOL)isOpenHostDryRunEnabled {
    NSString *value = [[[NSProcessInfo processInfo] environment] objectForKey:ShuttleOpenHostDryRunEnvironmentKey];
    return [value isEqualToString:@"1"];
}

- (NSMutableArray *)mutableStringArrayFromValue:(id)value {
    if (![value isKindOfClass:[NSArray class]]) {
        return [NSMutableArray array];
    }

    NSMutableArray *strings = [NSMutableArray array];
    for (id item in value) {
        if ([item isKindOfClass:[NSString class]]) {
            [strings addObject:item];
        }
    }

    return strings;
}

- (BOOL)loadJSONDictionaryAtPath:(NSString *)path into:(NSDictionary **)json error:(NSError **)error {
    NSData *data = [NSData dataWithContentsOfFile:path options:0 error:error];
    if (!data) {
        return NO;
    }

    id parsed = [NSJSONSerialization JSONObjectWithData:data
                                                options:NSJSONReadingMutableContainers
                                                  error:error];
    if (![parsed isKindOfClass:[NSDictionary class]]) {
        if (error) {
            *error = [NSError errorWithDomain:@"ShuttleConfigError"
                                         code:1
                                     userInfo:@{NSLocalizedDescriptionKey: @"Config root must be a JSON object"}];
        }
        return NO;
    }

    *json = parsed;
    return YES;
}

- (NSMutableArray *)validatedHostsFromJSON:(NSDictionary *)json sourceName:(NSString *)sourceName {
    id hosts = json[@"hosts"];
    if (!hosts) {
        return [NSMutableArray array];
    }

    if (![hosts isKindOfClass:[NSArray class]]) {
        NSLog(@"Ignoring %@ hosts because it is not an array", sourceName);
        return [NSMutableArray array];
    }

    return [hosts mutableCopy];
}

- (void)insertDisabledMenuItemWithTitle:(NSString *)title {
    NSMenuItem *menuItem = [menu insertItemWithTitle:title
                                             action:nil
                                      keyEquivalent:@""
                                            atIndex:0];
    [menuItem setEnabled:NO];
}

- (BOOL)sshConfigFilesNeedUpdate {
    NSArray *defaultConfigFiles = @[
        @"/etc/ssh_config",
        @"/etc/ssh/ssh_config",
        [@"~/.ssh/config" stringByExpandingTildeInPath]
    ];

    if (!sshConfigModifiedTimes) {
        for (NSString *file in defaultConfigFiles) {
            if ([[NSFileManager defaultManager] fileExistsAtPath:file]) {
                return YES;
            }
        }
        return NO;
    }

    NSMutableSet *filesToCheck = [NSMutableSet setWithArray:defaultConfigFiles];
    [filesToCheck addObjectsFromArray:[sshConfigModifiedTimes allKeys]];

    for (NSString *file in filesToCheck) {
        NSDate *oldDate = sshConfigModifiedTimes[file];
        BOOL existedBefore = (oldDate != nil);
        BOOL existsNow = [[NSFileManager defaultManager] fileExistsAtPath:file];

        if (existedBefore && !existsNow) {
            return YES;
        }

        if (existsNow && [self needUpdateFor:file with:oldDate]) {
            return YES;
        }
    }

    return NO;
}

- (void)menuWillOpen:(NSMenu *)menu {
    // Check when the config was last modified
    if ( [self needUpdateFor:shuttleConfigFile with:configModified] ||
        [self needUpdateFor:shuttleAltConfigFile with:configModified2] ||
        [self sshConfigFilesNeedUpdate]) {

        configModified = [self getMTimeFor:shuttleConfigFile];
        configModified2 = [self getMTimeFor:shuttleAltConfigFile];

        [self loadMenu];
    }
}

// Parsing of the SSH Config File
// Courtesy of https://gist.github.com/geeksunny/3376694
- (NSDictionary<NSString *, NSDictionary *> *)parseSSHConfigFile {

    NSFileManager *fileMgr = [[NSFileManager alloc] init];
    NSMutableDictionary<NSString *, NSDictionary *> *servers = [[NSMutableDictionary alloc] init];
    sshConfigModifiedTimes = [NSMutableDictionary dictionary];
    NSArray<NSString *> *configFiles = @[
        @"/etc/ssh_config",
        @"/etc/ssh/ssh_config",
        [@"~/.ssh/config" stringByExpandingTildeInPath]
    ];

    for (NSString *configFile in configFiles) {
        if (![fileMgr fileExistsAtPath:configFile]) {
            continue;
        }

        NSDictionary *parsedServers = [self parseSSHConfig:configFile visited:[NSMutableSet set]];
        if (parsedServers) {
            [servers addEntriesFromDictionary:parsedServers];
        }
    }

    if ([servers count] == 0) {
        // We did not find any config file so we gracefully die
        return nil;
    }

    return servers;
}

- (NSDictionary<NSString *, NSDictionary *> *)parseSSHConfig:(NSString *)filepath {
    return [self parseSSHConfig:filepath visited:[NSMutableSet set]];
}

- (NSArray<NSString *> *)splitSSHIncludePaths:(NSString *)includeValue {
    NSMutableArray *paths = [NSMutableArray array];
    NSCharacterSet *whitespace = [NSCharacterSet whitespaceAndNewlineCharacterSet];

    for (NSString *path in [includeValue componentsSeparatedByCharactersInSet:whitespace]) {
        NSString *trimmed = [path stringByTrimmingCharactersInSet:whitespace];
        if ([trimmed length] == 0) {
            continue;
        }

        if (([trimmed hasPrefix:@"\""] && [trimmed hasSuffix:@"\""]) ||
            ([trimmed hasPrefix:@"'"] && [trimmed hasSuffix:@"'"])) {
            trimmed = [trimmed substringWithRange:NSMakeRange(1, [trimmed length] - 2)];
        }

        [paths addObject:trimmed];
    }

    return paths;
}

- (NSArray<NSString *> *)expandedSSHIncludePaths:(NSString *)includeValue relativeToFile:(NSString *)filepath {
    NSMutableArray *paths = [NSMutableArray array];
    NSString *baseDirectory = [filepath stringByDeletingLastPathComponent];

    for (NSString *includePath in [self splitSSHIncludePaths:includeValue]) {
        NSString *expandedPath = [includePath stringByExpandingTildeInPath];
        if (![expandedPath isAbsolutePath]) {
            expandedPath = [[baseDirectory stringByAppendingPathComponent:includePath] stringByExpandingTildeInPath];
        }

        NSCharacterSet *globCharacters = [NSCharacterSet characterSetWithCharactersInString:@"*?["];
        if ([expandedPath rangeOfCharacterFromSet:globCharacters].location == NSNotFound) {
            [paths addObject:expandedPath];
            continue;
        }

        glob_t matches;
        memset(&matches, 0, sizeof(matches));
        int result = glob([expandedPath fileSystemRepresentation], 0, NULL, &matches);
        if (result == 0) {
            for (size_t i = 0; i < matches.gl_pathc; i++) {
                NSString *matchedPath = [NSString stringWithUTF8String:matches.gl_pathv[i]];
                if (matchedPath) {
                    [paths addObject:matchedPath];
                }
            }
        }
        globfree(&matches);
    }

    return paths;
}

- (NSDictionary<NSString *, NSDictionary *> *)parseSSHConfig:(NSString *)filepath visited:(NSMutableSet<NSString *> *)visited {
    filepath = [filepath stringByExpandingTildeInPath];
    NSString *canonicalPath = [[NSURL fileURLWithPath:filepath] path];

    if ([visited containsObject:canonicalPath]) {
        return @{};
    }
    [visited addObject:canonicalPath];

    if (![[NSFileManager defaultManager] fileExistsAtPath:canonicalPath]) {
        return @{};
    }

    NSDate *mtime = [self getMTimeFor:canonicalPath];
    if (mtime) {
        sshConfigModifiedTimes[canonicalPath] = mtime;
    }

    // Get file contents into fh.
    NSString *fh = [NSString stringWithContentsOfFile:canonicalPath encoding:NSUTF8StringEncoding error:nil];
    if (!fh) {
        return @{};
    }

    // build the regex for matching
    NSError* error = NULL;
    NSRegularExpression* rx = [NSRegularExpression regularExpressionWithPattern:@"^(#?)[ \\t]*([^ \\t=]+)[ \\t=]+(.*)$"
                                                                        options:0
                                                                          error:&error];

    // create data store
    NSMutableDictionary* servers = [[NSMutableDictionary alloc] init];
    NSString* key = nil;

    // Loop through each line and parse the file.
    for (NSString *line in [fh componentsSeparatedByString:@"\n"]) {

        // Strip line
        NSString *trimmed = [line stringByTrimmingCharactersInSet:[ NSCharacterSet whitespaceCharacterSet]];

        // run the regex against the line
        NSTextCheckingResult* matches = [rx firstMatchInString:trimmed
                                                       options:0
                                                         range:NSMakeRange(0, [trimmed length])];
        if ([matches numberOfRanges] != 4) {
            continue;
        }

        BOOL isComment = [[trimmed substringWithRange:[matches rangeAtIndex:1]] isEqualToString:@"#"];
        NSString* first = [trimmed substringWithRange:[matches rangeAtIndex:2]];
        NSString* second = [trimmed substringWithRange:[matches rangeAtIndex:3]];

        // check for special comment key/value pairs
        if (isComment && key && [first hasPrefix:@"shuttle."]) {
            servers[key][[first substringFromIndex:8]] = second;
        }

        // other comments must be skipped
        if (isComment) {
            continue;
        }

        NSString *directive = [first lowercaseString];
        if ([directive isEqualToString:@"include"]) {
            // Support for ssh_config Include directive.
            for (NSString *includePath in [self expandedSSHIncludePaths:second relativeToFile:canonicalPath]) {
                [servers addEntriesFromDictionary:[self parseSSHConfig:includePath visited:visited]];
            }
            continue;
        }

        if ([directive isEqualToString:@"host"]) {
            // a new host section

            // split multiple aliases on space and only save the first
            NSArray* hostAliases = [second componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
            hostAliases = [hostAliases filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"SELF != ''"]];
            key = [hostAliases firstObject];
            servers[key] = [[NSMutableDictionary alloc] init];
        }
    }

    return servers;
}


- (void) loadMenu {
    // Clear out the hosts so we can start over
    NSUInteger staticMenuItems = MIN((NSUInteger)4, [[menu itemArray] count]);
    while ([[menu itemArray] count] > staticMenuItems) {
        [menu removeItemAtIndex:0];
    }

    // Parse the config file
    NSError *jsonError = nil;
    NSDictionary *json = nil;
    if (![self loadJSONDictionaryAtPath:shuttleConfigFile into:&json error:&jsonError]) {
        [self insertDisabledMenuItemWithTitle:NSLocalizedString(@"Error parsing config", nil)];
        NSLog(@"Error parsing config %@: %@", shuttleConfigFile, jsonError);
        return;
    }

    terminalPref = [self stringValueForKey:@"terminal" inDictionary:json defaultValue:@"terminal.app"];
    editorPref = [self stringValueForKey:@"editor" inDictionary:json defaultValue:@"default"];
    openInPref = [self stringValueForKey:@"open_in" inDictionary:json defaultValue:@"tab"];
    themePref = [json[@"default_theme"] isKindOfClass:[NSString class]] ? json[@"default_theme"] : nil;
    launchAtLoginController.launchAtLogin = [json[@"launch_at_login"] boolValue];
    shuttleHosts = [self validatedHostsFromJSON:json sourceName:@"primary config"];
    ignoreHosts = [self mutableStringArrayFromValue:json[@"ssh_config_ignore_hosts"]];
    ignoreKeywords = [self mutableStringArrayFromValue:json[@"ssh_config_ignore_keywords"]];

    //add hosts from the alternate json config
    if (parseAltJSON) {
        NSError *jsonAltError = nil;
        NSDictionary *jsonAlt = nil;
        if ([self loadJSONDictionaryAtPath:shuttleAltConfigFile into:&jsonAlt error:&jsonAltError]) {
            shuttleHostsAlt = [self validatedHostsFromJSON:jsonAlt sourceName:@"alternate config"];
            [shuttleHosts addObjectsFromArray:shuttleHostsAlt];
        } else {
            [self insertDisabledMenuItemWithTitle:NSLocalizedString(@"Error parsing alternate config", nil)];
            NSLog(@"Error parsing alternate config %@: %@", shuttleAltConfigFile, jsonAltError);
        }
    }

    // Should we merge ssh config hosts?
    BOOL showSshConfigHosts = YES;
    if ([[json allKeys] containsObject:(@"show_ssh_config_hosts")] && [json[@"show_ssh_config_hosts"] boolValue] == NO) {
        showSshConfigHosts = NO;
    }

    if (showSshConfigHosts) {
        // Read configuration from ssh config
        NSDictionary* servers = [self parseSSHConfigFile];
        for (NSString* key in servers) {
            BOOL skipCurrent = NO;
            NSDictionary* cfg = [servers objectForKey:key];

            // get special name from config if set, fallback to the key
            NSString* name = cfg[@"name"] ? cfg[@"name"] : key;

            // Ignore entries that contain wildcard characters
            if ([name rangeOfString:@"*"].length != 0)
                skipCurrent = YES;

            // Ignore entries that start with `.`
            if ([name hasPrefix:@"."])
                skipCurrent = YES;

            // Ignore entries whose name matches exactly any of the values in ignoreHosts
            for (NSString* ignore in ignoreHosts) {
                if ([name isEqualToString:ignore]) {
                    skipCurrent = YES;
                }
            }

            // Ignore entries whose name contains any of the values in ignoreKeywords
            for (NSString* ignore in ignoreKeywords) {
                if ([name rangeOfString:ignore].location != NSNotFound) {
                    skipCurrent = YES;
                }
            }

            if (skipCurrent) {
                continue;
            }

            // Split the host into parts separated by / - the last part is the name for the leaf in the tree
            NSMutableArray* path = [NSMutableArray arrayWithArray:[name componentsSeparatedByString:@"/"]];
            NSString* leaf = [path lastObject];
            if (leaf == nil)
                continue;
            [path removeLastObject];

            NSMutableArray* itemList = shuttleHosts;
            for (NSString *part in path) {
                BOOL createList = YES;
                for (id rawItem in itemList) {
                    if (![rawItem isKindOfClass:[NSDictionary class]]) {
                        continue;
                    }

                    NSDictionary* item = rawItem;
                    // if we encounter an item with cmd/name then we have to bail
                    // since there's no way we can dig deeper here
                    if (item[@"cmd"] || item[@"name"]) {
                        continue;
                    }

                    // if this item has the name of our target check if we can
                    // reuse it (if it's an array) - or if we need to bail
                    if (item[part]) {
                        // make sure this is an array and not an object
                        if ([item[part] isKindOfClass:[NSArray class]]) {
                            itemList = item[part];
                            createList = NO;
                        } else {
                            itemList = nil;
                        }
                        break;
                    }
                }

                if (itemList == nil) {
                    // things gone south... there's already something present and it's
                    // not an array...
                    break;
                }

                if (createList) {
                    // create a new entry and set it as itemList
                    NSMutableArray *newList = [[NSMutableArray alloc] init];
                    [itemList addObject:[NSDictionary dictionaryWithObject:newList
                                                                    forKey:part]];
                    itemList = newList;
                }
            }

            // if everything worked out we will see a non-nil itemList where the
            // system should be appended to. part hold the last part of the splitted string (aka hostname).
            if (itemList) {
                // build the corresponding ssh command
                NSString* cmd = [NSString stringWithFormat:@"ssh %@", key];

                // inject the data into the json parser result
                [itemList addObject:[NSDictionary dictionaryWithObjects:[NSArray arrayWithObjects:leaf, cmd, nil]
                                                                forKeys:[NSArray arrayWithObjects:@"name", @"cmd", nil]]];
            }
        }
    }

    // feed the final result into the recursive method which builds the menu
    [self buildMenu:shuttleHosts addToMenu:menu];
}

- (void) buildMenu:(NSArray*)data addToMenu:(NSMenu *)m {
    // go through the array and sort out the menus and the leafs into
    // separate bucks so we can sort them independently.
    NSMutableDictionary* menus = [[NSMutableDictionary alloc] init];
    NSMutableDictionary* leafs = [[NSMutableDictionary alloc] init];

    for (id rawItem in data) {
        if (![rawItem isKindOfClass:[NSDictionary class]]) {
            continue;
        }

        NSDictionary* item = rawItem;
        if ([item[@"cmd"] isKindOfClass:[NSString class]] && [item[@"name"] isKindOfClass:[NSString class]]) {
            // this is a leaf
            [leafs setObject:item forKey:item[@"name"]];
        } else {
            // must be a menu - add all instances
            for (NSString* key in item) {
                if ([item[key] isKindOfClass:[NSArray class]]) {
                    [menus setObject:item[key] forKey:key];
                }
            }
        }
    }

    NSArray* menuKeys = [[menus allKeys] sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
    NSArray* leafKeys = [[leafs allKeys] sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)];

    NSInteger pos = 0;

    // create menus first
    for (NSString* key in menuKeys) {
        NSMenu* subMenu = [[NSMenu alloc] init];
        NSMenuItem* menuItem = [[NSMenuItem alloc] init];
        [self separatorSortRemoval:key];
        [menuItem setTitle:menuName];
        [menuItem setSubmenu:subMenu];
        [m insertItem:menuItem atIndex:pos++];
        if (addSeparator) {
            [m insertItem:[NSMenuItem separatorItem] atIndex:pos++];
        }
        // build submenu
        [self buildMenu:menus[key] addToMenu:subMenu];
    }

    // now create leafs
    for (NSString *key in leafKeys) {
        NSDictionary* cfg = leafs[key];
        NSMenuItem* menuItem = [[NSMenuItem alloc] init];

        //Get the command we are going to run in termainal
        NSString *menuCmd = cfg[@"cmd"];
        //Get the theme for this terminal session
        NSString *termTheme = cfg[@"theme"];
        //Get the name for the terminal session
        NSString *termTitle = cfg[@"title"];
        //Get the value of setting inTerminal
        NSString *termWindow = cfg[@"inTerminal"];
        //Get the menu name will will use this as the title if title is null.
        [self separatorSortRemoval:cfg[@"name"]];

        //Place the terminal command, theme, and title into the legacy separator-delimited string.
        NSString *menuRepObj = [self legacyMenuRepresentedObjectWithCommand:menuCmd
                                                                      theme:termTheme
                                                                      title:termTitle
                                                                     window:termWindow
                                                                       name:menuName];

        [menuItem setTitle:menuName];
        [menuItem setRepresentedObject:menuRepObj];
        [menuItem setAction:@selector(openHost:)];
        [m insertItem:menuItem atIndex:pos++];
        if (addSeparator) {
            [m insertItem:[NSMenuItem separatorItem] atIndex:pos++];
        }
    }
}

- (void) separatorSortRemoval:(NSString *)currentName {
    NSError *regexError = nil;
    addSeparator = NO;

    NSRegularExpression *regexSort = [NSRegularExpression regularExpressionWithPattern:@"([\\[][a-z]{3}[\\]])" options:0 error:&regexError];
    NSRegularExpression *regexSeparator = [NSRegularExpression regularExpressionWithPattern:@"([\\[][-]{3}[\\]])" options:0 error:&regexError];

    NSUInteger sortMatches = [regexSort numberOfMatchesInString:currentName options:0 range:NSMakeRange(0,[currentName length])];
    NSUInteger separatorMatches = [regexSeparator  numberOfMatchesInString:currentName options:0 range:NSMakeRange(0,[currentName length])];
    //NSUInteger *totalMatches = sortMatches + separatorMatches;



    if ( sortMatches == 1 || separatorMatches == 1 ) {
        if (sortMatches == 1 && separatorMatches == 1 ) {
            menuName = [regexSort stringByReplacingMatchesInString:currentName options:0 range:NSMakeRange(0, [currentName length]) withTemplate:@""];
            menuName = [regexSeparator stringByReplacingMatchesInString:menuName options:0 range:NSMakeRange(0, [menuName length]) withTemplate:@""];
            addSeparator = YES;
        } else {

            if( sortMatches == 1) {
                menuName = [regexSort stringByReplacingMatchesInString:currentName options:0 range:NSMakeRange(0, [currentName length]) withTemplate:@""];
                addSeparator = NO;
            }
            if ( separatorMatches == 1 ) {
                menuName = [regexSeparator stringByReplacingMatchesInString:currentName options:0 range:NSMakeRange(0, [currentName length]) withTemplate:@""];
                addSeparator = YES;
            }
        }
    } else {
        menuName = currentName;
        addSeparator = NO;
    }
}

- (void) openHost:(NSMenuItem *) sender {
    //NSLog(@"sender: %@", sender);
    //NSLog(@"Command: %@",[sender representedObject]);

    NSString *errorMessage;
    NSString *errorInfo;

    //Place the menu item settings into the legacy component array shape.
    NSArray *objectsFromJSON = [self menuComponentsFromRepresentedObject:[sender representedObject]];
    if (!objectsFromJSON) {
        [self throwError:NSLocalizedString(@"Invalid menu item configuration", nil)
          additionalInfo:NSLocalizedString(@"The selected item does not contain a complete command definition.", nil)
continueOnErrorOption:NO];
        return;
    }

    //This is our command that will be run in the terminal window
    NSString *escapedObject;
    //The theme for the terminal window
    NSString *terminalTheme;
    //The title for the terminal window
    NSString *terminalTitle;
    //Are commands run in a new tab (default) a new terminal window (new), or in the current tab of the last used window (current).
    NSString *terminalWindow;

    escapedObject = [objectsFromJSON objectAtIndex:0];

    //if terminalTheme is not set then check for a global setting.
    if( [[objectsFromJSON objectAtIndex:1] isEqualToString:@"(null)"] ){
        if(themePref == 0) {
            if( [terminalPref isEqualToString:@"iterm"] ){
                //we have no global theme and there is no theme in the command settings.
                //Forcing the Default profile for iTerm and the basic profile for Terminal.app
                terminalTheme = @"Default";
            }else{
                terminalTheme = @"basic";
            }
            //We have a global setting using this as the theme.
        }else {
            terminalTheme = themePref;
        }
        //we have command level theme override the Global default_theme settings.
    }else{
        terminalTheme = [objectsFromJSON objectAtIndex:1];
    }

    //Check if terminalTitle is null
    if( [[objectsFromJSON objectAtIndex:2] isEqualToString:@"(null)"]){
        //setting the empty title to that of the menu item.
        terminalTitle = [objectsFromJSON objectAtIndex:4];
    }else{
        terminalTitle = [objectsFromJSON objectAtIndex:2];
    }

    //Check if inTerminal is null if so then use the default settings of open_in
    if( [[objectsFromJSON objectAtIndex:3] isEqualToString:@"(null)"]){

        //if open_in is not "tab" or "new" then force the default of "tab".
        if( ![openInPref isEqualToString:@"tab"] && ![openInPref isEqualToString:@"new"]){
            openInPref = @"tab";
        }
        //open_in was not empty or bad value we are passing the settings.
        terminalWindow = openInPref;
    }else{
        //inTerminal is not null and overrides the default values of open_in
        terminalWindow = [objectsFromJSON objectAtIndex:3];
        if( ![terminalWindow isEqualToString:@"new"] && ![terminalWindow isEqualToString:@"current"] && ![terminalWindow isEqualToString:@"tab"] && ![terminalWindow isEqualToString:@"virtual"])
        {
            errorMessage = [NSString stringWithFormat:@"%@%@%@ %@",@"'",terminalWindow,@"'", NSLocalizedString(@"is not a valid value for inTerminal. Please fix this in the JSON file",nil)];
            errorInfo = NSLocalizedString(@"bad \"inTerminal\":\"VALUE\" in the JSON settings",nil);
            [self throwError:errorMessage additionalInfo:errorInfo continueOnErrorOption:NO];
        }
    }

    // 先检查是否是 URL
    NSURL *url = [NSURL URLWithString:escapedObject];
    if (url && [url scheme]) {
        [[NSWorkspace sharedWorkspace] openURL:url];
        return;
    }

    // 确定终端类型
    TerminalType termType = TerminalTypeDefault;
    if ([terminalPref rangeOfString:@"iterm"].location != NSNotFound) {
        termType = TerminalTypeITerm;
    }

    // 确定窗口模式
    WindowMode winMode = WindowModeTab; // 默认为标签页模式
    if ([terminalWindow isEqualToString:@"new"]) {
        winMode = WindowModeNew;
    } else if ([terminalWindow isEqualToString:@"current"]) {
        winMode = WindowModeCurrent;
    } else if ([terminalWindow isEqualToString:@"virtual"]) {
        winMode = WindowModeVirtual;
    }

    if ([self isOpenHostDryRunEnabled]) {
        NSLog(@"SHUTTLE_OPENHOST_DRY_RUN command=%@ terminalType=%ld windowMode=%ld theme=%@ title=%@",
              escapedObject, (long)termType, (long)winMode, terminalTheme, terminalTitle);
        return;
    }

    // 使用 TerminalManager 执行命令
    //[[TerminalManager sharedManager] executeCommand:escapedObject
    //                                  terminalType:termType
    //                                  windowMode:winMode
    //                                       theme:terminalTheme
    //                                       title:terminalTitle];

    [[TerminalManager sharedManager] executeCommandDirectly:escapedObject
                                         terminalType:termType
                                           windowMode:winMode
                                                theme:terminalTheme
                                                title:terminalTitle];
}

- (void) runScript:(NSString *)scriptPath handler:(NSString*)handlerName parameters:(NSArray*)parametersInArray {
    //special thanks to stackoverflow.com/users/316866/leandro for pointing me the right direction.
    //see http://goo.gl/olcpaX
    NSAppleScript           * appleScript;
    NSAppleEventDescriptor  * thisApplication, *containerEvent;
    NSURL                   * pathURL = [NSURL fileURLWithPath:scriptPath];

    NSDictionary * appleScriptCreationError = nil;
    appleScript = [[NSAppleScript alloc] initWithContentsOfURL:pathURL error:&appleScriptCreationError];

    if (handlerName && [handlerName length])
    {
        /* If we have a handlerName (and potentially parameters), we build
         * an NSAppleEvent to execute the script. */

        //Get a descriptor
        int pid = [[NSProcessInfo processInfo] processIdentifier];
        thisApplication = [NSAppleEventDescriptor descriptorWithDescriptorType:typeKernelProcessID
                                                                         bytes:&pid
                                                                        length:sizeof(pid)];

        //Create the container event

        //We need these constants from the Carbon OpenScripting framework, but we don't actually need Carbon.framework...
#define kASAppleScriptSuite 'ascr'
#define kASSubroutineEvent  'psbr'
#define keyASSubroutineName 'snam'
        containerEvent = [NSAppleEventDescriptor appleEventWithEventClass:kASAppleScriptSuite
                                                                  eventID:kASSubroutineEvent
                                                         targetDescriptor:thisApplication
                                                                 returnID:kAutoGenerateReturnID
                                                            transactionID:kAnyTransactionID];
        //Set the target handler
        [containerEvent setParamDescriptor:[NSAppleEventDescriptor descriptorWithString:handlerName]
                                forKeyword:keyASSubroutineName];

        //Pass parameters - parameters is expecting an NSArray with only NSString objects
        if ([parametersInArray count])
        {

            NSAppleEventDescriptor  *arguments = [[NSAppleEventDescriptor alloc] initListDescriptor];
            NSString                *object;

            for (object in parametersInArray) {
                [arguments insertDescriptor:[NSAppleEventDescriptor descriptorWithString:object]
                                    atIndex:([arguments numberOfItems] +1)];
            }

            [containerEvent setParamDescriptor:arguments forKeyword:keyDirectObject];
        }
        //Execute the event
        [appleScript executeAppleEvent:containerEvent error:nil];
    }
}

- (void)showWarning:(NSString *)message additionalInfo:(NSString *)info {
    NSAlert *alert = [[NSAlert alloc] init];
    [alert setMessageText:message];
    [alert setInformativeText:info ?: @""];
    [alert setAlertStyle:NSAlertStyleWarning];
    [alert addButtonWithTitle:NSLocalizedString(@"OK", nil)];
    [alert runModal];
}

- (IBAction)showImportPanel:(id)sender {
    NSOpenPanel * openPanelObj	= [NSOpenPanel openPanel];
    NSInteger tvarNSInteger	= [openPanelObj runModal];
    if(tvarNSInteger == NSModalResponseOK){
        NSFileManager *fileManager = [NSFileManager defaultManager];
        NSURL * selectedFileUrl = [openPanelObj URL];
        NSURL *configURL = [NSURL fileURLWithPath:shuttleConfigFile];
        NSString *tempPath = [NSTemporaryDirectory() stringByAppendingPathComponent:[[NSUUID UUID] UUIDString]];
        NSURL *tempURL = [NSURL fileURLWithPath:tempPath];
        NSError *error = nil;

        if (![fileManager copyItemAtURL:selectedFileUrl toURL:tempURL error:&error]) {
            [self showWarning:NSLocalizedString(@"Could not import config", nil)
               additionalInfo:[error localizedDescription]];
            return;
        }

        if ([fileManager fileExistsAtPath:shuttleConfigFile]) {
            NSString *backupName = [[configURL lastPathComponent] stringByAppendingString:@".backup"];
            NSURL *resultingURL = nil;
            if (![fileManager replaceItemAtURL:configURL
                                  withItemAtURL:tempURL
                                 backupItemName:backupName
                                        options:0
                               resultingItemURL:&resultingURL
                                          error:&error]) {
                [fileManager removeItemAtURL:tempURL error:nil];
                [self showWarning:NSLocalizedString(@"Could not import config", nil)
                   additionalInfo:[error localizedDescription]];
                return;
            }

            NSURL *backupURL = [[configURL URLByDeletingLastPathComponent] URLByAppendingPathComponent:backupName];
            [fileManager removeItemAtURL:backupURL error:nil];
        } else if (![fileManager moveItemAtURL:tempURL toURL:configURL error:&error]) {
            [fileManager removeItemAtURL:tempURL error:nil];
            [self showWarning:NSLocalizedString(@"Could not import config", nil)
               additionalInfo:[error localizedDescription]];
            return;
        }
    } else {
        return;
    }

}

-(void) throwError:(NSString*)errorMessage additionalInfo:(NSString*)errorInfo continueOnErrorOption:(BOOL)continueOption {
    NSAlert *alert = [[NSAlert alloc] init];
    [alert setInformativeText:errorInfo];
    [alert setMessageText:errorMessage];
    [alert setAlertStyle:NSAlertStyleWarning];

    if (continueOption) {
        [alert addButtonWithTitle:NSLocalizedString(@"Quit",nil)];
        [alert addButtonWithTitle:NSLocalizedString(@"Continue",nil)];

    }else{
        [alert addButtonWithTitle:NSLocalizedString(@"Quit",nil)];
    }

    if ([alert runModal] == NSAlertFirstButtonReturn) {
        [NSApp terminate:NSApp];
    }
}

- (IBAction)showExportPanel:(id)sender {
    NSSavePanel * savePanelObj	= [NSSavePanel savePanel];
    //Display the Save Panel
    NSInteger result	= [savePanelObj runModal];
    if (result == NSModalResponseOK) {
        NSURL *saveURL = [savePanelObj URL];
        // then copy a previous file to the new location
        NSError *error = nil;
        if (![[NSFileManager defaultManager] copyItemAtPath:shuttleConfigFile toPath:saveURL.path error:&error]) {
            [self showWarning:NSLocalizedString(@"Could not export config", nil)
               additionalInfo:[error localizedDescription]];
        }
    }
}

- (IBAction)configure:(id)sender {

    //if the editor setting is omitted or contains 'default' open using the default editor.
    if([editorPref rangeOfString:@"default"].location != NSNotFound) {

        [[NSWorkspace sharedWorkspace] openURL:[NSURL fileURLWithPath:shuttleConfigFile]];
    }
    else{
        //build the editor command
        NSString *editorCommand = [NSString stringWithFormat:@"%@ %@", editorPref, shuttleConfigFile];

        //build the reprensented object. It's expecting menuCmd, termTheme, termTitle, termWindow, menuName
        NSString *editorRepObj = [NSString stringWithFormat:@"%@¬_¬%@¬_¬%@¬_¬%@¬_¬%@", editorCommand, nil, @"Editing shuttle JSON", nil, nil];

        //make a menu item for the command selector(openHost:) runs in a new terminal window.
        NSMenuItem *editorMenu = [[NSMenuItem alloc] initWithTitle:@"editJSONconfig" action:@selector(openHost:) keyEquivalent:(@"")];

        //set the command for the menu item
        [editorMenu setRepresentedObject:editorRepObj];

        //open the JSON file in the terminal editor.
        [self openHost:editorMenu];
    }
}

- (IBAction)showAbout:(id)sender {

    //Call the windows controller
    AboutWindowController *aboutWindow = [[AboutWindowController alloc] initWithWindowNibName:@"AboutWindowController"];

    //Set the window to stay on top
    [aboutWindow.window makeKeyAndOrderFront:nil];
    [aboutWindow.window setLevel:NSFloatingWindowLevel];

    //Show the window
    [aboutWindow showWindow:self];
}

- (IBAction)quit:(id)sender {
    [[NSStatusBar systemStatusBar] removeStatusItem:statusItem];
    [NSApp terminate:NSApp];
}

@end
