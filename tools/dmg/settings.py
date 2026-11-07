# dmgbuild settings for the Hoverbox install window.
# Usage: dmgbuild -s tools/dmg/settings.py -D app=path/to/Hoverbox.app -D background=path/to/background.tiff "Hoverbox" Hoverbox-macOS.dmg
# Icon positions are icon centers from the window's top-left; the arrow in
# render-background.swift sits between them.
import os.path

app = defines["app"]  # noqa: F821 (dmgbuild provides `defines`)
app_name = os.path.basename(app)

format = "UDZO"
files = [app]
symlinks = {"Applications": "/Applications"}
icon = os.path.join(app, "Contents", "Resources", "AppIcon.icns")

background = defines["background"]  # noqa: F821
window_rect = ((200, 120), (660, 400))
default_view = "icon-view"
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
show_icon_preview = False
include_icon_view_settings = True

icon_size = 112
text_size = 13
icon_locations = {
    app_name: (170, 212),
    "Applications": (490, 212),
}
