#import <AppKit/AppKit.h>
#import "AppMenuPanelService.h"

@interface Panel : NSObject
{
    NSWindow *panelWindow;
    NSView *contentView;
    AppMenuPanelService *menuService;
}

- (void)createPanel;
- (void)setupXWindowProperties;

@end
