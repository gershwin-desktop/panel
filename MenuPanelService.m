#import "MenuPanelService.h"

@implementation MenuPanelService

@synthesize menuDisplayView = _menuDisplayView;

- (instancetype)init
{
    self = [super init];
    if (self) {
        applicationMenus = [[NSMutableDictionary alloc] init];
    }
    return self;
}

- (void)dealloc
{
    [self stopService];
    [applicationMenus release];
    [super dealloc];
}

- (void)startService
{
    NSLog(@"MenuPanelService: Starting service...");
    
    // Make sure we invalidate any existing connection first
    if (serverConnection) {
        NSLog(@"MenuPanelService: Invalidating existing connection");
        [serverConnection invalidate];
        serverConnection = nil;
    }
    
    // Check for and clear any existing registrations
    NSConnection *existing = [NSConnection connectionWithRegisteredName:@"GNUstepMenuPanel" host:nil];
    if (existing) {
        NSLog(@"MenuPanelService: Found existing service, invalidating...");
        [existing invalidate];
        // Wait for cleanup
        sleep(1);
    }
    
    serverConnection = [NSConnection defaultConnection];
    [serverConnection setRootObject:self];
    
    NSLog(@"MenuPanelService: Setting root object to: %@ of class %@", self, [self class]);
    NSLog(@"MenuPanelService: Root object responds to registerApplication: %@", 
          [self respondsToSelector:@selector(registerApplication:)] ? @"YES" : @"NO");
    
    // Set timeouts
    [serverConnection setRequestTimeout:10.0];
    [serverConnection setReplyTimeout:10.0];
    
    if (![serverConnection registerName:@"GNUstepMenuPanel"]) {
        NSLog(@"MenuPanelService: FAILED to register name 'GNUstepMenuPanel'");
        return;
    }
    
    NSLog(@"MenuPanelService: Successfully registered name 'GNUstepMenuPanel'");
    NSLog(@"MenuPanelService: Service ready for connections");
}

- (void)stopService
{
    if (serverConnection) {
        [serverConnection invalidate];
        serverConnection = nil;
    }
}

#pragma mark - GSMenuPanelService Protocol

- (void)registerApplication:(NSString *)appId
{
    NSLog(@"Panel: Registering application: %@", appId);
    if (!appId) {
        NSLog(@"Panel: Warning - nil appId in registerApplication");
        return;
    }
}

- (void)unregisterApplication:(NSString *)appId
{
    NSLog(@"Panel: Unregistering application: %@", appId);
    if (!appId) return;
    
    [applicationMenus removeObjectForKey:appId];
    if ([activeApplicationId isEqualToString:appId]) {
        activeApplicationId = nil;
        [self refreshMenuDisplay];
    }
}

- (void)setMainMenu:(in bycopy NSMenu *)menu forApplication:(NSString *)appId
{
    NSLog(@"Panel: setMainMenu called for app %@", appId);
    
    if (!menu || !appId) {
        NSLog(@"Panel: Warning - nil menu (%@) or appId (%@)", menu, appId);
        return;
    }
    
    NSLog(@"Panel: Menu title: '%@'", [menu title]);
    NSLog(@"Panel: Menu item count: %lu", (unsigned long)[[menu itemArray] count]);
    
    // Log first few menu items for debugging
    NSArray *items = [menu itemArray];
    for (NSUInteger i = 0; i < MIN(3, [items count]); i++) {
        NSMenuItem *item = [items objectAtIndex:i];
        NSLog(@"Panel: Item %lu: '%@'", (unsigned long)i, [item title]);
    }
    
    [applicationMenus setObject:menu forKey:appId];
    
    if ([appId isEqualToString:activeApplicationId] || !activeApplicationId) {
        NSLog(@"Panel: Setting as active menu for app %@", appId);
        activeApplicationId = appId;
        [self refreshMenuDisplay];
    } else {
        NSLog(@"Panel: Menu stored for app %@ (not currently active)", appId);
    }
}

- (void)applicationDidBecomeActive:(NSString *)appId
{
    NSLog(@"Panel: App became active: %@", appId);
    if (!appId) return;
    
    activeApplicationId = appId;
    [self refreshMenuDisplay];
}

- (void)applicationDidResignActive:(NSString *)appId
{
    NSLog(@"Panel: App resigned active: %@", appId);
    // Keep the menu visible even when app resigns active
    // This matches typical Mac behavior
}

#pragma mark - Display Methods

- (void)refreshMenuDisplay
{
    NSLog(@"Panel: refreshMenuDisplay called");
    NSLog(@"Panel: activeApplicationId: %@", activeApplicationId);
    NSLog(@"Panel: menuDisplayView: %@", _menuDisplayView);
    
    if (!activeApplicationId || !_menuDisplayView) {
        NSLog(@"Panel: Cannot refresh - missing activeApp or displayView");
        return;
    }
    
    NSMenu *currentMenu = [applicationMenus objectForKey:activeApplicationId];
    NSLog(@"Panel: currentMenu for app %@: %@", activeApplicationId, currentMenu);
    
    if (currentMenu) {
        [self performSelectorOnMainThread:@selector(displayMenuOnMainThread:)
                               withObject:currentMenu
                            waitUntilDone:NO];
    } else {
        NSLog(@"Panel: No menu found for active app %@", activeApplicationId);
        // Clear the display if no menu
        [self performSelectorOnMainThread:@selector(displayMenuOnMainThread:)
                               withObject:nil
                            waitUntilDone:NO];
    }
}

- (void)displayMenuOnMainThread:(NSMenu *)menu
{
    [self displayMenu:menu inView:_menuDisplayView];
}

- (void)displayMenu:(NSMenu *)menu inView:(NSView *)view
{
    NSLog(@"Panel: displayMenu called with menu '%@'", menu ? [menu title] : @"(nil)");
    
    // Remove ALL existing subviews
    NSArray *subviews = [[view subviews] copy];
    for (NSView *subview in subviews) {
        NSLog(@"Panel: Removing subview: %@ of class %@", subview, [subview class]);
        [subview removeFromSuperview];
    }
    [subviews release];
    
    if (!menu) {
        NSLog(@"Panel: No menu to display - panel cleared");
        [view setNeedsDisplay:YES];
        return;
    }
    
    NSLog(@"Panel: Creating NSMenuView for menu with %lu items", (unsigned long)[[menu itemArray] count]);
    
    NSMenuView *menuView = [[NSMenuView alloc] initWithFrame:[view bounds]];
    [menuView setMenu:menu];
    [menuView setHorizontal:YES];
    [menuView setInterfaceStyle:NSMacintoshInterfaceStyle];
    [menuView setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
    
    // Force the menu view to size itself
    [menuView sizeToFit];
    
    NSLog(@"Panel: Adding menu view with frame: %@", NSStringFromRect([menuView frame]));
    
    [view addSubview:menuView];
    [menuView release];
    
    [view setNeedsDisplay:YES];
    
    NSLog(@"Panel: Menu display completed for '%@'", [menu title]);
}

@end
