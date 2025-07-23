#import "Panel.h"
#import <X11/Xlib.h>
#import <X11/Xatom.h>

#define PANEL_HEIGHT 28

@implementation Panel

- (instancetype)init
{
    self = [super init];
    if (self) {
        menuService = [[MenuPanelService alloc] init];
    }
    return self;
}

- (void)dealloc
{
    [menuService release];
    [super dealloc];
}

- (void)createPanel
{
    NSRect screenFrame = [[NSScreen mainScreen] frame];
    NSRect panelFrame = NSMakeRect(0, screenFrame.size.height - PANEL_HEIGHT, 
                                  screenFrame.size.width, PANEL_HEIGHT);
    
    panelWindow = [[NSWindow alloc] initWithContentRect:panelFrame
                                             styleMask:NSBorderlessWindowMask
                                               backing:NSBackingStoreBuffered
                                                 defer:NO];
    
    [panelWindow setLevel:NSScreenSaverWindowLevel];
    [panelWindow setBackgroundColor:[NSColor controlBackgroundColor]];
    [panelWindow setOpaque:YES];
    [panelWindow setCanHide:NO];
    [panelWindow setCollectionBehavior:NSWindowCollectionBehaviorCanJoinAllSpaces |
                                       NSWindowCollectionBehaviorStationary];
    
    contentView = [panelWindow contentView];
    [menuService setMenuDisplayView:contentView];
    
    [panelWindow makeKeyAndOrderFront:nil];
    
    [self performSelector:@selector(setupXWindowProperties) 
               withObject:nil 
               afterDelay:0.1];
    
    [menuService startService];
    
    NSLog(@"Panel created and service started");
}

- (void)setupXWindowProperties
{
    NSInteger windowNumber = [panelWindow windowNumber];
    Display *display = XOpenDisplay(NULL);
    if (!display) {
        NSLog(@"Failed to open X display");
        return;
    }
    
    Window xWindow = (Window)windowNumber;
    
    // Set window type to DOCK
    Atom wmWindowType = XInternAtom(display, "_NET_WM_WINDOW_TYPE", False);
    Atom wmWindowTypeDock = XInternAtom(display, "_NET_WM_WINDOW_TYPE_DOCK", False);
    XChangeProperty(display, xWindow, wmWindowType, XA_ATOM, 32,
                   PropModeReplace, (unsigned char*)&wmWindowTypeDock, 1);
    
    // Set window state
    Atom stateValues[] = {
        XInternAtom(display, "_NET_WM_STATE_SKIP_TASKBAR", False),
        XInternAtom(display, "_NET_WM_STATE_STICKY", False),
        XInternAtom(display, "_NET_WM_STATE_ABOVE", False)
    };
    Atom stateAtom = XInternAtom(display, "_NET_WM_STATE", False);
    XChangeProperty(display, xWindow, stateAtom, XA_ATOM, 32,
                   PropModeReplace, (unsigned char*)stateValues, 3);
    
    // Set struts to reserve screen space
    NSRect screenFrame = [[NSScreen mainScreen] frame];
    long strutPartial[12] = {
        0, 0, PANEL_HEIGHT, 0,
        0, 0,
        0, 0,
        0, (long)screenFrame.size.width-1,
        0, 0
    };
    
    Atom strutPartialAtom = XInternAtom(display, "_NET_WM_STRUT_PARTIAL", False);
    XChangeProperty(display, xWindow, strutPartialAtom, XA_CARDINAL, 32,
                   PropModeReplace, (unsigned char*)strutPartial, 12);
    
    long strut[4] = {0, 0, PANEL_HEIGHT, 0};
    Atom strutAtom = XInternAtom(display, "_NET_WM_STRUT", False);
    XChangeProperty(display, xWindow, strutAtom, XA_CARDINAL, 32,
                   PropModeReplace, (unsigned char*)strut, 4);
    
    XFlush(display);
    XCloseDisplay(display);
    
    NSLog(@"X11 window properties configured");
}

@end
