include $(GNUSTEP_MAKEFILES)/common.make

APP_NAME = Panel
Panel_OBJC_FILES = main.m Panel.m AppMenuPanelService.m
Panel_HEADER_FILES = Panel.h AppMenuPanelService.h

# Remove DBusKit dependency - we'll use dbus-send instead
Panel_LDFLAGS += -lX11
Panel_CPPFLAGS += -I/usr/include/X11 -I/usr/local/include/X11 -I/usr/X11R6/include -I/usr/local/include
Panel_CPPFLAGS += -DHAVE_X11=1

# Additional include paths for DBusKit (adjust paths as needed for FreeBSD)
Panel_CPPFLAGS += -I/usr/local/GNUstep/Local/Library/Headers

include $(GNUSTEP_MAKEFILES)/application.make
