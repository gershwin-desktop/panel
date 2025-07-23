#import <AppKit/AppKit.h>
#import "MenuPanelService.h"

@interface Panel : NSObject
{
    NSWindow *panelWindow;
    NSView *contentView;
    MenuPanelService *menuService;
}

- (void)createPanel;
- (void)setupXWindowProperties;

@end
