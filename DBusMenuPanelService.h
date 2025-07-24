#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#import <DBusKit/DBusKit.h>

// D-Bus menu service interface based on com.canonical.dbusmenu
@interface DBusMenuPanelService : NSObject 
{
    DKPort *sessionBus;
    DKProxy *registrarProxy;
    NSMutableDictionary *applicationMenus; // windowId -> DKProxy
    NSMutableDictionary *menuLayouts;     // windowId -> NSMenu
    NSString *activeWindowId;
    NSView *_menuDisplayView;
    
    // Window monitoring
    NSTimer *windowMonitorTimer;
    NSNumber *currentFocusedWindow;
}

@property (nonatomic, strong) NSView *menuDisplayView;

// Service lifecycle
- (BOOL)startService;
- (void)stopService;

// Menu management
- (void)refreshMenuDisplay;
- (void)handleWindowFocusChanged:(NSNumber *)windowId;

// Internal menu handling
- (void)fetchMenuForWindow:(NSNumber *)windowId;
- (NSMenu *)buildMenuFromLayout:(NSDictionary *)layout;
- (void)displayMenu:(NSMenu *)menu inView:(NSView *)view;

@end
