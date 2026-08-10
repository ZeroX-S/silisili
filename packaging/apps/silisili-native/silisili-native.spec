Name:           silisili-native-devel
Version:        1.1.0
Release:        1.35
Summary:        Native Sailfish OS development version of silisili
License:        GPL-3.0-or-later and LGPL-2.1-or-later and BSD-3-Clause and Apache-2.0 and ISC and WTFPL
Group:          Applications/Multimedia
BuildArch:      aarch64
AutoReqProv:    no
Requires:       ca-certificates
Requires:       droidmedia
Requires:       libhybris-libEGL
Requires:       libhybris-libGLESv2
Requires:       libstdc++
Requires:       pulseaudio
Requires:       sailfishsilica-qt5
Requires:       qt5-qtdeclarative
Requires:       qt5-qtdeclarative-import-sensors
Requires:       qt5-qtnetwork
Requires:       zlib

%description
Parallel-installable native Sailfish Silica migration build of silisili.
This development package does not replace silisili-sailfish 1.0.0-7.

%prep

%install
rm -rf %{buildroot}
install -d -m0755 %{buildroot}/usr/bin
install -d -m0755 %{buildroot}/usr/lib64/silisili-native
install -d -m0755 %{buildroot}/usr/libexec/silisili-native
install -d -m0755 %{buildroot}/usr/libexec/droid-hybris/system/lib
install -d -m0755 %{buildroot}/usr/lib/systemd/system
install -d -m0755 %{buildroot}/usr/share/applications
install -d -m0755 %{buildroot}/usr/share/icons/hicolor/86x86/apps
install -d -m0755 %{buildroot}/usr/share/mapplauncherd/privileges.d
install -d -m0755 %{buildroot}/usr/share/licenses/%{name}
install -m0755 %{stagingdir}/silisili-native %{buildroot}/usr/bin/silisili-native
install -m0755 %{stagingdir}/libexec/libminimedia-audiosource-shim.so %{buildroot}/usr/libexec/droid-hybris/system/lib/libsilisili-minimedia-audiosource-shim.so
install -m0755 %{stagingdir}/libexec/silisili-native-minimedia-wrapper %{buildroot}/usr/libexec/silisili-native/silisili-native-minimedia-wrapper
install -m0644 %{stagingdir}/systemd/silisili-native-minimedia.service %{buildroot}/usr/lib/systemd/system/silisili-native-minimedia.service
cp -a %{stagingdir}/lib/. %{buildroot}/usr/lib64/silisili-native/
cp -a %{stagingdir}/licenses/. %{buildroot}/usr/share/licenses/%{name}/
install -m0644 %{stagingdir}/silisili-native.desktop %{buildroot}/usr/share/applications/cn.silisili.native.desktop
install -m0644 %{stagingdir}/silisili-native-devel.png %{buildroot}/usr/share/icons/hicolor/86x86/apps/silisili-native-devel.png
install -m0644 %{stagingdir}/silisili-native.privileges %{buildroot}/usr/share/mapplauncherd/privileges.d/silisili-native

%post
# Sailjail only exposes the development app's own config directory at runtime.
# Seed a read-only snapshot of the stable/legacy config into that directory
# during package installation so the app can import cookies without expanding
# its runtime sandbox.  Do not overwrite an explicit native session.
native_dir=/home/defaultuser/.config/cn.silisili.native
native_snapshot=$native_dir/stable_config_snapshot.json
native_session=$native_dir/account_session.json
stable_config=/home/defaultuser/.config/silisili/silisili_config.json
legacy_snapshot=/home/defaultuser/.config/silisili-native/stable_config_snapshot.json

if [ ! -f "$native_session" ] && [ ! -f "$native_snapshot" ]; then
    mkdir -p "$native_dir" || :
    if [ -f "$stable_config" ]; then
        cp -f "$stable_config" "$native_snapshot" || :
    elif [ -f "$legacy_snapshot" ]; then
        cp -f "$legacy_snapshot" "$native_snapshot" || :
    fi
fi
if [ -d "$native_dir" ]; then
    chmod 700 "$native_dir" || :
    chown defaultuser:defaultuser "$native_dir" 2>/dev/null || chown defaultuser "$native_dir" 2>/dev/null || :
fi
if [ -f "$native_snapshot" ]; then
    chmod 600 "$native_snapshot" || :
    chown defaultuser:defaultuser "$native_snapshot" 2>/dev/null || chown defaultuser "$native_snapshot" 2>/dev/null || :
fi
systemctl daemon-reload >/dev/null 2>&1 || :
systemctl enable silisili-native-minimedia.service >/dev/null 2>&1 || :
systemctl restart silisili-native-minimedia.service >/dev/null 2>&1 || :
exit 0

%preun
if [ "$1" -eq 0 ]; then
    systemctl disable --now silisili-native-minimedia.service >/dev/null 2>&1 || :
fi
exit 0

%postun
systemctl daemon-reload >/dev/null 2>&1 || :
exit 0

%files
%defattr(-,root,root,-)
/usr/bin/silisili-native
/usr/libexec/droid-hybris/system/lib/libsilisili-minimedia-audiosource-shim.so
/usr/libexec/silisili-native/silisili-native-minimedia-wrapper
/usr/lib/systemd/system/silisili-native-minimedia.service
/usr/lib64/silisili-native/*
/usr/share/applications/cn.silisili.native.desktop
/usr/share/icons/hicolor/86x86/apps/silisili-native-devel.png
/usr/share/mapplauncherd/privileges.d/silisili-native
%license /usr/share/licenses/%{name}/*

%changelog
* Mon Aug 10 2026 silisili contributors <noreply@localhost> - 1.1.0-1.35
- Make PlaybackSession the common presentation owner for VOD, PGC and live,
  while retaining separate resolver, quality, seek, speed and history rules.
- Present an active live stream through the configured moving-video Cover or
  movable system PiP without pausing, reloading or creating another decoder.

* Mon Aug 10 2026 silisili contributors <noreply@localhost> - 1.1.0-1.34
- Seed Qt's exported process-wide global share context before either QQuick
  scene graph is created, so cold-start foreground, Cover and system PiP all
  sample the same hardware-decoded texture without reloading playback.

* Mon Aug 10 2026 silisili contributors <noreply@localhost> - 1.1.0-1.33
- When Sailfish has not yet published Qt's global share context, explicitly
  share the live renderer with the already initialized QQuickWindow context;
  retain the 1.25 global-share path whenever it is available.

* Mon Aug 10 2026 silisili contributors <noreply@localhost> - 1.1.0-1.32
- Delay only live stream resolution until the process-lifetime renderer has
  joined Qt Quick's initialized OpenGL share group, eliminating the direct-live
  startup race without changing the 1.25 VOD presentation checks.

* Mon Aug 10 2026 silisili contributors <noreply@localhost> - 1.1.0-1.31
- Keep the proven 1.25 VOD presentation path unchanged while allowing only
  live surfaces to validate an EGL-shared texture directly when Qt does not
  report the late-created scene-graph context relationship.

* Mon Aug 10 2026 silisili contributors <noreply@localhost> - 1.1.0-1.30
- Restore the 1.25 point-on-demand renderer, preload, texture-sharing and
  presentation gates without the later experimental foreground changes.
- Keep the live-only droidmedia timestamp normalization and live FLV audio
  discovery fix, so the live repair cannot alter ordinary VOD behavior.

* Mon Aug 10 2026 silisili contributors <noreply@localhost> - 1.1.0-1.29
- Publish verified droidmedia frames independently of the libmpv audio restart
  event while retaining the non-zero history-position gate.
- Give live FLV audio discovery a container-specific probe budget so direct
  hardware video does not leave libmpv with no selected audio stream.

* Mon Aug 10 2026 silisili contributors <noreply@localhost> - 1.1.0-1.28
- Accept the main player's persistent texture when the native GL namespace
  confirms visibility after a Lipstick context transition, preventing an
  audio-only black screen caused by stale Qt share-group bookkeeping.
- Restore the explicit portable-software compatibility override while keeping
  automatic hardware-start and first-frame fallback as the production path.

* Mon Aug 10 2026 silisili contributors <noreply@localhost> - 1.1.0-1.27
- Accept a persistent video texture in the Cover or system-PiP scene graph
  when the native GL namespace confirms visibility even if Qt's share-group
  bookkeeping reports the Lipstick-owned window as unshared.
- Retain the live hardware timestamp normalization and non-seekable fallback
  guarantees introduced in 1.26.

* Mon Aug 10 2026 silisili contributors <noreply@localhost> - 1.1.0-1.26
- Normalize live-container hardware timestamps to libmpv's playback clock so
  long-running FLV sources cannot be throttled as hours ahead of audio.
- Preserve non-seekable live semantics during hardware restart and software
  fallback, preventing an impossible initial-position gate from hiding video.

* Mon Aug 10 2026 silisili contributors <noreply@localhost> - 1.1.0-1.25
- Apply a non-zero initial/history position as a paused per-file start option,
  and release audio only after the new file confirms the target clock and the
  first real video texture. This removes audible time-zero playback, initial
  audio-only output and the later visible seek.
- Treat a successfully decoded application-owned hardware texture as codec
  startup progress even while presentation waits for audio-position alignment,
  preventing the first-frame watchdog from forcing a redundant software load.

* Mon Aug 10 2026 silisili contributors <noreply@localhost> - 1.1.0-1.24
- Keep droidmedia frame callbacks nonblocking by dropping an excess incoming
  output under GUI pressure, preventing Binder transaction buildup from
  freezing video while the separate audio clock continues. Retain consecutive
  queued frames and move queue-sized sliding backpressure to the private demux
  thread so OMX cannot burst past the display queue or lose source cadence.
- Detect a stopped hardware frame serial while audio advances and restart only
  the same-quality video decoder at the retained clock position; keep the
  audio load, shared texture, controls and media-load serial intact.

* Mon Aug 10 2026 silisili contributors <noreply@localhost> - 1.1.0-1.23
- Bound compressed droidmedia input to 1.5 seconds ahead of the audio clock so
  asynchronous OMX adaptations cannot queue an entire long video, exhaust CMA
  and leave the player stuck in loading.
- Reconcile the internal hardware-to-software load serial, retain pause/seek
  intent during a quality transition, and keep transport controls interactive
  beneath a passive loading indicator.
- Keep the 1200 ms first-frame safety deadline for verified UHD opt-in while
  allowing ordinary 1080P hardware startup 3500 ms before software fallback.

* Mon Aug 10 2026 silisili contributors <noreply@localhost> - 1.1.0-1.22
- Treat droidmedia's advertised UHD support as provisional and default
  unverified devices to the real 1080P60 hardware representation while keeping
  every server-advertised quality row visible.
- Retain an explicit verified-device UHD opt-in with a 1200 ms first-frame
  watchdog; a failed opt-in persists the stable operational ceiling and
  retries at 1080P60 without unsafe UHD software decode.

* Mon Aug 10 2026 silisili contributors <noreply@localhost> - 1.1.0-1.21
- Probe AVC/HEVC OMX limits per device and cadence (30/60fps), then resolve
  requested 4K/8K rows to
  the highest real representation the installed hardware decoder declares,
  avoiding codecs that can be created but never output a first UHD frame.
- Gate home-feed pagination after a network failure before publishing
  loading=false, preventing the loading/contentY handlers from recursively
  starting offline requests while the user continues scrolling.
- Exercise the exact pagination failure with 64 continued-scroll loadMore
  attempts and require same-process refresh recovery.

* Mon Aug 10 2026 silisili contributors <noreply@localhost> - 1.1.0-1.20
- Keep droidmedia's reference bounded callback backpressure, retain only one
  waiting gralloc frame above 1080P, and stop OMX before worker joins so a
  blocked input queue cannot freeze teardown.
- Reject dimensions beyond the bounded 4096x2304 direct-decoder allocation
  budget.
- Keep 8K and unsupported AV1 rows visible while resolving them to the highest
  safe real AVC/HEVC representation instead of attempting phone-side 8K
  software decode.

* Sun Aug 09 2026 silisili contributors <noreply@localhost> - 1.1.0-1.19
- Abort obsolete replies immediately when Qt reports an offline or changed
  network bearer instead of leaving pages blocked until their hard timeout.
- Let refresh and category changes cancel in-flight home, live, dynamic, and
  inbox requests, while generation guards reject stale responses.
- Apply the same bounded connectivity lifecycle to danmaku requests and add a
  deterministic same-process network recovery regression.

* Sun Aug 09 2026 silisili contributors <noreply@localhost> - 1.1.0-1.18
- Suppress notification-surface remapping while asynchronous lca-tool task
  activation returns the existing player to the foreground, preventing a PiP
  flash between a restore tap and Lipstick's foreground state update.
- Keep the PiP close control's full touch target while removing its translucent
  circular background so only the theme close glyph overlays the video.

* Sun Aug 09 2026 silisili contributors <noreply@localhost> - 1.1.0-1.17
- Replace the compositor-resized compact PiP surface with a stable full-screen
  transparent notification overlay and a bounded click-through video box.
- Present the live shared hardware-decoder texture through Qt Quick, persist
  drag positions, rotate from the device sensor, and activate through lca-tool.

* Sun Aug 09 2026 silisili contributors <noreply@localhost> - 1.1.0-1.16
- Use exact-qn DASH for every advertised profile, including 720P and below.
- Keep progressive media only as a compatibility fallback after DASH failure.

* Sun Aug 09 2026 silisili contributors <noreply@localhost> - 1.1.0-1.15
- Separate the full quality-catalog probe from exact-qn media selection.
- Never substitute a representation above the quality row selected by users.
- Add semantic geometry evidence for physical quality-picker testing.

* Sun Aug 09 2026 silisili contributors <noreply@localhost> - 1.1.0-1.14
- Keep every server-advertised quality available across in-place switches.
- Make the in-player quality sheet physically flickable with four visible rows.
- Disconnect the Cover texture source while system PiP owns presentation.

* Sun Aug 09 2026 silisili contributors <noreply@localhost> - 1.1.0-1.13
- Launch the privileged PIE through the generic booster so main() sets
  AA_ShareOpenGLContexts before constructing QGuiApplication; this preserves
  one GL share group across the video renderer, Cover and system PiP.

* Sun Aug 09 2026 silisili contributors <noreply@localhost> - 1.1.0-1.12
- Build the privileged application as PIE/ET_DYN so Sailfish mapplauncherd's
  Silica booster can load it after applying the background-PiP privilege set.

* Sun Aug 09 2026 silisili contributors <noreply@localhost> - 1.1.0-1.11
- Add a configurable background presentation mode: the normal Sailfish Cover
  can keep showing the live shared video, or one privileged Lipstick
  notification surface can present the same texture as a movable system PiP.
- Apply explicit Wayland input and empty opaque regions, hide system PiP on
  foreground, lock, display-off, stop and EOF, and keep one decoder without
  using the compositor's whole-output recorder protocol.
- Preserve every API-advertised VOD quality across quality switches, probe the
  full entitled DASH ladder, and allow every returned profile through the
  playback request instead of permanently capping the menu at 1080P.
- Expand the native quality picker into a bounded, flickable list that retains
  and highlights the current selection after 720P/1080P changes.

* Sun Aug 09 2026 silisili contributors <noreply@localhost> - 1.1.0-1.10
- Pace the active hardware-decoded shared framebuffer at the 60 Hz display
  cadence. A 30 FPS source is presented twice per source frame without another
  decode or pixel copy, keeping Qt/Lipstick swaps above the 45 FPS floor while
  preserving the real source cadence and libmpv audio clock.
- Pause the presentation driver during seek, buffering, pause, EOF and inactive
  main-window states; Cover continues from real decoded frame notifications.

* Sun Aug 09 2026 silisili contributors <noreply@localhost> - 1.1.0-1.09
- Recycle droidmedia gralloc frames behind EGL render fences instead of a
  per-frame glFinish, preserving buffer lifetime without serializing the GUI
  and GPU on every decoded frame.
- Bound the deferred buffer queue and retain a safe emergency drain for broken
  EGL fence implementations, while keeping the direct path CPU-copy-free.

* Sun Aug 09 2026 silisili contributors <noreply@localhost> - 1.1.0-1.08
- Add a true hardware video path modelled on RooTheater: FFmpeg demuxes the
  video track, droidmedia selects HW_ONLY Android OMX, and gralloc frames enter
  the existing shared Cover texture through EGLImage/external-OES without a
  CPU pixel copy; libmpv remains the separate DASH audio/master clock.
- Keep seek inside the live OMX decoder through flush plus demux reposition,
  and fall back at the current position to the complete software pipeline when
  codec capability, runtime decode, EGLImage or shader setup fails.
- Start the standard minimediaservice through a scoped systemd compatibility
  wrapper. Only affected 32-bit Android 9 images receive the missing
  AudioSource callback shim from droid-hybris' permitted library namespace;
  working adaptations run their unmodified service.

* Sun Aug 09 2026 silisili contributors <noreply@localhost> - 1.1.0-1.07
- Drive libmpv display-resample from each distinct shared texture actually
  consumed by the inactive Sailfish Cover, restoring smooth Cover playback
  while retaining one decoder, source and playback clock.
- Keep main-window swap feedback foreground-only so Cover and full-screen
  presentation cannot double-report the same display cadence.
- Reject visible-card media preparation while the application is backgrounded;
  a Cover refresh can no longer decode the refreshed Home row zero into a
  stopped detail page. Resume bounded preparation when Home is visible again.

* Sun Aug 09 2026 silisili contributors <noreply@localhost> - 1.1.0-1.06
- Promote the shared video framebuffer to the full-screen host's native pixel
  size after orientation settles, so a real 1920x1080 source is no longer
  reduced to an 800-pixel intermediate texture and enlarged by Qt Quick.
- Keep detail, compact-player and Cover rendering on the bounded shared profile
  and retain the single decoder/source/clock during resolution promotion.
- Report libmpv swaps only after the real Qt/Lipstick window flip and publish
  the inactive half of the video double buffer with a non-blocking GL flush,
  eliminating redundant offscreen work without serializing every 1080p frame.
- Replace the placeholder About copy with build-injected application, package,
  Sailfish, architecture, Qt and libmpv version information plus explicit
  playback, compatibility, package-isolation and open-source disclosures.
- Make the RPM build reject CMake/spec version drift and inject the actual RPM
  release into the application metadata shown to the user.
- Cancel stale region requests and guard their replies by generation so a fast
  category switch cannot display the previous ranking under the new heading;
  add bounded timeouts to both ranking and related-video requests.
- Keep the CMake and qmake native manifests aligned and add a source/QRC/desktop
  verification gate for repeatable release review.

* Sun Aug 09 2026 silisili contributors <noreply@localhost> - 1.1.0-1.05
- Stop sending `is_refresh=1` merely because the user selected another PGC
  category; only an explicit pull-down refresh may request a rotated batch.
- Retain one page-lifetime snapshot per PGC category, including rows, cursor
  and deduplication state, so switching back cannot adopt a rotating module;
  explicit refresh invalidates only the visible category snapshot.
- Commit PGC list rows and their pagination cursor atomically before clearing
  the loading latch, preventing a model reset at the list end from issuing an
  empty-cursor request and mixing a second result set into the selected tab.
- Reject pagination before the current category has published a cursor and
  retain generation/category guards for late responses during rapid switches.

* Sun Aug 09 2026 silisili contributors <noreply@localhost> - 1.1.0-1.04
- Add authenticated comment like/unlike actions with optimistic count updates
  and rollback when the API rejects a request.
- Add replies for root comments and nested replies across video previews, full
  comment lists, PGC comments and reply threads, with immediate model refresh.
- Use compact borderless Sailfish icon actions for like and reply instead of
  full-size form buttons in every comment row.

* Sun Aug 09 2026 silisili contributors <noreply@localhost> - 1.1.0-1.03
- Present the active decoded shared texture in the Sailfish Cover while video
  is playing, without moving the primary surface, reloading media or seeking.
- Preserve the source framebuffer aspect inside the Cover and retain the poster
  only until the first real video frame is ready.

* Sun Aug 09 2026 silisili contributors <noreply@localhost> - 1.1.0-1.02
- Carry history cid and progress through account-library routing and start both
  ordinary videos and PGC episodes directly at the recorded media position.
- Apply the recorded position to the initial media load instead of playing at
  zero and issuing a visible/audio-discontinuous follow-up seek.

* Sat Aug 08 2026 silisili contributors <noreply@localhost> - 1.1.0-1.01
- Bind Sailfish OS 5.2 Amber.Barcode through its declared BarcodeImage API,
  explicitly selecting QRCode format and assigning sourceText so the inherited
  QQuickItem data list can no longer cause a false renderer match and No data.

* Sat Aug 08 2026 silisili contributors <noreply@localhost> - 1.1.0-1.00
- Select Amber.Barcode on Sailfish OS 5.2+ with a runtime QML probe and keep
  QrShareImage as the Sailfish OS 5.1/fallback renderer.
- Replace the native and packaged app icons with the optimized supplied icon.

* Fri Aug 07 2026 silisili contributors <noreply@localhost> - 1.1.0-0.99
- Keep the QR image stable across login polling status updates; only an
  explicit user-triggered generate/regenerate action replaces the QR source.

* Fri Aug 07 2026 silisili contributors <noreply@localhost> - 1.1.0-0.98
- Recover display geometry directly from a verified decoded frame when the
  asynchronous video-out-params event is lost, releasing the retained first
  frame without reloading, seeking, pausing, or replacing the decoder.

* Fri Aug 07 2026 silisili contributors <noreply@localhost> - 1.1.0-0.97
- Report authenticated playback history at first frame, every 15 seconds, and
  at pause, background, stop, completion, and video/part transitions.

* Fri Aug 07 2026 silisili contributors <noreply@localhost> - 1.1.0-0.96
- Reconcile the first-frame loading latch from the current presented texture
- Continue multi-part videos on the same playback surface after real EOF

* Fri Aug 07 2026 silisili contributors <noreply@localhost> - 1.1.0-0.95
- Disable the unreliable system-level background PiP surface after device
  testing showed that Lipstick could report it exposed without making it
  visible. Retain the draggable in-application compact player and Cover path.

* Fri Aug 07 2026 silisili contributors <noreply@localhost> - 1.1.0-0.94
- Treat compact-player restoration as an explicit trigger for both comments
  and recommendations, bypassing viewport lazy-load gates without issuing
  duplicate requests or duplicating model rows.
- Report the inline fullscreen control geometry for repeatable no-flash device
  handoff tests without image or visual-model inspection.

* Fri Aug 07 2026 silisili contributors <noreply@localhost> - 1.1.0-0.93
- Add compositor-exposure evidence for the independent background PiP surface.
- Verify compact-to-detail recovery only after both comment and recommendation
  requests have completed, while retaining the no-duplicate-request invariant.

* Fri Aug 07 2026 silisili contributors <noreply@localhost> - 1.1.0-0.92
- Detect background state from Lipstick's topmost-process signal instead of
  relying only on Qt.applicationState, and map PiP as an independent overlay
  surface so it remains visible after the application becomes a Cover.
- Resume already-loaded comment and recommendation delegates when a compact
  player restores its detail page, without duplicate API requests or rows.

* Fri Aug 07 2026 silisili contributors <noreply@localhost> - 1.1.0-0.91
- Restore 1080P (quality 80) as the default and highest visible VOD quality;
  retain the 720P progressive path only as an API/media fallback.
- Make inline-to-full-screen video-host transfer atomic and suppress the compact
  overlay throughout the handoff, without decoder reload or seek.

* Fri Aug 07 2026 silisili contributors <noreply@localhost> - 1.1.0-0.90
- Use mpv display-resample interpolation at 60 Hz for the stable 720p software
  stream because Bilibili's tested assets expose 1080P60 but only 720P30.

* Fri Aug 07 2026 silisili contributors <noreply@localhost> - 1.1.0-0.89
- Cap the one-decoder software path at 720P60 (quality 74) after repeated
  real-device 1080P60 page-transition windows fell below the 45 FPS floor.
- Keep 60 FPS motion while reducing decoded pixels by 56 percent, and expose
  only qualities supported by the stable software-performance envelope.

* Fri Aug 07 2026 silisili contributors <noreply@localhost> - 1.1.0-0.88
- Keep SearchPage from automatically opening the system keyboard while compact
  video plays; explicit field taps still open it without passive page resize.
- Restore the stock PageStack duration after proving zero-duration transitions
  can leave the Sailfish PageStack busy state latched.

* Fri Aug 07 2026 silisili contributors <noreply@localhost> - 1.1.0-0.87
- Disable the 400 ms Sailfish PageStack transition only while compact video is
  active, then restore it, preventing navigation animation from stealing frames.

* Fri Aug 07 2026 silisili contributors <noreply@localhost> - 1.1.0-0.86
- Serialize compact-player page-transition regression pushes so each animated
  PageStack transition completes before the next synthetic interaction begins.

* Fri Aug 07 2026 silisili contributors <noreply@localhost> - 1.1.0-0.85
- Reduce the stable shared video FBO long edge from 900 to 800 px after the
  real-device transition gate measured 43.8 FPS in its first one-second window.

* Fri Aug 07 2026 silisili contributors <noreply@localhost> - 1.1.0-0.84
- Keep the persistent software-video FBO at a stable 900 px long edge so page
  construction and transitions retain enough GPU headroom for the 45 FPS floor.

* Fri Aug 07 2026 silisili contributors <noreply@localhost> - 1.1.0-0.83
- Keep a screen-quality video FBO across same-aspect inline, full-screen and
  compact host moves, avoiding two allocations and dropped transition frames.
- Rebuild the persistent FBO only when presentation aspect actually changes,
  preserving correct portrait-video geometry without size-only churn.

* Fri Aug 07 2026 silisili contributors <noreply@localhost> - 1.1.0-0.82
- Move compact overlay drawing and Wayland buffer swaps onto a dedicated GL
  thread so the GUI thread's single mpv renderer no longer serializes them.
- Synchronize overlay exposure, visibility and decoded-frame wakeups without
  copying textures or creating another media pipeline.

* Fri Aug 07 2026 silisili contributors <noreply@localhost> - 1.1.0-0.81
- Present the background shared texture through a compact QOpenGLWindow
  instead of a second Qt Quick render loop, while keeping one mpv decoder.
- Draw decoded frames directly into the Lipstick overlay and make a tap return
  to the application; no title or persistent controls obscure the video.

* Fri Aug 07 2026 silisili contributors <noreply@localhost> - 1.1.0-0.80
- Make the background Lipstick overlay a compact transient surface positioned
  relative to the application instead of a full-screen transparent buffer.
- Composite only the actual video rectangle (about one eighth of the pixels
  on the test phone); retain draggable free placement for the in-app player.

* Fri Aug 07 2026 silisili contributors <noreply@localhost> - 1.1.0-0.79
- Map the system overlay after Lipstick's app-to-Cover transition and remap a
  bounded number of times if the compositor withdraws it during that handoff.
- Let the overlay mirror submit decoded-frame updates without waiting on a
  second client-side vsync; Lipstick remains responsible for final display
  synchronization while the single mpv pipeline keeps its shared texture.

* Fri Aug 07 2026 silisili contributors <noreply@localhost> - 1.1.0-0.78
- Transfer the live texture to the stable compact layer synchronously during
  PageStack changes so a busy event loop cannot create a transition gap.
- Clear session visibility before mpv resets its EOF flag, preventing the
  completed small window from flashing one empty frame during auto-dismiss.
- Claim the destination video host before activating prepared playback so the
  compact layer cannot expose the preceding video's retained frame on entry.

* Fri Aug 07 2026 silisili contributors <noreply@localhost> - 1.1.0-0.77
- Keep the in-app compact player on ApplicationWindow's stable rotating layer
  so PageStack transitions never detach its live shared texture.
- Hand an exiting inline surface to the compact host in the next event-loop
  turn without the previous 220 ms hidden delay, reload, seek, or decoder swap.
- Mirror the same persistent mpv texture into a focusless, input-bounded
  Lipstick overlay while playback is backgrounded; hide it on foreground,
  lock, display-off, stop, or EOF without creating a second decoder.
- Auto-dismiss and clear compact/system PiP playback after natural EOF while
  retaining the normal completed state on an active full player page.

* Fri Aug 07 2026 silisili contributors <noreply@localhost> - 1.1.0-0.76
- Remove the QtMultimedia/GStreamer/droidmedia hardware-decoder path, its
  local media proxy, runtime dependencies, and decoder-switch state machine.
- Start every VOD directly in one persistent mpv software video/audio pipeline;
  direct-device baseline reaches the first texture in under two seconds.
- Keep seek and playback-rate operations inside that same decoder so position
  changes no longer pause for a hardware-to-software surface hand-off.

* Fri Aug 07 2026 silisili contributors <noreply@localhost> - 1.1.0-0.75
- Remove the always-visible compact-player title bar and keep controls hidden
  during normal playback so the video has no persistent overlay obstruction.
- Show one reduced-height control strip only after touch, auto-hide it after
  2.2 seconds, and retain restore, pause/play, close, and double-tap restore.

* Thu Aug 06 2026 silisili contributors <noreply@localhost> - 1.1.0-0.74
- Parent the in-app compact player to the active Sailfish Page so it inherits
  the page's landscape transform instead of the portrait framebuffer root.
- Compute compact-player sizing, placement, and drag bounds in the active
  Page coordinate space and report the bound page geometry for device tests.

* Thu Aug 06 2026 silisili contributors <noreply@localhost> - 1.1.0-0.73
- Add bounded network timeouts and WBI signing for account, UP-space,
  dynamics, playback, comments, live, and PGC requests.
- Make dynamic cards open a full content detail page before comments, fix
  personal-library initialization/refresh races, and request optimized avatar
  thumbnails with bounded CDN failover.
- Start playback from an early parallel CID lookup, accept valid 720P DASH
  video/audio pairs without a redundant API request, and preserve the hardware
  audio gate until the first real video frame.
- Drain all proxied video bytes before closing the local hardware-decoder
  connection and remove hidden periodic hardware seeks that could flush a
  healthy droidmedia surface to black during long playback.
- Enforce a landscape floating-player window from both the application
  orientation and source aspect, including semantic aspect logging.

* Thu Aug 06 2026 silisili contributors <noreply@localhost> - 1.1.0-0.72
- Add responsive landscape layouts for media details, navigation/account
  grids, feed cards, comments, QR login and player controls.
- Add privacy-safe semantic orientation/geometry markers and a development
  launch override for repeatable real-device landscape regression testing.
- Let the same opt-in development launch override select Navigation, media
  detail or compact-player regression routes without coordinate assumptions.
- Replace the fixed bottom compact-player strip with a bounded 16:9 in-app
  floating player that can be dragged, remembers relative placement across
  orientation changes, and distinguishes drag from activation.

* Thu Aug 06 2026 silisili contributors <noreply@localhost> - 1.1.0-0.71
- Isolate shared dynamics requests by section and generation, clear the old
  model immediately on section changes, and ignore late replies so video rows
  cannot leak into the image/repost page during rapid navigation.
- Make non-video and UP-space dynamic cards open their typed comment thread by
  default when available, while retaining video access through the context
  menu and explicit comment buttons.

* Thu Aug 06 2026 silisili contributors <noreply@localhost> - 1.1.0-0.70
- Bind scale-independent semantic geometry markers to the actual Video
  dynamics and Image/repost dynamics tiles so real-device touch regression
  cannot accidentally target Search or Region ranking.

* Thu Aug 06 2026 silisili contributors <noreply@localhost> - 1.1.0-0.69
- Keep SearchField focus entirely inside its instantiated list-header scope;
  avoid the cross-component headerItem callback that SIGBUSes on the phone's
  older Qt Quick runtime.

* Thu Aug 06 2026 silisili contributors <noreply@localhost> - 1.1.0-0.68
- Split followed dynamics into dedicated video and non-video sections, using
  the server video feed where available and filtering the all-content cursor
  for image, article, repost, and other non-video cards.
- Retry dynamic and author-space pagination after slow-scroll/loading races;
  paginate both UP videos and 12-item space-dynamic pages by their real page
  and offset cursors.
- Render forwarded/original space content and expose typed dynamic comments,
  including reply threads and comment posting for resource types 1, 11, and 17.
- Resolve the SearchPage header-component focus scope so keyboard input reaches
  the search field reliably after opening the page.

* Thu Aug 06 2026 silisili contributors <noreply@localhost> - 1.1.0-0.67
- Reuse the native account session for video search so Bilibili does not treat
  partial or typo-tolerant queries as anonymous anti-abuse traffic.
- Report HTTP 412 distinctly and add privacy-safe authenticated/result markers
  for repeatable real-device search regression tests.

* Thu Aug 06 2026 silisili contributors <noreply@localhost> - 1.1.0-0.66
- Report logical geometry for the Account and History touch targets so device
  automation can derive coordinates across compositor scale factors without
  screenshots or hard-coded legacy geometry.

* Thu Aug 06 2026 silisili contributors <noreply@localhost> - 1.1.0-0.65
- Add semantic page-ready markers for More content and Account so real-device
  touch regressions can synchronize on page state without visual inspection.

* Thu Aug 06 2026 silisili contributors <noreply@localhost> - 1.1.0-0.64
- Ignore the superseded source's END_FILE(STOP) during a replace load so it
  cannot clear the new source's requested-position presentation gate.

* Thu Aug 06 2026 silisili contributors <noreply@localhost> - 1.1.0-0.63
- Hold new-source texture presentation until libmpv confirms the requested
  initial seek position, preventing a transient time-zero or stale frame from
  satisfying the synchronized transport first-frame gate.

* Thu Aug 06 2026 silisili contributors <noreply@localhost> - 1.1.0-0.62
- Keep normal playback on the Sailfish hardware decoder, but treat explicit
  seek and non-default rate as a synchronized transport boundary on device
  adaptations whose advertised controls do not advance the picture clock.
- Freeze the audio clock and retain the last hardware frame while the portable
  decoder prepares the requested position; swap only after a real software
  texture is rendered, then release audio and picture together.
- Preserve runtime hardware detection and automatic software fallback for
  unsupported phones without changing the stable application package.

* Thu Aug 06 2026 silisili contributors <noreply@localhost> - 1.1.0-0.61
- Replace the fixed small live recommendation block with the signed, real
  feedV2 pagination source, deduplicate rooms, and continuously request the
  next page near the list bottom while retaining pull-down refresh.

* Thu Aug 06 2026 silisili contributors <noreply@localhost> - 1.1.0-0.60
- Preserve a deterministic byte length through the local CDN proxy so the
  Sailfish QtMultimedia/GStreamer hardware path can expose time seeking.
- Apply seek as a pause/flush/seek/resume transaction, verify the hardware
  picture clock, and fail over to synchronized software video if a device
  adaptation rejects seek or playback-rate control.
- Verify non-default playback rate against the audio master so a stale picture
  can never continue while only audio responds to acceleration.

* Thu Aug 06 2026 silisili contributors <noreply@localhost> - 1.1.0-0.59
- Add native account pages for playback history, favorite folders, subscribed
  collections, followed anime/cinema, and the watch-later queue, including
  authenticated pagination and navigable collection contents.

* Thu Aug 06 2026 silisili contributors <noreply@localhost> - 1.1.0-0.58
- Measure completed Qt Quick window swaps for the continuous 60-second 45 fps
  display floor instead of treating decoder probe delivery as visible output.

* Thu Aug 06 2026 silisili contributors <noreply@localhost> - 1.1.0-0.57
- Bind Qt 5.6 VideoOutput through a mediaObject adapter so the Nemo hardware
  texture backend is loaded instead of decoding into an unpresented probe.

* Thu Aug 06 2026 silisili contributors <noreply@localhost> - 1.1.0-0.56
- Feed the Sailfish QtMultimedia hardware path through an application-local,
  range-capable HTTP proxy so Qt's working TLS stack handles Bilibili CDN
  certificates rejected by GStreamer's older GLib TLS backend.
- Keep device adaptation detection optional and retain forced, missing-plugin,
  media-error, and first-frame-timeout fallback to portable mpv software decode.

* Thu Aug 06 2026 silisili contributors <noreply@localhost> - 1.1.0-0.55
- Route hardware video through the Sailfish QtMultimedia/GStreamer device
  adaptation and Nemo texture output, retaining mpv as the audio clock and
  automatic software-decoder fallback on unsupported phones or media.
- Gate audio on the first probed hardware frame, preserve source aspect ratio,
  keep one decoder across Cover transitions, and measure delivered frames for
  the continuous 60-second 45 FPS qualification.

* Thu Aug 06 2026 silisili contributors <noreply@localhost> - 1.1.0-0.54
- Start the empty V4L2 OUTPUT queue and CAPTURE session before submitting the
  first compressed packet, matching the downstream Qualcomm msm_vidc contract.
- Treat a V4L2 queue-start failure as terminal instead of retrying against a
  dead decoder session, and do not expose an empty zero-aspect FBO as a frame.
- Bound stalled avatar image requests so author space and dynamic feeds can
  advance to the alternate Bilibili CDN hosts instead of loading forever.

* Thu Aug 06 2026 silisili contributors <noreply@localhost> - 1.1.0-0.53
- Fall back to application-owned V4L2 USERPTR buffers for the compressed Venus
  input queue while retaining MMAP NV12 buffers for decoded capture frames.

* Thu Aug 06 2026 silisili contributors <noreply@localhost> - 1.1.0-0.52
- Supply the coded video dimensions while probing the Venus raw capture queue;
  the downstream driver rejects the zero-size probe accepted by newer drivers.

* Thu Aug 06 2026 silisili contributors <noreply@localhost> - 1.1.0-0.51
- Accept the Sailfish bonito Qualcomm Venus decoder's legacy V4L2 contract:
  fall back from unsupported VIDIOC_TRY_FMT to the working VIDIOC_S_FMT probe.
- Keep V4L2-M2M ahead of software fallback while preserving copied frames for
  the persistent Cover-safe renderer and source-specific video geometry.
- Cache avatar responses and retry the alternate Bilibili image CDN hosts for
  author space and dynamic feeds when the first host fails.

* Thu Aug 06 2026 silisili contributors <noreply@localhost> - 1.1.0-0.50
- Match mpv 0.37's decoder selector implementation by using the exact FFmpeg
  short driver names and retain its automatic software fallback order.
- Capture the complete vd and ffmpeg/video initialization trace so a rejected
  Venus device or pixel format is visible in real-device semantic evidence.

* Thu Aug 06 2026 silisili contributors <noreply@localhost> - 1.1.0-0.49
- Use mpv's complete lavc decoder driver names so the V4L2-M2M priority list
  matches the bundled FFmpeg decoders instead of falling back to software.
- Report the active V4L2 device descriptor and filtered decoder diagnostics
  from libmpv for an evidence-based hardware decode gate on the real phone.

* Thu Aug 06 2026 silisili contributors <noreply@localhost> - 1.1.0-0.48
- Enable Qualcomm Venus decoding through private FFmpeg V4L2-M2M wrapper
  decoders while retaining software fallback and Cover-safe copied frames.
- Reallocate persistent video FBOs when the live/VOD host changes orientation,
  reset source geometry between media, and enforce aspect-preserving mpv state.
- Give QML avatar requests Bilibili CDN headers, a bounded disk cache, and
  two asynchronous alternate-CDN retries for author space and dynamics.

* Thu Aug 06 2026 silisili contributors <noreply@localhost> - 1.1.0-0.47
- Prefer mpv auto-copy-safe hardware decoding for high-frame-rate media while
  keeping the persistent Cover-safe GL renderer on ordinary copied frames.
- Log both the requested copy-back profile and the actual decoder backend.

* Wed Aug 05 2026 silisili contributors <noreply@localhost> - 1.1.0-0.46
- Restore normal-priority frame dispatch so file-loaded/playback events cannot
  be starved before the first visible frame.
- Keep comments and recommendations loading automatically, but instantiate
  only small staged preview batches to avoid the prior 8-10 second FPS dip.

* Wed Aug 05 2026 silisili contributors <noreply@localhost> - 1.1.0-0.45
- Prioritize shared-texture frame events over supplementary QML/network work.
- Load comments and related thumbnails only after explicit detail exploration.
- Stage small preview batches so 1080P60 playback keeps its 45 FPS floor.

* Wed Aug 05 2026 silisili contributors <noreply@localhost> - 1.1.0-0.44
- Add an in-process 45 FPS floor monitor for high-frame-rate media, using 60
  consecutive one-second windows and explicit 60-second/EOF summaries.
- Enable the lightweight libavcodec playback profile (automatic threading,
  fast decode, and non-reference loop-filter skipping) to preserve frame-rate
  headroom without changing the retained Cover renderer or playback clock.

* Wed Aug 05 2026 silisili contributors <noreply@localhost> - 1.1.0-0.43
- Drive the progress bar and displayed playback time from a dedicated 100 ms
  presentation clock, interpolated between authoritative libmpv time samples.
- Pause the presentation clock during pause, load, seek and cache buffering,
  while keeping decoder, shared textures and Cover recovery unchanged.

* Wed Aug 05 2026 silisili contributors <noreply@localhost> - 1.1.0-0.42
- Withdraw the previous video's shared texture immediately when navigation
  selects another source, instead of leaving a historical frame visible while
  the replacement URL resolves.
- Publish video again only after libmpv confirms playback restart for the newly
  started file; keep the persistent render context and texture pool intact.

* Wed Aug 05 2026 silisili contributors <noreply@localhost> - 1.1.0-0.41
- Replace the CPU QImage conversion/upload path with application-owned,
  double-buffered OpenGL textures shared with the Qt Quick scene graph.
- Keep libmpv's offscreen render context alive across Cover transitions while
  preserving the active decoder, audio clock, source and playback position.

* Wed Aug 05 2026 silisili contributors <noreply@localhost> - 1.1.0-0.40
- Separate libmpv decode/render from the Sailfish scene graph with a persistent
  software frame buffer, so Cover replaces only Qt's display texture.

* Wed Aug 05 2026 silisili contributors <noreply@localhost> - 1.1.0-0.39
- Recreate the Qt framebuffer after a Sailfish Cover return while preserving
  the active libmpv stream, audio, and playback position.

* Wed Aug 05 2026 silisili contributors <noreply@localhost> - 1.1.0-0.38
- Decode the active video to software frames before its initial load, so a
  Sailfish Cover EGL-context loss cannot strand hardware video textures behind
  a black resumed FBO. Cover return still performs no source reload or seek.
- Log the active decoder and interop state at file load for device evidence.

* Wed Aug 05 2026 silisili contributors <noreply@localhost> - 1.1.0-0.37
- Keep the active libmpv decoder, audio clock and GL context intact across a
  Sailfish Cover return whenever Qt retains the scene graph; request a fresh
  FBO present without reloading, seeking or rebuilding the still-valid context.
- Do not enable libmpv advanced render control for a window that Sailfish can
  suspend behind a Cover, so the render API is not left with an unserviceable
  callback contract while playback remains active.
- Remove all automatic Cover-time source reload and seek recovery paths.

* Wed Aug 05 2026 silisili contributors <noreply@localhost> - 1.1.0-0.36
- Recover the separate Cover case where audio continues but the resumed Qt
  Quick FBO is black: reload the active source once at its current clock after
  the foreground GL hand-off.

* Wed Aug 05 2026 silisili contributors <noreply@localhost> - 1.1.0-0.35
- Recover the real Sailfish Cover video-output failure (`VO_INIT_FAILED`) only
  after a fresh foreground GL context is attached, retaining source position
  and pause state instead of leaving the player black.

* Wed Aug 05 2026 silisili contributors <noreply@localhost> - 1.1.0-0.34
- Give the idle Cover a low-contrast diagonal watermark background inspired by
  Sailfish Settings, while retaining SiliSili branding and its native refresh action.

* Wed Aug 05 2026 silisili contributors <noreply@localhost> - 1.1.0-0.33
- Make PGC category changes cancel and invalidate older requests, so a slow
  rank response cannot replace the selected 番剧 or 影视 queue.
- Recreate only libmpv's GL render context after foreground activation, then
  repaint in stages; media decoding, audio, source URL and clock are retained.
- Repair SearchPage delegate sizing, refresh the no-playback Cover card, and
  add native UP 主 space with recent works and public dynamics from video detail.

* Wed Aug 05 2026 silisili contributors <noreply@localhost> - 1.1.0-0.32
- Make the PGC entry default to the real bangumi hot/rank list so the follow
  page order matches Bilibili ranking semantics instead of mixed tab modules.
- Restore foreground video by reattaching and repainting the current mpv
  framebuffer only; avoid source reloads and visibility toggles that interrupt
  background playback on resume.
- Reveal video detail metadata, comment previews, episode rows and related
  items progressively so delegate/image creation does not contend with active
  playback in a single frame burst.
- Explicitly open the Sailfish input panel for search and comment fields when
  they receive focus.

* Wed Aug 05 2026 silisili contributors <noreply@localhost> - 1.1.0-0.31
- Defer video-detail comment previews, related recommendations and Danmaku
  setup until playback has settled and the user scrolls near those sections,
  reducing page-entry and first-frame UI/main-thread contention.
- Stagger the remaining detail-page background work and add device log markers
  for the lazy loading path.

* Tue Aug 04 2026 silisili contributors <noreply@localhost> - 1.1.0-0.30
- Replace full-page quality dialogs in VOD/live fullscreen playback with a
  bottom overlay picker so the video remains visible while changing resolution.
- Refresh the native Cover idle state with a compact SiliSili card and account
  hint instead of a plain empty cover.
- Route PlaybackSession surface moves through the MpvVideoItem host-claim path
  and refresh the FBO after host switches to reduce black video after repeated
  inline/fullscreen/compact transitions.
- Add persistent native device tooling notes and a one-pass regression batch
  script using the reliable Python debug-shell transport.

* Tue Aug 04 2026 silisili contributors <noreply@localhost> - 1.1.0-0.29
- Make Home recommendation pagination use Flickable visibleArea and a light
  active-page timer, so loading continues when the footer is visible even if
  SilicaListView content coordinates do not report an exact bottom transition.

* Tue Aug 04 2026 silisili contributors <noreply@localhost> - 1.1.0-0.28
- Trigger Home feed pagination from near-bottom scrolling and movement end, so
  the default recommendation page keeps loading while the user stays at the
  bottom instead of waiting for an exact atYEnd transition.

* Tue Aug 04 2026 silisili contributors <noreply@localhost> - 1.1.0-0.27
- Advance the Home feed page cursor before notifying QML that loading ended so
  continuous bottom scrolling cannot request the same recommendation page twice.

* Tue Aug 04 2026 silisili contributors <noreply@localhost> - 1.1.0-0.26
- Add infinite-scroll pagination for the Home recommended and popular feeds:
  reaching the bottom now appends the next page instead of stopping at the
  initial batch.

* Tue Aug 04 2026 silisili contributors <noreply@localhost> - 1.1.0-0.25
- Align the in-app home title with the shorter SiliSili launcher name.
- Expand the video-detail comment preview from three to seven loaded main
  comments and clarify that the full comments page remains available.

* Tue Aug 04 2026 silisili contributors <noreply@localhost> - 1.1.0-0.24
- Rename the launcher entry to SiliSili and refresh the icon artwork crop so
  it fills the Sailfish launcher slot.
- Add a native left-edge swipe-back hot zone for full VOD and live players.
- Disable horizontal seek handling for live streams while keeping brightness,
  volume and tap controls, and add press-and-hold 2x speed for VOD playback.

* Tue Aug 04 2026 silisili contributors <noreply@localhost> - 1.1.0-0.23
- Seed the stable or legacy account snapshot into the Sailjail-whitelisted
  native config directory during package installation so login migration works
  when the app is launched from the icon.
- Log account nav success without exposing account names or cookie values.

* Tue Aug 04 2026 silisili contributors <noreply@localhost> - 1.1.0-0.22
- Persist QR-login cookies inside the Sailjail-whitelisted config directory,
  import the previous development session path when present, and preserve
  URL-encoded cookie values such as SESSDATA when saving native sessions.

* Tue Aug 04 2026 silisili contributors <noreply@localhost> - 1.1.0-0.21
- Prefer 1080P60 VOD/PGC playurl requests with DASH/fourk parameters, pass
  DASH audio tracks to mpv, and fall back to the old 720P progressive path
  when the account or video does not expose a >720P DASH video track.

* Tue Aug 04 2026 silisili contributors <noreply@localhost> - 1.1.0-0.20
- Reuse the process-lifetime mpv item for live playback, stop any VOD session
  before entering live, and recover stale single-instance locks after crashes.
- Make live playback URL requests latest-wins so stale network replies cannot
  load a live stream into a destroyed or replaced live page.

* Tue Aug 04 2026 silisili contributors <noreply@localhost> - 1.1.0-0.19
- Give portrait full-player controls a less crowded native layout with quality
  on its own full-width row and danmaku actions grouped below it.

* Tue Aug 04 2026 silisili contributors <noreply@localhost> - 1.1.0-0.18
- Reflow portrait full-player controls into native-width grouped rows so the
  VOD fullscreen button area no longer looks crowded in portrait orientation.

* Mon Aug 03 2026 silisili contributors <noreply@localhost> - 1.1.0-0.17
- Make tapping the in-app compact player restore the previous playback detail
  page in the PageStack instead of always opening the full-page player.

* Mon Aug 03 2026 silisili contributors <noreply@localhost> - 1.1.0-0.16
- Remove the duplicated in-page "More functions" menu from the Home page now
  that secondary navigation lives in the native pull-down "More content" page.

* Mon Aug 03 2026 silisili contributors <noreply@localhost> - 1.1.0-0.15
- Restore the reliable foreground source-reload recovery path because the
  lightweight 0.14 nudge can still resume with a black Sailfish/Wayland video
  surface on device.

* Mon Aug 03 2026 silisili contributors <noreply@localhost> - 1.1.0-0.14
- Make Sailfish foreground restore smoother by using a lightweight current-position
  mpv nudge after the surface refresh instead of reloading the network source.

* Mon Aug 03 2026 silisili contributors <noreply@localhost> - 1.1.0-0.13
- Rebuild the foreground playback surface after Sailfish Cover/app restore and
  reload the current mpv source at the preserved position when needed so audio
  playback does not return with a black video frame.
- Reduce the reserved player back-swipe corridor and center the fullscreen
  seek slider so progress controls no longer appear shifted to the right.

* Mon Aug 03 2026 silisili contributors <noreply@localhost> - 1.1.0-0.12
- Replay the current mpv source from the beginning when the user presses play
  after EOF, including inline, fullscreen, compact and Cover controls.

* Mon Aug 03 2026 silisili contributors <noreply@localhost> - 1.1.0-0.11
- Make QR login navigation robust by always opening the native login page and
  creating the system QR item at runtime with an inline fallback error.
- Refresh the libmpv framebuffer on Sailfish foreground restore so background
  playback does not resume with audio-only black video.
- Replace the account page overlay placeholder with inline status text to avoid
  covering the "no available login session" message.

* Mon Aug 03 2026 silisili contributors <noreply@localhost> - 1.1.0-0.10
- Re-apply LC_NUMERIC=C immediately before lazy mpv_create() because
  Sailfish launcher/Silica startup can restore the device locale after main().

* Mon Aug 03 2026 silisili contributors <noreply@localhost> - 1.1.0-0.9
- Normalize LC_NUMERIC before Qt/mpv startup so Sailfish launcher/sailjail
  sessions can create the shared mpv client just like direct debug launches.

* Mon Aug 03 2026 silisili contributors <noreply@localhost> - 1.1.0-0.8
- Lazily create and retry the shared mpv client when real playback starts.
- Treat expired or unavailable account state as a recoverable login state.
- Replace the development launcher icon with the updated high-resolution art.

* Sun Aug 02 2026 silisili contributors <noreply@localhost> - 1.1.0-0.7
- Replace the crowded home shortcut grid with one compact primary row for
  live, recommended, popular and PGC content plus collapsed secondary actions.
- Add fixed inline VOD and PGC players with persistent progress, native seek
  sliders, horizontal seeking, and split brightness/volume gestures.
- Serialize video resolution requests, defer supplementary detail work, expose
  complete paginated comments, and guard the process against duplicate starts.
- Separate playback state from render-surface ownership so inline, fullscreen,
  dialogs, compact mode and the static Cover share one persistent VOD backend.

* Sun Aug 02 2026 silisili contributors <noreply@localhost> - 1.1.0-0.6
- Move the shared playback surface into the active Sailfish Cover scene so
  background play/pause actions and progress continue to reach mpv.

* Sun Aug 02 2026 silisili contributors <noreply@localhost> - 1.1.0-0.5
- Preserve the current position and requested pause state when Qt recreates
  the shared mpv renderer during inline, fullscreen and compact transitions.

* Sun Aug 02 2026 silisili contributors <noreply@localhost> - 1.1.0-0.4
- Track actual playback and end-of-file state so display blanking is inhibited
  only while media is genuinely playing; retain aspect-aware orientation and
  transient controls.

* Sun Aug 02 2026 silisili contributors <noreply@localhost> - 1.1.0-0.3
- Use the supported Nemo.KeepAlive 1.2 display blanking object so only active
  foreground playback keeps the display awake.

* Sun Aug 02 2026 silisili contributors <noreply@localhost> - 1.1.0-0.2
- Add aspect-aware fullscreen orientation, transient playback controls,
  collision-aware danmaku lanes, compact playback polish, and native
  home navigation.

* Fri Jul 31 2026 silisili contributors <noreply@localhost> - 1.1.0-0.1
- Add the first native Silica vertical slice with PageStack, live home feed,
  pull-down refresh, Sailfish Cover, and read-only stable config migration.
