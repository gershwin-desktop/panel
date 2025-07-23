#import <AppKit/AppKit.h>
#import "Panel.h"

int main(int argc, const char *argv[])
{
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    
    [NSApplication sharedApplication];
    
    Panel *panel = [[Panel alloc] init];
    [panel createPanel];
    
    [NSApp run];
    
    [panel release];
    [pool release];
    return 0;
}
