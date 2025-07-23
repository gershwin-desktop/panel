#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>

@protocol GSMenuPanelService
- (void)registerApplication:(NSString *)appId;
- (void)unregisterApplication:(NSString *)appId;
- (void)setMainMenu:(in bycopy NSMenu *)menu forApplication:(NSString *)appId;
- (void)applicationDidBecomeActive:(NSString *)appId;
- (void)applicationDidResignActive:(NSString *)appId;
@end
