#import "DBusMenuPanelService.h"
#import <X11/Xlib.h>
#import <X11/Xatom.h>
#import <X11/Xutil.h>

// Global X11 error handler
static int x11ErrorHandler(Display *display, XErrorEvent *error)
{
    return 0; // Silently ignore X11 errors
}

@implementation DBusMenuPanelService

@synthesize menuDisplayView = _menuDisplayView;

- (instancetype)init
{
    self = [super init];
    if (self) {
        applicationMenus = [[NSMutableDictionary alloc] init];
        menuLayouts = [[NSMutableDictionary alloc] init];
        
        // Set up safer X11 error handling
        XSetErrorHandler(x11ErrorHandler);
        
        NSLog(@"DBusMenuPanelService: Initializing simple service");
    }
    return self;
}

- (void)dealloc
{
    [self stopService];
    [applicationMenus release];
    [menuLayouts release];
    [windowMonitorTimer invalidate];
    [super dealloc];
}

#pragma mark - Service Lifecycle

- (BOOL)startService
{
    NSLog(@"DBusMenuPanelService: Starting simple service (X11 properties only)...");
    
    // Skip D-Bus for now, just focus on X11 properties
    // This will help us see if your theme is setting properties at all
    
    [self startWindowMonitoring];
    
    NSLog(@"DBusMenuPanelService: Service started in simple mode");
    return YES;
}

- (void)stopService
{
    [windowMonitorTimer invalidate];
    windowMonitorTimer = nil;
    
    [applicationMenus removeAllObjects];
    [menuLayouts removeAllObjects];
}

#pragma mark - Window Monitoring

- (void)startWindowMonitoring
{
    NSLog(@"DBusMenuPanelService: Starting simple window monitoring...");
    
    // Check immediately, then every 3 seconds
    [self checkAllWindows];
    
    windowMonitorTimer = [NSTimer scheduledTimerWithTimeInterval:3.0
                                                          target:self
                                                        selector:@selector(checkAllWindows)
                                                        userInfo:nil
                                                         repeats:YES];
}

- (void)checkAllWindows
{
    Display *display = XOpenDisplay(NULL);
    if (!display) {
        NSLog(@"DBusMenuPanelService: Cannot open X display");
        return;
    }
    
    // Get the focused window
    Window focused;
    int revert;
    XGetInputFocus(display, &focused, &revert);
    
    NSLog(@"DBusMenuPanelService: === Window Check ===");
    NSLog(@"DBusMenuPanelService: Focused window: 0x%lx", (unsigned long)focused);
    
    // Skip invalid focus windows
    if (focused == None || focused == PointerRoot || focused == 1) {
        NSLog(@"DBusMenuPanelService: Skipping invalid focus window");
        XCloseDisplay(display);
        return;
    }
    
    // Get all top-level windows and check them
    [self scanTopLevelWindows:display focusedWindow:focused];
    
    XCloseDisplay(display);
}

- (void)scanTopLevelWindows:(Display *)display focusedWindow:(Window)focused
{
    Window root = DefaultRootWindow(display);
    Window dummyParent, dummyRoot;
    Window *children;
    unsigned int nChildren;
    
    if (XQueryTree(display, root, &dummyRoot, &dummyParent, &children, &nChildren) == Success) {
        NSLog(@"DBusMenuPanelService: Found %u top-level windows", nChildren);
        
        int interestingWindows = 0;
        for (unsigned int i = 0; i < nChildren; i++) {
            Window window = children[i];
            
            // Check if this window is mapped (visible)
            XWindowAttributes attrs;
            if (XGetWindowAttributes(display, window, &attrs) == Success && 
                attrs.map_state == IsViewable && attrs.class == InputOutput) {
                
                // Check if it has a window name or class (skip system windows)
                NSString *windowClass = [self getWindowClass:window display:display];
                NSString *windowName = [self getWindowName:window display:display];
                
                if (windowClass && ![windowClass isEqualToString:@"unknown.unknown"] &&
                    ![windowClass hasPrefix:@"."]) {
                    
                    interestingWindows++;
                    BOOL isFocused = (window == focused);
                    [self checkWindow:window display:display isFocused:isFocused];
                }
            }
        }
        
        NSLog(@"DBusMenuPanelService: Found %d interesting windows", interestingWindows);
        
        if (children) XFree(children);
    } else {
        NSLog(@"DBusMenuPanelService: Failed to query window tree");
    }
}

- (void)checkWindow:(Window)window display:(Display *)display isFocused:(BOOL)focused
{
    // Get window info
    NSString *windowClass = [self getWindowClass:window display:display];
    NSString *windowName = [self getWindowName:window display:display];
    
    // Only log interesting windows (skip system windows)
    if (!windowClass || [windowClass isEqualToString:@"unknown.unknown"]) {
        return;
    }
    
    NSLog(@"DBusMenuPanelService: %s Window 0x%lx: %@ (%@)", 
          focused ? "***" : "   ", (unsigned long)window, windowName, windowClass);
    
    // Check for menu properties
    BOOL hasMenuProperties = [self checkMenuProperties:window display:display];
    
    if (hasMenuProperties) {
        NSLog(@"DBusMenuPanelService: ✓ Found menu properties on window!");
        if (focused) {
            [self createFoundMenuDisplay:windowClass];
        }
    } else if (focused) {
        // Clear display if focused window has no menu
        [self displayMenu:nil inView:_menuDisplayView];
    }
}

- (NSString *)getWindowClass:(Window)window display:(Display *)display
{
    XClassHint classHint;
    memset(&classHint, 0, sizeof(classHint));
    
    if (XGetWindowAttributes(display, window, NULL) != Success) {
        return nil; // Window doesn't exist
    }
    
    if (XGetClassHint(display, window, &classHint) == Success) {
        NSString *result = [NSString stringWithFormat:@"%s.%s", 
                           classHint.res_class ? classHint.res_class : "unknown",
                           classHint.res_name ? classHint.res_name : "unknown"];
        if (classHint.res_class) XFree(classHint.res_class);
        if (classHint.res_name) XFree(classHint.res_name);
        return result;
    }
    
    return @"unknown.unknown";
}

- (NSString *)getWindowName:(Window)window display:(Display *)display
{
    char *windowName = NULL;
    if (XFetchName(display, window, &windowName) == Success && windowName) {
        NSString *result = [NSString stringWithUTF8String:windowName];
        XFree(windowName);
        return result;
    }
    return @"(no name)";
}

- (BOOL)checkMenuProperties:(Window)window display:(Display *)display
{
    // List of all possible menu-related properties
    NSArray *menuProperties = @[
        @"_DBUSMENU_SERVICE_NAME",
        @"_DBUSMENU_OBJECT_PATH",
        @"_GTK_APPLICATION_OBJECT_PATH",
        @"_GTK_WINDOW_OBJECT_PATH", 
        @"_GTK_APPLICATION_ID",
        @"_GTK_MENUBAR_OBJECT_PATH",
        @"_NET_WM_PID",
        @"_UNITY_OBJECT_PATH",
        @"_KDE_NET_WM_APPMENU_SERVICE_NAME",
        @"_KDE_NET_WM_APPMENU_OBJECT_PATH"
    ];
    
    BOOL foundAny = NO;
    
    for (NSString *propName in menuProperties) {
        NSString *value = [self getStringProperty:window 
                                         property:[propName UTF8String] 
                                          display:display];
        if (value && [value length] > 0) {
            NSLog(@"DBusMenuPanelService:     ✓ %@: %@", propName, value);
            foundAny = YES;
        }
    }
    
    if (!foundAny) {
        // Also scan for ANY property that might contain "menu" or "dbus"
        foundAny = [self scanForMenuRelatedProperties:window display:display];
    }
    
    return foundAny;
}

- (BOOL)scanForMenuRelatedProperties:(Window)window display:(Display *)display
{
    int nProps = 0;
    Atom *propList = XListProperties(display, window, &nProps);
    BOOL foundAny = NO;
    
    if (propList && nProps > 0) {
        for (int i = 0; i < nProps; i++) {
            char *atomName = XGetAtomName(display, propList[i]);
            if (atomName) {
                NSString *propName = [NSString stringWithUTF8String:atomName];
                NSString *lowerProp = [propName lowercaseString];
                
                if ([lowerProp containsString:@"menu"] || 
                    [lowerProp containsString:@"dbus"] ||
                    [lowerProp containsString:@"gtk"]) {
                    
                    NSString *value = [self getStringProperty:window 
                                                     property:atomName 
                                                      display:display];
                    NSLog(@"DBusMenuPanelService:      %@: %@", propName, 
                          value ? value : @"(binary/unreadable)");
                    foundAny = YES;
                }
                XFree(atomName);
            }
        }
        XFree(propList);
    }
    
    return foundAny;
}

- (NSString *)getStringProperty:(Window)window property:(const char *)propName display:(Display *)display
{
    Atom propAtom = XInternAtom(display, propName, True); // Only if exists
    if (propAtom == None) return nil;
    
    Atom actualType;
    int actualFormat;
    unsigned long nItems, bytesAfter;
    unsigned char *prop = NULL;
    
    int result = XGetWindowProperty(display, window, propAtom, 0, 1024, False, AnyPropertyType,
                                   &actualType, &actualFormat, &nItems, &bytesAfter, &prop);
    
    if (result == Success && prop && nItems > 0) {
        NSString *stringResult = nil;
        
        if (actualType == XA_STRING || actualFormat == 8) {
            // Create a safe null-terminated string
            char *safeProp = malloc(nItems + 1);
            if (safeProp) {
                memcpy(safeProp, prop, nItems);
                safeProp[nItems] = '\0';
                stringResult = [NSString stringWithUTF8String:safeProp];
                free(safeProp);
            }
        }
        
        XFree(prop);
        return stringResult;
    }
    
    return nil;
}

- (void)createFoundMenuDisplay:(NSString *)appName
{
    NSLog(@"DBusMenuPanelService: Creating 'found menu' display for %@", appName);
    
    // Create a simple test menu to show we found something
    NSMenu *testMenu = [[NSMenu alloc] initWithTitle:@"Menu Found"];
    
    NSMenuItem *item1 = [[NSMenuItem alloc] initWithTitle:[NSString stringWithFormat:@"%@ Menu", appName]
                                                   action:nil
                                            keyEquivalent:@""];
    [testMenu addItem:item1];
    [item1 release];
    
    NSMenuItem *item2 = [[NSMenuItem alloc] initWithTitle:@"Properties Found!"
                                                   action:nil
                                            keyEquivalent:@""];
    [testMenu addItem:item2];
    [item2 release];
    
    [self displayMenu:testMenu inView:_menuDisplayView];
    [testMenu release];
}

#pragma mark - Display Methods

- (void)refreshMenuDisplay
{
    [self checkAllWindows];
}

- (void)displayMenu:(NSMenu *)menu inView:(NSView *)view
{
    NSLog(@"DBusMenuPanelService: displayMenu called with menu: %@", 
          menu ? [menu title] : @"(nil)");
    
    // Clear existing content
    NSArray *subviews = [[view subviews] copy];
    for (NSView *subview in subviews) {
        [subview removeFromSuperview];
    }
    [subviews release];
    
    if (!menu || [menu numberOfItems] == 0) {
        NSLog(@"DBusMenuPanelService: Clearing menu display");
        [view setNeedsDisplay:YES];
        return;
    }
    
    NSLog(@"DBusMenuPanelService: Creating menu view for %ld items", (long)[menu numberOfItems]);
    
    // Create horizontal menu view
    NSMenuView *menuView = [[NSMenuView alloc] initWithFrame:[view bounds]];
    [menuView setMenu:menu];
    [menuView setHorizontal:YES];
    [menuView setInterfaceStyle:NSMacintoshInterfaceStyle];
    [menuView setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
    
    [menuView sizeToFit];
    [view addSubview:menuView];
    [menuView release];
    
    [view setNeedsDisplay:YES];
    
    NSLog(@"DBusMenuPanelService: ✓ Menu display completed");
}

@end
