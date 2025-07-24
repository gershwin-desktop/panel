#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>

@interface AppMenuPanelService : NSObject 
{
    NSView *_menuDisplayView;
    NSTimer *windowMonitorTimer;
    NSNumber *currentFocusedWindow;
    NSMutableDictionary *windowMenus;
    NSTask *appMenuRegistrarTask;
}

@property (nonatomic, strong) NSView *menuDisplayView;

// Service lifecycle
- (BOOL)startService;
- (void)stopService;

// Menu management
- (void)refreshMenuDisplay;
- (void)displayMenu:(NSMenu *)menu inView:(NSView *)view;

@end
