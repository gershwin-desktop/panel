#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#import "MenuPanelProtocol.h"

@interface MenuPanelService : NSObject <GSMenuPanelService>
{
    NSMutableDictionary *applicationMenus;
    NSConnection *serverConnection;
    NSString *activeApplicationId;
    NSView *_menuDisplayView;  // Changed to match @property synthesized name
}

@property (nonatomic, strong) NSView *menuDisplayView;

- (void)startService;
- (void)stopService;
- (void)refreshMenuDisplay;

@end
