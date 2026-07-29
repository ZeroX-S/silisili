# Upstream sources

- wiliwili 1.6.0: https://github.com/xfangfang/wiliwili
  commit `88e5876bea9502d06f46a8656e3530684d3aaf7d`
- Borealis submodule commit:
  `5f08b286f3df737f3321d2247a6fe633fcead03c`
- Sailfish SDK target `SailfishOS-5.0.0.62-aarch64`
- Sailfish SDK tooling `SailfishOS-5.0.0.62-i486`
- OpenSSL 3.0.16 commit
  `fa1e5dfb142bb1c26c3c38a10aafa7a095df52e5`
- curl 8.9.1 commit `83bedbd730d62b83744cc26fa0433d3f6e2e4cd6`
- libass 0.17.3 commit `e46aedea0a0d17da4c4ef49d84b94a7994664ab5`
- libplacebo 6.338.2 commit `64c1954570f1cd57f8570a57e51fb0249b57bb90`
- mpv 0.37.0 commit `818ce7c51a6b9179307950e919983e0909942098`
- FFmpeg 5.1.6 commit `6338d19eb349e23a2004eb6cdd863bdef454572d`
- Sailfish GCC package family 10.3.1, providing `GLIBCXX_3.4.28` and
  `CXXABI_1.3.12`
- Complete silisili Sailfish source patch (application, Borealis, and GLFW):
  `patches/silisili-sailfish-mobile.patch`
  SHA-256
  `2f50d87181f42331955e1f332754ad9e8047662c31d1c29c219f2736dbd943e5`.
- Mobile interaction reference: https://github.com/0xjax/bilibili-mobile
  commit `1e868592c31463b90d4db4d3e6e9bccd3e4ccb32`. It is a userscript and no
  source code is included; only its complete search/menu/history/activity
  reachability was used as an information-architecture reference.
- Sailfish 5.1 z1.5 media-player launcher template SHA-256:
  `a626c13264226d0f8060d773d99038f72c598d879d8823b2fd9efb85268d2e9a`

The Sailfish package changes the resource prefix, ELF RPATH, and
private-runtime packaging. A locally built GPL-3.0-or-later AArch64 ELF
launcher replaces Lipstick's compositor-only EGL environment with Wayland
before executing the adapted upstream binary. The application, OpenSSL, curl,
FFmpeg, libass, libplacebo, and mpv are compiled against the Sailfish OS
5.0.0.62 target. The private FFmpeg build includes HTTPS media transport;
GCC 10 libstdc++ remains a system library. The release gate rejects payloads
newer than `GLIBC_2.30`, `GLIBCXX_3.4.28`, or
`CXXABI_1.3.12`, so one package supports Sailfish OS 5.0 and 5.1. No service
credentials, DRM bypass, or proprietary decoders are included.

The Sailfish window ignores saved desktop geometry and starts as a compositor
fullscreen Wayland surface. Its bundled GLFW client binds Qt Wayland's
BSD-licensed `qt_surface_extension` protocol directly, so no Qt runtime is
added to the application package.

The Sailfish build fixes the logical baseline at 640x360, making controls and
text 1.5 times larger than the former 960-pixel short edge. Common video grids
use 2 columns in portrait and 4 in landscape, with phone-sized navigation,
spacing, OSD, and touch targets. Lists with an existing refresh action also
refresh after a 64-unit downward pull from their top boundary. Saved desktop
UI-scale values are ignored.

Search uses Sailfish's system input method directly. The television alphabet
grid, controller Y shortcut and hint, and its settings toggle are disabled on
the phone build. A persistent header exposes search, messages, and settings
from Home, Activity, and Me without covering the channel row. Those three
primary pages use a fixed bottom touch tab bar; nested screens continue to use
the native activity stack and Back behavior. Every shared text and numeric
input page activates the system keyboard after becoming visible, retries once
after compositor focus settles, and exposes fixed touch Back and OK controls.
Search results place the editable query in a separate row above their category
tabs.

The bundled GLFW/Borealis input path preserves native Wayland finger IDs and
cancellation. The player uses touch-first controls: tap toggles the OSD, a
center double tap toggles playback, and horizontal drag previews a seek and
only commits on release. Additional fingers cancel the active single-finger
gesture rather than changing the media crop.
Physical joystick/gamepad initialization, callbacks, polling, mapping data,
controller hints/settings, and controller-only font resources are disabled or
not packaged. The Sailfish hint gallery retains only the generic touch-oriented
`hint_silisili.png`; the two gamepad instruction images are removed. System
Back, keyboard text entry, and accessibility activation remain available.
The compact touch OSD also bypasses Borealis custom gamepad navigation routes,
because its hidden volume and danmaku-setting controls are intentionally not
focusable.

The phone video detail follows Bilibili's mobile information order: a full-width
16:9 player is first in portrait, followed by title, metadata, author, actions,
and native tabs for comments, recommendations, parts, and uploader videos.
Website-only download/open-App controls are intentionally absent. Landscape
hides the detail content and gives the complete surface to video. mpv owns
aspect handling within that one video
surface, so playback, danmaku, subtitles, progress, thumbnails, and touch all
use the same bounds. The OSD uses compact mobile-sized controls and a 72-unit
bottom strip.
Fullscreen reuses that same `VideoView` inside the detail activity. mpv's
effective `video-out-params/dw` and `dh` select a portrait or landscape
orientation mask. Current Lipstick stable-XDG windows ignore that legacy Qt
surface-extension mask, so landscape fullscreen keeps the configured surface
stable and rotates the logical NanoVG scene, mpv external-FBO quad, and input
coordinates together. It does not set a Wayland buffer transform, which is
incompatible with Android wayland-egl on this device. Portrait media remains
unrotated. Exiting fullscreen returns to portrait detail. The OSD has a touch
Back control; Back exits fullscreen before popping the detail page.

While mpv is actively playing in the foreground, the application first tries
to attach a Wayland idle inhibitor to its surface. Lipstick versions that do
not publish that protocol use Sailfish MCE's temporary display-blanking pause
instead; the request is renewed every 20 seconds over the same system-bus
connection. The inhibitor is removed or the MCE pause is cancelled on pause,
EOF, stop, backgrounding, activity exit, or application shutdown. The package
checks whether MCE currently permits an application pause before reporting a
successful renewal. The image uses MCE's upstream `keep-on` blanking-pause
policy so standard Sailfish application requests are honored; normal automatic
blanking remains enabled whenever no application holds a request. The package
does not change that system-wide policy itself.

Sailfish API requests keep TLS peer verification enabled and use the generated
system PEM bundle directly. Anonymous comment requests omit the synthetic
`buvid3` that causes the reply API to return a truncated terminal cursor; real
authenticated sessions retain their Cookie header. The portrait comment list
consumes the exact remaining height below the player metadata and begins at the
first returned comment before normal next-page recycling. Phone diagnostics
record each comment request cursor, response cursor, and successful append.

Native-fence descriptors remain owned by EGL. The application never scans or
closes arbitrary descriptors from `/proc/self/fd`; doing so races EGL's normal
fence release and can close a PulseAudio `eventfd` after descriptor reuse.

Launcher PNGs use the dot-free `silisili-sailfish` icon key and are generated
at 86, 108, 128, and 172 pixels from the Sailfish 5.1 media-player silhouette.
Only the stock center glyph is replaced with a transparent `SiliSili` mark in
the narrow, dotted rhythm of the upstream word mark; the official alpha
contour, gradient, and highlight are preserved. The 256-pixel application icon
keeps the upstream wiliwili gradient, contour, and controller motif while
changing only its white word mark to `SiliSili`. The home and About screens use
the same reproducible brand lettering. Old dotted icon files and SVG launcher
icons are not packaged.
