include $(GNUSTEP_MAKEFILES)/common.make

APP_NAME = Panel
Panel_OBJC_FILES = main.m Panel.m MenuPanelService.m
Panel_HEADER_FILES = Panel.h MenuPanelService.h MenuPanelProtocol.h

# Fixed: Add proper X11 linking flags
Panel_LDFLAGS += -lX11
Panel_CPPFLAGS += -I/usr/include/X11

include $(GNUSTEP_MAKEFILES)/application.make
