#import "AppMenuPanelService.h"
#import <X11/Xlib.h>
#import <X11/Xatom.h>
#import <X11/Xutil.h>

// Global X11 error handler
static int x11ErrorHandler(Display *display, XErrorEvent *error)
{
    return 0; // Silently ignore X11 errors
}

@implementation AppMenuPanelService

@synthesize menuDisplayView = _menuDisplayView;

- (instancetype)init
{
    self = [super init];
    if (self) {
        windowMenus = [[NSMutableDictionary alloc] init];
        
        // Set up X11 error handling
        XSetErrorHandler(x11ErrorHandler);
        
        NSLog(@"AppMenuPanelService: Initializing appmenu-registrar based service");
    }
    return self;
}

- (void)dealloc
{
    [self stopService];
    [windowMenus release];
    [windowMonitorTimer invalidate];
    [super dealloc];
}

#pragma mark - Service Lifecycle

- (BOOL)startService
{
    NSLog(@"AppMenuPanelService: Starting appmenu-registrar based service...");
    
    // Check if appmenu-registrar is running
    if (![self checkAppMenuRegistrar]) {
        NSLog(@"AppMenuPanelService: appmenu-registrar not found, trying to start it...");
        [self startAppMenuRegistrar];
    }
    
    // Start monitoring window focus
    [self startWindowMonitoring];
    
    NSLog(@"AppMenuPanelService: Service started");
    return YES;
}

- (BOOL)checkAppMenuRegistrar
{
    // Check if the registrar service is available on D-Bus
    NSTask *task = [[NSTask alloc] init];
    [task setLaunchPath:@"/usr/local/bin/dbus-send"];
    [task setArguments:@[
        @"--session",
        @"--dest=com.canonical.AppMenu.Registrar",
        @"--type=method_call",
        @"--print-reply",
        @"/com/canonical/AppMenu/Registrar",
        @"org.freedesktop.DBus.Introspectable.Introspect"
    ]];
    
    NSPipe *pipe = [NSPipe pipe];
    [task setStandardOutput:pipe];
    [task setStandardError:pipe];
    
    @try {
        [task launch];
        [task waitUntilExit];
        
        BOOL success = ([task terminationStatus] == 0);
        NSLog(@"AppMenuPanelService: appmenu-registrar check: %@", success ? @"found" : @"not found");
        [task release];
        return success;
    }
    @catch (NSException *e) {
        NSLog(@"AppMenuPanelService: Exception checking registrar: %@", e);
        [task release];
        return NO;
    }
}

- (void)startAppMenuRegistrar
{
    // Try to start appmenu-registrar if it's available
    NSString *registrarPath = nil;
    NSArray *possiblePaths = @[
        @"/usr/local/bin/appmenu-registrar",
        @"/usr/bin/appmenu-registrar",
        @"/opt/local/bin/appmenu-registrar"
    ];
    
    for (NSString *path in possiblePaths) {
        if ([[NSFileManager defaultManager] fileExistsAtPath:path]) {
            registrarPath = path;
            break;
        }
    }
    
    if (!registrarPath) {
        NSLog(@"AppMenuPanelService: appmenu-registrar binary not found");
        return;
    }
    
    NSLog(@"AppMenuPanelService: Starting appmenu-registrar at %@", registrarPath);
    
    appMenuRegistrarTask = [[NSTask alloc] init];
    [appMenuRegistrarTask setLaunchPath:registrarPath];
    
    @try {
        [appMenuRegistrarTask launch];
        NSLog(@"AppMenuPanelService: appmenu-registrar started with PID %d", 
              [appMenuRegistrarTask processIdentifier]);
        
        // Give it a moment to start
        sleep(1);
    }
    @catch (NSException *e) {
        NSLog(@"AppMenuPanelService: Failed to start appmenu-registrar: %@", e);
        [appMenuRegistrarTask release];
        appMenuRegistrarTask = nil;
    }
}

- (void)stopService
{
    [windowMonitorTimer invalidate];
    windowMonitorTimer = nil;
    
    [windowMenus removeAllObjects];
    
    if (appMenuRegistrarTask && [appMenuRegistrarTask isRunning]) {
        [appMenuRegistrarTask terminate];
        [appMenuRegistrarTask release];
        appMenuRegistrarTask = nil;
    }
}

#pragma mark - Window Monitoring

- (void)startWindowMonitoring
{
    NSLog(@"AppMenuPanelService: Starting window monitoring...");
    windowMonitorTimer = [NSTimer scheduledTimerWithTimeInterval:1.0
                                                          target:self
                                                        selector:@selector(checkFocusedWindow)
                                                        userInfo:nil
                                                         repeats:YES];
}

- (void)checkFocusedWindow
{
    Display *display = XOpenDisplay(NULL);
    if (!display) return;
    
    Window focused;
    int revert;
    XGetInputFocus(display, &focused, &revert);
    
    if (focused == None || focused == PointerRoot || focused == 1) {
        XCloseDisplay(display);
        return;
    }
    
    NSNumber *windowId = [NSNumber numberWithUnsignedLong:(unsigned long)focused];
    
    BOOL windowChanged = NO;
    if (currentFocusedWindow == nil) {
        windowChanged = YES;
    } else if (![windowId isEqualToNumber:currentFocusedWindow]) {
        windowChanged = YES;
    }
    
    if (windowChanged) {
        NSLog(@"AppMenuPanelService: Window focus changed to: 0x%lx", (unsigned long)focused);
        [currentFocusedWindow release];
        currentFocusedWindow = [windowId retain];
        
        [self handleWindowFocusChanged:focused display:display];
    }
    
    XCloseDisplay(display);
}

- (void)handleWindowFocusChanged:(Window)window display:(Display *)display
{
    NSLog(@"AppMenuPanelService: handleWindowFocusChanged called for window 0x%lx", (unsigned long)window);
    
    @try {
        // Check if window still exists
        XWindowAttributes attrs;
        if (XGetWindowAttributes(display, window, &attrs) != Success) {
            NSLog(@"AppMenuPanelService: Window 0x%lx no longer exists", (unsigned long)window);
            [self displayMenu:nil inView:_menuDisplayView];
            return;
        }
        
        // Get window info for logging
        NSString *windowClass = [self getWindowClass:window display:display];
        NSString *windowName = [self getWindowName:window display:display];
        
        NSLog(@"AppMenuPanelService: Focused window: %@ (%@)", windowName, windowClass);
        
        // Check if this window has menu properties set by your theme
        NSString *serviceName = [self getMenuServiceForWindow:window display:display];
        NSString *objectPath = [self getMenuObjectPathForWindow:window display:display];
        
        if (serviceName && objectPath && [serviceName length] > 0 && [objectPath length] > 0) {
            NSLog(@"AppMenuPanelService: ✓ Found menu: service=%@ path=%@", serviceName, objectPath);
            [self fetchMenuFromService:serviceName objectPath:objectPath window:window];
        } else {
            NSLog(@"AppMenuPanelService: ✗ No menu properties found");
            [self displayMenu:nil inView:_menuDisplayView];
        }
    }
    @catch (NSException *e) {
        NSLog(@"AppMenuPanelService: Exception in handleWindowFocusChanged: %@", e);
        [self displayMenu:nil inView:_menuDisplayView];
    }
}

#pragma mark - X11 Property Reading

- (NSString *)getWindowClass:(Window)window display:(Display *)display
{
    @try {
        XClassHint classHint;
        memset(&classHint, 0, sizeof(classHint));
        
        // Check if window exists first
        XWindowAttributes attrs;
        if (XGetWindowAttributes(display, window, &attrs) != Success) {
            return @"(inaccessible)";
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
    @catch (NSException *e) {
        NSLog(@"AppMenuPanelService: Exception in getWindowClass: %@", e);
        return @"(exception)";
    }
}

- (NSString *)getWindowName:(Window)window display:(Display *)display
{
    @try {
        char *windowName = NULL;
        if (XFetchName(display, window, &windowName) == Success && windowName) {
            NSString *result = [NSString stringWithUTF8String:windowName];
            XFree(windowName);
            return result;
        }
        return @"(no name)";
    }
    @catch (NSException *e) {
        NSLog(@"AppMenuPanelService: Exception in getWindowName: %@", e);
        return @"(exception)";
    }
}

- (NSString *)getMenuServiceForWindow:(Window)window display:(Display *)display
{
    return [self getStringProperty:window property:"_DBUSMENU_SERVICE_NAME" display:display];
}

- (NSString *)getMenuObjectPathForWindow:(Window)window display:(Display *)display
{
    return [self getStringProperty:window property:"_DBUSMENU_OBJECT_PATH" display:display];
}

- (NSString *)getStringProperty:(Window)window property:(const char *)propName display:(Display *)display
{
    Atom propAtom = XInternAtom(display, propName, True);
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

#pragma mark - Menu Fetching via dbus-send

- (void)fetchMenuFromService:(NSString *)serviceName objectPath:(NSString *)objectPath window:(Window)window
{
    NSLog(@"AppMenuPanelService: Fetching menu from %@:%@", serviceName, objectPath);
    
    // Use dbus-send to call GetLayout method
    NSTask *task = [[NSTask alloc] init];
    [task setLaunchPath:@"/usr/local/bin/dbus-send"];
    [task setArguments:@[
        @"--session",
        [NSString stringWithFormat:@"--dest=%@", serviceName],
        @"--type=method_call",
        @"--print-reply",
        objectPath,
        @"com.canonical.dbusmenu.GetLayout",
        @"int32:0",    // parent ID
        @"int32:-1",   // recursion depth
        @"array:string:" // property names (empty)
    ]];
    
    NSPipe *pipe = [NSPipe pipe];
    [task setStandardOutput:pipe];
    [task setStandardError:pipe];
    
    @try {
        [task launch];
        [task waitUntilExit];
        
        if ([task terminationStatus] == 0) {
            NSFileHandle *handle = [pipe fileHandleForReading];
            NSData *data = [handle readDataToEndOfFile];
            NSString *output = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
            
            NSLog(@"AppMenuPanelService: ✓ Got menu layout:");
            NSLog(@"%@", output);
            
            // Parse the D-Bus output and create a menu
            NSMenu *menu = [self parseDBusMenuOutput:output];
            if (menu) {
                [windowMenus setObject:menu forKey:@(window)];
                [self displayMenu:menu inView:_menuDisplayView];
            }
            
            [output release];
        } else {
            NSLog(@"AppMenuPanelService: ✗ Failed to get menu layout");
        }
        
    }
    @catch (NSException *e) {
        NSLog(@"AppMenuPanelService: Exception fetching menu: %@", e);
    }
    
    [task release];
}

- (NSMenu *)parseDBusMenuOutput:(NSString *)output
{
    // Simple parser for dbus-send output
    // This is a basic implementation - in production you'd want a proper D-Bus library
    
    if (!output || ![output containsString:@"string"]) {
        return nil;
    }
    
    NSMenu *menu = [[NSMenu alloc] initWithTitle:@"Application Menu"];
    
    // Look for menu item labels in the D-Bus output
    NSArray *lines = [output componentsSeparatedByString:@"\n"];
    for (NSString *line in lines) {
        if ([line containsString:@"string \""] && [line containsString:@"label"]) {
            // Extract menu item label
            NSRange startRange = [line rangeOfString:@"string \""];
            if (startRange.location != NSNotFound) {
                NSString *remainder = [line substringFromIndex:startRange.location + startRange.length];
                NSRange endRange = [remainder rangeOfString:@"\""];
                if (endRange.location != NSNotFound) {
                    NSString *label = [remainder substringToIndex:endRange.location];
                    if ([label length] > 0 && ![label hasPrefix:@"_"]) {
                        NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:label
                                                                      action:nil
                                                               keyEquivalent:@""];
                        [menu addItem:item];
                        [item release];
                        NSLog(@"AppMenuPanelService: Added menu item: %@", label);
                    }
                }
            }
        }
    }
    
    if ([menu numberOfItems] == 0) {
        [menu release];
        return nil;
    }
    
    return [menu autorelease];
}

#pragma mark - Display Methods

- (void)refreshMenuDisplay
{
    // Re-check the current window
    [self checkFocusedWindow];
}

- (void)displayMenu:(NSMenu *)menu inView:(NSView *)view
{
    NSLog(@"AppMenuPanelService: displayMenu called with menu: %@", 
          menu ? [menu title] : @"(nil)");
    
    // Clear existing content
    NSArray *subviews = [[view subviews] copy];
    for (NSView *subview in subviews) {
        [subview removeFromSuperview];
    }
    [subviews release];
    
    if (!menu || [menu numberOfItems] == 0) {
        NSLog(@"AppMenuPanelService: Clearing menu display");
        [view setNeedsDisplay:YES];
        return;
    }
    
    NSLog(@"AppMenuPanelService: Creating menu view for %ld items", (long)[menu numberOfItems]);
    
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
    
    NSLog(@"AppMenuPanelService: ✓ Menu display completed");
}

@end
