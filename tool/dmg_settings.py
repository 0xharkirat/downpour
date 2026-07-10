# dmgbuild settings for Downpour.
#
# No custom background on purpose: Finder then renders its native window,
# which adapts to the viewer's appearance - Dark Mode gives a dark window with
# white labels, Light Mode a light window with black labels. A custom
# background picture forces black labels in BOTH modes (Finder limitation,
# see create-dmg #197).
#
# dmgbuild writes the .DS_Store directly, so this runs headless / in CI.
# Invoked from tool/release_macos.sh.
import os.path

app = defines['app']
appname = os.path.basename(app)

files = [app]
symlinks = {'Applications': '/Applications'}

format = 'UDZO'
compression_level = 9

# Native, appearance-adaptive window (no `background` set => backgroundType 0).
window_rect = ((300, 140), (620, 400))
default_view = 'icon-view'
icon_size = 128
text_size = 13
show_icon_preview = False
include_icon_view_settings = True
include_list_view_settings = False
icon_locations = {
    appname: (160, 200),
    'Applications': (460, 200),
}

# Brand the mounted volume + the .dmg file with the app icon.
_icon = defines.get('icon')
if _icon and os.path.exists(_icon):
    icon = _icon
