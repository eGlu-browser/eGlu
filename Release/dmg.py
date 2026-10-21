# The disk image's window, for dmgbuild (https://github.com/dmgbuild/dmgbuild),
# which writes the Finder's own layout file directly: no Finder to script and
# no window opening mid-build. Release/mac.sh passes the app's path in with -D.
# After the Mac's Search's own (its Installer/dmg.py): the app on the left,
# Applications on the right, to drag it to.

import os.path

app = defines["app"]
name = os.path.basename(app)

format = "UDZO"
files = [app]
symlinks = {"Applications": "/Applications"}

# The mounted volume wears the app's icon, where the app has one as a file.
icns = os.path.join(app, "Contents", "Resources", "AppIcon.icns")
if os.path.exists(icns):
    icon = icns

window_rect = ((200, 160), (560, 340))
default_view = "icon-view"
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
sidebar_width = 0

arrange_by = None
icon_size = 112
text_size = 13
label_pos = "bottom"
icon_locations = {
    name: (150, 150),
    "Applications": (410, 150),
}
