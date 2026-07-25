%global debug_package %{nil}
%define __os_install_post %{nil}

Name:           silisili-sailfish
Version:        1.0.0
Release:        1
Summary:        silisili Bilibili client for Sailfish OS
License:        GPL-3.0-or-later and LGPL-2.1-or-later and BSD-3-Clause and (GPL-3.0-or-later WITH GCC-exception-3.1)
Group:          Applications/Multimedia
BuildArch:      aarch64
AutoReqProv:    no
Requires:       ca-certificates
Requires:       dbus-libs
Requires:       jolla-keyboard
Requires:       libcurl
Requires:       libstdc++
Requires:       openssl-libs
Requires:       pulseaudio
Requires:       wayland
Requires:       zlib
Requires:       libwebp
Requires:       libhybris-libEGL
Requires:       maliit-framework-wayland
Provides:       wiliwili-sailfish = 1.6.0-1.bonito31
Obsoletes:      wiliwili-sailfish <= 1.6.0-1.bonito31

%description
silisili is a Sailfish OS port and modification derived from wiliwili 1.6.0,
developed with Vibe Coding and distributed under GPL-3.0-or-later. It is
packaged as a native AArch64 ELF for Sailfish OS.
The package carries a private minimal mpv, FFmpeg, libplacebo, libass, and GNU
C++ runtime while using the system network, TLS, PulseAudio, and graphics stack.

%prep

%install
rm -rf %{buildroot}
install -d -m0755 %{buildroot}/usr/bin
install -d -m0755 %{buildroot}/usr/lib64/silisili
install -d -m0755 %{buildroot}/usr/share/applications
install -d -m0755 %{buildroot}/usr/share/silisili
install -d -m0755 %{buildroot}/usr/share/licenses/%{name}
install -m0755 %{stagingdir}/launcher %{buildroot}/usr/bin/silisili
install -m0755 %{stagingdir}/silisili %{buildroot}/usr/lib64/silisili/silisili.real
cp -a %{stagingdir}/lib/. %{buildroot}/usr/lib64/silisili/
cp -a %{stagingdir}/resources %{buildroot}/usr/share/silisili/
cp -a %{stagingdir}/icons %{buildroot}/usr/share/
install -m0644 %{stagingdir}/silisili.desktop %{buildroot}/usr/share/applications/cn.silisili.app.desktop
cp -a %{stagingdir}/licenses/. %{buildroot}/usr/share/licenses/%{name}/
find %{buildroot}/usr/lib64/silisili %{buildroot}/usr/share/silisili \
    %{buildroot}/usr/share/licenses/%{name} -type d -exec chmod 0755 {} +
find %{buildroot}/usr/share/silisili %{buildroot}/usr/share/licenses/%{name} \
    -type f -exec chmod a+r {} +

%files
%defattr(-,root,root,-)
%license /usr/share/licenses/%{name}/*
/usr/bin/silisili
%dir %attr(0755,root,root) /usr/lib64/silisili
/usr/lib64/silisili/*
/usr/share/applications/cn.silisili.app.desktop
/usr/share/icons/hicolor/*/apps/silisili-sailfish.png
/usr/share/silisili

%changelog
* Sun Jul 26 2026 silisili contributors <noreply@localhost> - 1.0.0-1
- Publish silisili v1.0 as a renamed Sailfish OS port derived from wiliwili
  1.6.0, with retained upstream copyright and third-party licenses.
- Rename the executable, private runtime, resources, desktop identity,
  configuration directory, source namespace, and generated branding.
- Migrate an existing private wiliwili configuration on first launch and
  retain the validated touch, input, comments, fullscreen, and keep-awake work.
- Mark the project as developed with Vibe Coding.

* Sat Jul 25 2026 Bonito Port Team <noreply@localhost> - 1.6.0-1.bonito31
- Finalize the shared Sailfish text and numeric input path after phone testing
  search, comment, and settings fields with the native Maliit keyboard.
- Count Unicode preedit characters correctly, reset the counter when preedit
  is cleared, and keep fixed touch Back and OK controls on every input page.

* Sat Jul 25 2026 Bonito Port Team <noreply@localhost> - 1.6.0-1.bonito30
- Connect every shared text and numeric input page directly to the Sailfish
  Maliit peer service when Lipstick exposes no standard Wayland text-input.
- Handle committed and preedit text, deletion, numeric keyboard selection, and
  the keyboard Done key while retaining fixed touch Back and OK controls.

* Sat Jul 25 2026 Bonito Port Team <noreply@localhost> - 1.6.0-1.bonito29
- Open the Sailfish system input method after every shared text or numeric
  input page is visible, with a delayed activation retry for compositor focus.
- Add fixed touch Back and OK controls to the input-page toolbar while keeping
  keyboard and system Back actions on the same single-dismiss path.

* Sat Jul 25 2026 Bonito Port Team <noreply@localhost> - 1.6.0-1.bonito28
- Detect when the Sailfish display policy rejects application blanking-pause
  requests instead of logging a false-positive renewal.
- Pair playback keepalive with the standard MCE keep-on policy, which leaves
  normal automatic blanking enabled whenever no application requests it.

* Sat Jul 25 2026 Bonito Port Team <noreply@localhost> - 1.6.0-1.bonito27
- Fall back from Wayland idle-inhibit to Sailfish MCE blanking-pause requests
  on Lipstick compositors that do not publish the Wayland protocol.
- Renew the temporary MCE request while foreground playback continues and
  cancel it through the same system-bus client when playback stops.

* Sat Jul 25 2026 Bonito Port Team <noreply@localhost> - 1.6.0-1.bonito26
- Keep the Sailfish display awake only while video is actively playing in the
  foreground, using the compositor's Wayland idle-inhibit protocol.
- Release the display inhibitor immediately on pause, EOF, stop, backgrounding,
  activity exit, and application shutdown.

* Sat Jul 25 2026 Bonito Port Team <noreply@localhost> - 1.6.0-1.bonito25
- Restyle video-detail tabs as a compact Sailfish phone segment row with
  inline secondary counts and a centered active indicator.

* Sat Jul 25 2026 Bonito Port Team <noreply@localhost> - 1.6.0-1.bonito24
- Constrain every phone card grid to two portrait columns and at most four
  landscape columns when a page has no explicit responsive declaration.
- Replace the clipped translucent desktop search dialog with an opaque,
  600-unit phone input sheet and give the Dynamic feed the full screen width.

* Sat Jul 25 2026 Bonito Port Team <noreply@localhost> - 1.6.0-1.bonito23
- Rotate the logical NanoVG scene, mpv external-FBO quad, and input coordinates
  together when a landscape video enters fullscreen on stable XDG Shell.
- Keep portrait media and the normal detail page in portrait without using a
  Wayland buffer transform that is incompatible with Android wayland-egl.

* Sat Jul 25 2026 Bonito Port Team <noreply@localhost> - 1.6.0-1.bonito22
- Request one concrete Sailfish orientation when entering or leaving video
  fullscreen, matching the Qt surface-extension orientation enum.
- Clear the detail player's Yoga aspect constraint in fullscreen and record
  the computed frame and hidden detail surfaces for real-device validation.

* Sat Jul 25 2026 Bonito Port Team <noreply@localhost> - 1.6.0-1.bonito21
- Observe mpv's complete video-out-params node so dimensions arrive atomically
  without synchronously re-entering mpv from its wake callback.
- Drop the embedded 16:9 layout constraint while fullscreen, leaving mpv to
  preserve the media aspect ratio inside the complete Sailfish surface.

* Sat Jul 25 2026 Bonito Port Team <noreply@localhost> - 1.6.0-1.bonito20
- Intermediate test build superseded after synchronous property access from
  mpv's wake callback was found to stall file loading.

* Sat Jul 25 2026 Bonito Port Team <noreply@localhost> - 1.6.0-1.bonito19
- Backport mpv's external-FBO swapchain guard so libmpv does not create an
  undrainable per-frame OpenGL fence queue on Sailfish.

* Sat Jul 25 2026 Bonito Port Team <noreply@localhost> - 1.6.0-1.bonito18
- Disable libmpv's optional per-frame OpenGL sync objects on Sailfish FBO
  rendering to prevent Qualcomm KGSL sync-file descriptor exhaustion.

* Sat Jul 25 2026 Bonito Port Team <noreply@localhost> - 1.6.0-1.bonito17
- Preserve EGL ownership of native-fence descriptors to prevent a video-switch
  race from closing a reused PulseAudio eventfd and aborting the player.
- Keep the persistent bottom navigation visible on Activity and Me by allowing
  their content roots to use the height assigned by the main tab frame.

* Sat Jul 25 2026 Bonito Port Team <noreply@localhost> - 1.6.0-1.bonito16
- Add persistent mobile navigation and a global header without web App
  promotion controls, following the Bilibili mobile information hierarchy.
- Adapt home, activity, profile, search, and video detail surfaces for Sailfish
  touch dimensions and keep native page-stack Back behavior.
- Omit the synthetic anonymous buvid3 from reply requests so the full comment
  cursor remains available while preserving authenticated comment state.

* Sat Jul 25 2026 Bonito Port Team <noreply@localhost> - 1.6.0-1.bonito15
- Reap only signaled native-fence descriptors left by the legacy Qualcomm
  libhybris Wayland EGL path during continuous video rendering.
- Add phone comment cursor, response, and append diagnostics for pagination
  verification without changing the Bilibili API contract.

* Fri Jul 24 2026 Bonito Port Team <noreply@localhost> - 1.6.0-1.bonito14
- Add top-boundary pull-to-refresh to phone lists while preserving ordinary
  upward scrolling and the existing refresh data callbacks.

* Fri Jul 24 2026 Bonito Port Team <noreply@localhost> - 1.6.0-1.bonito13
- Make the complete top-level search area receive touch events while retaining
  the Sailfish system input method and disabling the television alphabet grid.

* Fri Jul 24 2026 Bonito Port Team <noreply@localhost> - 1.6.0-1.bonito12
- Let Lipstick own orientation and surface sizing instead of applying an
  android_wlegl-incompatible Wayland buffer transform.
- Open the system search input method from an explicit enlarged touch target
  and flush runtime diagnostics promptly for automated phone verification.

* Fri Jul 24 2026 Bonito Port Team <noreply@localhost> - 1.6.0-1.bonito11
- Use Sailfish's system input method for search and remove the controller
  alphabet-grid entry, Y hints, and overlapping header search bars.
- Apply buffer transform and the next landscape EGL frame atomically instead
  of committing the previous portrait buffer at the new orientation.

* Fri Jul 24 2026 Bonito Port Team <noreply@localhost> - 1.6.0-1.bonito10
- Load Sailfish's generated system trust bundle directly and start comments at
  the first item in a fully constrained remaining-height list.
- Rotate landscape video buffers and framebuffer geometry together, including
  Wayland pointer and touch coordinate mapping.

* Fri Jul 24 2026 Bonito Port Team <noreply@localhost> - 1.6.0-1.bonito9
- Request a compositor fullscreen Wayland surface and ignore saved desktop
  geometry on Sailfish phones.
- Keep one player view for fullscreen, select portrait or landscape from mpv's
  effective display dimensions, and add touch and system Back navigation.

* Fri Jul 24 2026 Bonito Port Team <noreply@localhost> - 1.6.0-1.bonito8
- Prevent the compact touch OSD from registering gamepad navigation routes on
  hidden non-focusable controls when a video detail page is opened.

* Fri Jul 24 2026 Bonito Port Team <noreply@localhost> - 1.6.0-1.bonito7
- Match the official Bilibili phone detail structure with a full-width 16:9
  player above compact metadata, actions, and comments in portrait.
- Use a video-only landscape layout and a compact mobile OSD, and remove the
  extra media viewport that separately cropped playback overlays.
- Generate launcher sizes from the Sailfish 5.1 media-player silhouette with
  the upstream wiliwili word mark.

* Fri Jul 24 2026 Bonito Port Team <noreply@localhost> - 1.6.0-1.bonito6
- Use a fixed 640x360 phone baseline with 2-column portrait and 4-column
  landscape video grids, larger navigation, text, OSD, and touch targets.
- Add native multi-touch player gestures, a media-ratio playback viewport,
  and release-to-commit seeking with cancellation.
- Disable physical controller initialization and polling, remove controller
  settings/resources, and rename the Lipstick icon key to wiliwili-sailfish.

* Fri Jul 24 2026 Bonito Port Team <noreply@localhost> - 1.6.0-1.bonito5
- Rebuild the upstream application with Sailfish phone scaling, responsive
  portrait and landscape navigation, and orientation-aware video grids.
- Add the Sailfish 86, 108, and 172 pixel launcher icons from one consistent
  transparent source contour.

* Fri Jul 24 2026 Bonito Port Team <noreply@localhost> - 1.6.0-1.bonito4
- Replace the desktop Exec target with a small PIE ELF launcher that replaces
  the compositor hwcomposer environment with Wayland before executing the
  real upstream binary from the private runtime directory.

* Fri Jul 24 2026 Bonito Port Team <noreply@localhost> - 1.6.0-1.bonito3
- Make the private runtime traversable by desktop-session applications.
- Bundle the matching GNU C++ ABI runtime required by the upstream ELF.

* Fri Jul 24 2026 Bonito Port Team <noreply@localhost> - 1.6.0-1.bonito2
- Own only application icon files, not the shared system icon directories.

* Fri Jul 24 2026 Bonito Port Team <noreply@localhost> - 1.6.0-1.bonito1
- Repackage the upstream GLES2 Flatpak ELF for Sailfish OS.
- Replace the Flatpak resource prefix and add a private minimal media runtime.
