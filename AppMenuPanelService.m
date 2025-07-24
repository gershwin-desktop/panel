#import "AppMenuPanelService.h"
#import <X11/Xlib.h>
#import <X11/Xatom.h>
#import <X11/Xutil.h>

// This version queries the registrar directly and checks related windows

@implementation AppMenuPanelService

@synthesize menuDisplayView = _menuDisplayView;

- (instancetype)init
{
    self = [super init];
    if (self) {
        windowMenus = [[NSMutableDictionary alloc] init];
        NSLog(@"AppMenuPanelService: Initializing registrar-direct service");
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
    NSLog(@"AppMenuPanelService: Starting registrar-direct service...");
    
    // Show initial status
    [self displayInitialStatus];
    
    // Start monitoring window focus
    [self startWindowMonitoring];
    
    NSLog(@"AppMenuPanelService: Service started");
    return YES;
}

- (void)displayInitialStatus
{
    if (!_menuDisplayView) return;
    
    NSTextField *statusLabel = [[NSTextField alloc] initWithFrame:[_menuDisplayView bounds]];
    [statusLabel setStringValue:@"Global Menu Panel - Starting (Enhanced Mode)..."];
    [statusLabel setAlignment:NSCenterTextAlignment];
    [statusLabel setTextColor:[NSColor controlTextColor]];
    [statusLabel setBackgroundColor:[NSColor clearColor]];
    [statusLabel setBezeled:NO];
    [statusLabel setEditable:NO];
    [statusLabel setSelectable:NO];
    [statusLabel setFont:[NSFont systemFontOfSize:12]];
    [statusLabel setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
    
    [_menuDisplayView addSubview:statusLabel];
    [statusLabel release];
    [_menuDisplayView setNeedsDisplay:YES];
    
    [self performSelector:@selector(updateStatusToReady) withObject:nil afterDelay:1.0];
}

- (void)updateStatusToReady
{
    if (!_menuDisplayView) return;
    
    NSArray *subviews = [_menuDisplayView subviews];
    for (NSView *subview in subviews) {
        if ([subview isKindOfClass:[NSTextField class]]) {
            NSTextField *label = (NSTextField *)subview;
            [label setStringValue:@"Global Menu Panel - Ready (Enhanced Mode)"];
            [_menuDisplayView setNeedsDisplay:YES];
            break;
        }
    }
}

- (void)stopService
{
    [windowMonitorTimer invalidate];
    windowMonitorTimer = nil;
    [windowMenus removeAllObjects];
}

#pragma mark - Window Monitoring

- (void)startWindowMonitoring
{
    NSLog(@"AppMenuPanelService: Starting window monitoring...");
    windowMonitorTimer = [NSTimer scheduledTimerWithTimeInterval:2.0
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
    NSLog(@"AppMenuPanelService: Checking window 0x%lx and related windows...", (unsigned long)window);
    
    @try {
        // Get window info for logging
        NSString *windowName = [self getWindowName:window display:display];
        NSString *windowClass = [self getWindowClass:window display:display];
        
        NSLog(@"AppMenuPanelService: Focused window: %@ (%@)", windowName, windowClass);
        
        // Get all windows for this application and check them all
        NSArray *relatedWindows = [self findRelatedWindows:window display:display];
        
        NSLog(@"AppMenuPanelService: Found %lu related windows to check", (unsigned long)[relatedWindows count]);
        
        for (NSNumber *windowId in relatedWindows) {
            Window checkWindow = [windowId unsignedLongValue];
            NSString *checkName = [self getWindowName:checkWindow display:display];
            NSLog(@"AppMenuPanelService: Checking related window 0x%lx (%@)", (unsigned long)checkWindow, checkName);
            
            if ([self queryRegistrarForWindow:checkWindow]) {
                NSLog(@"AppMenuPanelService: ✓ Found menu on related window 0x%lx", (unsigned long)checkWindow);
                return; // Found a menu, stop searching
            }
        }
        
        NSLog(@"AppMenuPanelService: No menu found on any related window");
        [self displayMenu:nil inView:_menuDisplayView];
        
    }
    @catch (NSException *e) {
        NSLog(@"AppMenuPanelService: Exception in handleWindowFocusChanged: %@", e);
        [self displayMenu:nil inView:_menuDisplayView];
    }
}

- (NSArray *)findRelatedWindows:(Window)focusedWindow display:(Display *)display
{
    NSMutableArray *relatedWindows = [NSMutableArray array];
    
    // Always check the focused window first
    [relatedWindows addObject:[NSNumber numberWithUnsignedLong:(unsigned long)focusedWindow]];
    
    // Get the window class of the focused window
    NSString *focusedClass = [self getWindowClass:focusedWindow display:display];
    NSLog(@"AppMenuPanelService: Looking for windows matching class: %@", focusedClass);
    
    // Get all top-level windows
    Window root = DefaultRootWindow(display);
    Window dummyParent, dummyRoot;
    Window *children;
    unsigned int nChildren;
    
    if (XQueryTree(display, root, &dummyRoot, &dummyParent, &children, &nChildren) == Success) {
        for (unsigned int i = 0; i < nChildren; i++) {
            Window window = children[i];
            
            // Skip the focused window (already added)
            if (window == focusedWindow) continue;
            
            // Check if this window belongs to the same application
            NSString *windowClass = [self getWindowClass:window display:display];
            NSString *windowName = [self getWindowName:window display:display];
            
            // Match by class name or if it's a Terminal-related window
            if ([windowClass isEqualToString:focusedClass] || 
                [windowClass containsString:@"Terminal"] ||
                [windowName containsString:@"Terminal"]) {
                
                NSLog(@"AppMenuPanelService: Found related window 0x%lx: %@ (%@)", 
                      (unsigned long)window, windowName, windowClass);
                [relatedWindows addObject:[NSNumber numberWithUnsignedLong:(unsigned long)window]];
            }
        }
        XFree(children);
    }
    
    return relatedWindows;
}

- (BOOL)queryRegistrarForWindow:(Window)window
{
    // Try both registrar services we found
    NSArray *registrars = @[
        @"com.canonical.AppMenu.Registrar",
        @"org.valapanel.AppMenu.Registrar"
    ];
    
    for (NSString *registrarService in registrars) {
        if ([self queryRegistrar:registrarService forWindow:window]) {
            return YES; // Found a menu
        }
    }
    
    return NO; // No menu found
}

- (BOOL)queryRegistrar:(NSString *)registrarService forWindow:(Window)window
{
    // Use dbus-send to query the registrar for this window
    NSTask *task = [[NSTask alloc] init];
    [task setLaunchPath:@"/usr/local/bin/dbus-send"];
    [task setArguments:@[
        @"--session",
        [NSString stringWithFormat:@"--dest=%@", registrarService],
        @"--type=method_call",
        @"--print-reply",
        @"/com/canonical/AppMenu/Registrar",
        @"com.canonical.AppMenu.Registrar.GetMenuForWindow",
        [NSString stringWithFormat:@"uint32:%lu", (unsigned long)window]
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
            
            // Parse the response to extract service and path
            NSString *serviceName = [self extractServiceFromDBusOutput:output];
            NSString *objectPath = [self extractPathFromDBusOutput:output];
            
            if (serviceName && objectPath && 
                ![serviceName isEqualToString:@""] && ![objectPath isEqualToString:@"/"]) {
                NSLog(@"AppMenuPanelService: ✓ Found menu via registrar: %@ -> %@:%@", 
                      registrarService, serviceName, objectPath);
                
                [self fetchMenuFromService:serviceName objectPath:objectPath window:window];
                [output release];
                [task release];
                return YES;
            }
            
            [output release];
        }
        
    }
    @catch (NSException *e) {
        NSLog(@"AppMenuPanelService: Exception querying registrar %@: %@", registrarService, e);
    }
    
    [task release];
    return NO;
}

- (NSString *)extractServiceFromDBusOutput:(NSString *)output
{
    // Look for service name in D-Bus output
    // Format: string "service.name"
    NSRange serviceRange = [output rangeOfString:@"string \""];
    if (serviceRange.location != NSNotFound) {
        NSString *remainder = [output substringFromIndex:serviceRange.location + serviceRange.length];
        NSRange endRange = [remainder rangeOfString:@"\""];
        if (endRange.location != NSNotFound) {
            return [remainder substringToIndex:endRange.location];
        }
    }
    return nil;
}

- (NSString *)extractPathFromDBusOutput:(NSString *)output
{
    // Look for object path in D-Bus output (usually second string)
    NSArray *lines = [output componentsSeparatedByString:@"\n"];
    NSUInteger stringCount = 0;
    
    for (NSString *line in lines) {
        if ([line containsString:@"string \""]) {
            stringCount++;
            if (stringCount == 2) { // Second string should be the path
                NSRange startRange = [line rangeOfString:@"string \""];
                if (startRange.location != NSNotFound) {
                    NSString *remainder = [line substringFromIndex:startRange.location + startRange.length];
                    NSRange endRange = [remainder rangeOfString:@"\""];
                    if (endRange.location != NSNotFound) {
                        return [remainder substringToIndex:endRange.location];
                    }
                }
            }
        } else if ([line containsString:@"object path \""]) {
            NSRange startRange = [line rangeOfString:@"object path \""];
            if (startRange.location != NSNotFound) {
                NSString *remainder = [line substringFromIndex:startRange.location + startRange.length];
                NSRange endRange = [remainder rangeOfString:@"\""];
                if (endRange.location != NSNotFound) {
                    return [remainder substringToIndex:endRange.location];
                }
            }
        }
    }
    return nil;
}

#pragma mark - Helper Methods

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
        return @"(exception)";
    }
}

- (NSString *)getWindowClass:(Window)window display:(Display *)display
{
    @try {
        XClassHint classHint;
        memset(&classHint, 0, sizeof(classHint));
        
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
        return @"(exception)";
    }
}

- (void)fetchMenuFromService:(NSString *)serviceName objectPath:(NSString *)objectPath window:(Window)window
{
    NSLog(@"AppMenuPanelService: Fetching menu from %@:%@", serviceName, objectPath);
    
    NSTask *task = [[NSTask alloc] init];
    [task setLaunchPath:@"/usr/local/bin/dbus-send"];
    [task setArguments:@[
        @"--session",
        [NSString stringWithFormat:@"--dest=%@", serviceName],
        @"--type=method_call",
        @"--print-reply",
        objectPath,
        @"com.canonical.dbusmenu.GetLayout",
        @"int32:0",
        @"int32:-1",
        @"array:string:"
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
            
            NSLog(@"AppMenuPanelService: ✓ Got menu layout");
            
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
    if (!output || ![output containsString:@"string"]) {
        return nil;
    }
    
    NSMenu *menu = [[NSMenu alloc] initWithTitle:@"Application Menu"];
    
    NSArray *lines = [output componentsSeparatedByString:@"\n"];
    for (NSString *line in lines) {
        if ([line containsString:@"string \""] && [line containsString:@"label"]) {
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

- (void)refreshMenuDisplay
{
    [self checkFocusedWindow];
}

- (void)displayMenu:(NSMenu *)menu inView:(NSView *)view
{
    NSLog(@"AppMenuPanelService: displayMenu called with menu: %@", 
          menu ? [menu title] : @"(nil)");
    
    NSArray *subviews = [[view subviews] copy];
    for (NSView *subview in subviews) {
        [subview removeFromSuperview];
    }
    [subviews release];
    
    if (!menu || [menu numberOfItems] == 0) {
        NSTextField *statusLabel = [[NSTextField alloc] initWithFrame:[view bounds]];
        [statusLabel setStringValue:@"Global Menu Panel - No menu found (Enhanced Mode)"];
        [statusLabel setAlignment:NSCenterTextAlignment];
        [statusLabel setTextColor:[NSColor controlTextColor]];
        [statusLabel setBackgroundColor:[NSColor clearColor]];
        [statusLabel setBezeled:NO];
        [statusLabel setEditable:NO];
        [statusLabel setSelectable:NO];
        [statusLabel setFont:[NSFont systemFontOfSize:12]];
        [statusLabel setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
        
        [view addSubview:statusLabel];
        [statusLabel release];
        [view setNeedsDisplay:YES];
        return;
    }
    
    NSView *containerView = [[NSView alloc] initWithFrame:[view bounds]];
    [containerView setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
    
    NSTextField *statusLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(5, 0, 200, [view bounds].size.height)];
    [statusLabel setStringValue:[NSString stringWithFormat:@"Menu: %@ (%ld items)", 
                                 [menu title], (long)[menu numberOfItems]]];
    [statusLabel setAlignment:NSLeftTextAlignment];
    [statusLabel setTextColor:[NSColor controlTextColor]];
    [statusLabel setBackgroundColor:[NSColor clearColor]];
    [statusLabel setBezeled:NO];
    [statusLabel setEditable:NO];
    [statusLabel setSelectable:NO];
    [statusLabel setFont:[NSFont systemFontOfSize:10]];
    [statusLabel setAutoresizingMask:NSViewMaxXMargin];
    
    [containerView addSubview:statusLabel];
    [statusLabel release];
    
    NSRect menuFrame = NSMakeRect(210, 0, [view bounds].size.width - 215, [view bounds].size.height);
    NSMenuView *menuView = [[NSMenuView alloc] initWithFrame:menuFrame];
    [menuView setMenu:menu];
    [menuView setHorizontal:YES];
    [menuView setInterfaceStyle:NSMacintoshInterfaceStyle];
    [menuView setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
    
    [menuView sizeToFit];
    [containerView addSubview:menuView];
    [menuView release];
    
    [view addSubview:containerView];
    [containerView release];
    
    [view setNeedsDisplay:YES];
    
    NSLog(@"AppMenuPanelService: ✓ Menu display completed");
}

@end
