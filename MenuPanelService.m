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
    NSLog(@"MenuPanelService: Root object responds to setMainMenu:forApplication: %@", 
          [self respondsToSelector:@selector(setMainMenu:forApplication:)] ? @"YES" : @"NO");
    NSLog(@"MenuPanelService: Root object responds to setMenuData:forApplication: %@", 
          [self respondsToSelector:@selector(setMenuData:forApplication:)] ? @"YES" : @"NO");
    
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

- (void)setMainMenu:(in bycopy NSMenu *)menu forApplication:(in bycopy NSString *)appId
{
    NSLog(@"Panel: *** setMainMenu CALLED - ENTRY POINT ***");
    NSLog(@"Panel: appId: %@", appId);
    NSLog(@"Panel: menu: %@", menu);
    
    if (!menu || !appId) {
        NSLog(@"Panel: ERROR - nil menu (%@) or appId (%@)", menu, appId);
        return;
    }
    
    NSLog(@"Panel: Received menu titled: '%@'", [menu title]);
    NSLog(@"Panel: Menu has %lu items", (unsigned long)[[menu itemArray] count]);
    
    // Log the first few menu items we received
    NSArray *items = [menu itemArray];
    for (NSUInteger i = 0; i < MIN(5, [items count]); i++) {
        NSMenuItem *item = [items objectAtIndex:i];
        NSLog(@"Panel: Item %lu: '%@'", (unsigned long)i, [item title]);
    }
    
    // Store the menu
    [applicationMenus setObject:menu forKey:appId];
    
    if ([appId isEqualToString:activeApplicationId] || !activeApplicationId) {
        NSLog(@"Panel: Setting app %@ as active and displaying menu", appId);
        activeApplicationId = appId;
        [self refreshMenuDisplay];
    } else {
        NSLog(@"Panel: Menu stored for app %@ (active app is %@)", appId, activeApplicationId);
    }
}

- (void)setMenuData:(in bycopy NSDictionary *)menuData forApplication:(in bycopy NSString *)appId
{
    NSLog(@"Panel: *** setMenuData CALLED for app %@ ***", appId);
    
    if (!menuData || !appId) {
        NSLog(@"Panel: ERROR - nil menuData (%@) or appId (%@)", menuData, appId);
        return;
    }
    
    NSLog(@"Panel: Received menu data: %@", menuData);
    
    // Convert dictionary back to NSMenu
    NSMenu *reconstructedMenu = [self reconstructMenuFromDict:menuData];
    if (reconstructedMenu) {
        NSLog(@"Panel: Successfully reconstructed menu from data");
        [self setMainMenu:reconstructedMenu forApplication:appId];
    } else {
        NSLog(@"Panel: Failed to reconstruct menu from dictionary data");
    }
}

- (NSMenu *)reconstructMenuFromDict:(NSDictionary *)menuDict
{
    NSString *title = [menuDict objectForKey:@"title"];
    if (!title) {
        NSLog(@"Panel: No title in menu dictionary");
        return nil;
    }
    
    NSLog(@"Panel: Reconstructing menu titled: '%@'", title);
    NSMenu *menu = [[NSMenu alloc] initWithTitle:title];
    NSArray *itemsArray = [menuDict objectForKey:@"items"];
    
    if (!itemsArray) {
        NSLog(@"Panel: No items array in menu dictionary");
        [menu release];
        return nil;
    }
    
    for (NSDictionary *itemDict in itemsArray) {
        NSString *itemTitle = [itemDict objectForKey:@"title"];
        BOOL isSeparator = [[itemDict objectForKey:@"separator"] boolValue];
        
        NSMenuItem *item;
        if (isSeparator) {
            item = [NSMenuItem separatorItem];
            NSLog(@"Panel: Added separator item");
        } else {
            item = [[NSMenuItem alloc] initWithTitle:itemTitle action:NULL keyEquivalent:@""];
            [item setEnabled:[[itemDict objectForKey:@"enabled"] boolValue]];
            [item setHidden:[[itemDict objectForKey:@"hidden"] boolValue]];
            
            NSString *keyEquiv = [itemDict objectForKey:@"keyEquivalent"];
            if (keyEquiv) {
                [item setKeyEquivalent:keyEquiv];
                [item setKeyEquivalentModifierMask:[[itemDict objectForKey:@"keyModifiers"] intValue]];
            }
            
            // Handle submenu
            NSDictionary *submenuDict = [itemDict objectForKey:@"submenu"];
            if (submenuDict) {
                NSMenu *submenu = [self reconstructMenuFromDict:submenuDict];
                if (submenu) {
                    [item setSubmenu:submenu];
                    [submenu release];
                }
            }
            
            NSLog(@"Panel: Added menu item: '%@'", itemTitle);
        }
        
        [menu addItem:item];
        if (!isSeparator) [item release];
    }
    
    NSLog(@"Panel: Reconstructed menu with %lu items", (unsigned long)[[menu itemArray] count]);
    return [menu autorelease];
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
    NSLog(@"Panel: stored menus: %@", [applicationMenus allKeys]);
    
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
    NSLog(@"Panel: *** DISPLAY MENU CALLED - menu: %@, view: %@", menu, view);
    NSLog(@"Panel: *** displayMenu called *** with menu '%@'", menu ? [menu title] : @"(nil)");
    
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
    
    NSLog(@"Panel: Creating NSMenuView for menu '%@' with %lu items", [menu title], (unsigned long)[[menu itemArray] count]);
    
    // Create the menu view
    NSMenuView *menuView = [[NSMenuView alloc] initWithFrame:[view bounds]];
    
    // CRITICAL: Set horizontal BEFORE setting the menu
    [menuView setHorizontal:YES];
    [menuView setInterfaceStyle:NSMacintoshInterfaceStyle];
    
    // Set the menu
    [menuView setMenu:menu];
    
    // Configure autoresizing
    [menuView setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
    
    // Force initial sizing
    [menuView sizeToFit];
    
    // Get the sized frame and ensure it fits in our bounds
    NSRect menuFrame = [menuView frame];
    NSRect viewBounds = [view bounds];
    menuFrame.size.width = MIN(menuFrame.size.width, viewBounds.size.width);
    menuFrame.size.height = viewBounds.size.height; // Force to panel height
    [menuView setFrame:menuFrame];
    
    NSLog(@"Panel: Adding menu view with frame: %@", NSStringFromRect([menuView frame]));
    NSLog(@"Panel: Menu view class: %@", [menuView class]);
    
    [view addSubview:menuView];
    
    // IMPORTANT: Force the menu view to become visible
    [menuView setHidden:NO];
    [menuView setNeedsDisplay:YES];
    
    // Force the parent view to update
    [view setNeedsDisplay:YES];
    
    // Try to force window update if needed
    NSWindow *window = [view window];
    if (window) {
        [window display];
        [window flushWindow];
    }
    
    [menuView release];
    
    NSLog(@"Panel: *** Menu display completed for '%@' ***", [menu title]);
    
    // Debug output
    NSLog(@"Panel: View now has %lu subviews", (unsigned long)[[view subviews] count]);
    for (NSView *subview in [view subviews]) {
        NSLog(@"Panel: Subview: %@ frame: %@ hidden: %d", [subview class], 
              NSStringFromRect([subview frame]), [subview isHidden]);
    }
}

@end
