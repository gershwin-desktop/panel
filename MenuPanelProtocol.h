#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>

@protocol GSMenuPanelService
- (void)registerApplication:(NSString *)appId;
- (void)unregisterApplication:(NSString *)appId;
- (oneway void)setMainMenu:(in bycopy NSMenu *)menu forApplication:(in bycopy NSString *)appId;
- (oneway void)setMenuData:(in bycopy NSDictionary *)menuData forApplication:(in bycopy NSString *)appId;
- (void)applicationDidBecomeActive:(NSString *)appId;
- (void)applicationDidResignActive:(NSString *)appId;
@end
