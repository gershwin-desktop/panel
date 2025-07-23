#import "MenuPanelService.h"

@implementation MenuPanelService

@synthesize menuDisplayView = _menuDisplayView;  // Explicit synthesis

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
    serverConnection = [NSConnection defaultConnection];
    [serverConnection setRootObject:self];
    
    if (![serverConnection registerName:@"GNUstepMenuPanel"]) {
        NSLog(@"Failed to register menu panel service");
        return;
    }
    
    NSLog(@"Menu panel service started successfully");
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
    NSLog(@"Registering application: %@", appId);
}

- (void)unregisterApplication:(NSString *)appId
{
    NSLog(@"Unregistering application: %@", appId);
    [applicationMenus removeObjectForKey:appId];
    if ([activeApplicationId isEqualToString:appId]) {
        activeApplicationId = nil;
        [self refreshMenuDisplay];
    }
}

// Fixed: Add (in bycopy) modifier to match protocol
- (void)setMainMenu:(in bycopy NSMenu *)menu forApplication:(NSString *)appId
{
    if (menu) {
        NSLog(@"Setting menu for app %@: %@", appId, [menu title]);
        [applicationMenus setObject:menu forKey:appId];
        
        if ([appId isEqualToString:activeApplicationId] || !activeApplicationId) {
            activeApplicationId = appId;
            [self refreshMenuDisplay];
        }
    }
}

- (void)applicationDidBecomeActive:(NSString *)appId
{
    NSLog(@"App became active: %@", appId);
    activeApplicationId = appId;
    [self refreshMenuDisplay];
}

- (void)applicationDidResignActive:(NSString *)appId
{
    NSLog(@"App resigned active: %@", appId);
}

#pragma mark - Display Methods

- (void)refreshMenuDisplay
{
    if (!activeApplicationId || !_menuDisplayView) {
        return;
    }
    
    NSMenu *currentMenu = [applicationMenus objectForKey:activeApplicationId];
    if (currentMenu) {
        [self performSelectorOnMainThread:@selector(displayMenuOnMainThread:)
                               withObject:currentMenu
                            waitUntilDone:NO];
    }
}

- (void)displayMenuOnMainThread:(NSMenu *)menu
{
    [self displayMenu:menu inView:_menuDisplayView];
}

- (void)displayMenu:(NSMenu *)menu inView:(NSView *)view
{
    // Remove existing menu views
    for (NSView *subview in [view subviews]) {
        if ([subview isKindOfClass:[NSMenuView class]]) {
            [subview removeFromSuperview];
        }
    }
    
    if (!menu) return;
    
    NSMenuView *menuView = [[NSMenuView alloc] initWithFrame:[view bounds]];
    [menuView setMenu:menu];
    [menuView setHorizontal:YES];
    [menuView setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
    
    [view addSubview:menuView];
    [menuView release];
    
    [view setNeedsDisplay:YES];
    
    NSLog(@"Displayed menu '%@' with %lu items", [menu title], (unsigned long)[[menu itemArray] count]);
}

@end
