# Native Sailfish OS device validation

Device: Google Pixel 3a XL (`bonito`) running Sailfish OS 5.2.0.16. Current
VM wrapper build target: `SailfishOS-5.1.0.11-aarch64`.

Latest built development package:

- NEVRA: `silisili-native-devel-1.1.0-1.57.aarch64`
- RPM SHA-256: `6960aa8795478ecdabf70bad048ec924617be6ac06f91a5e0d92e8a322b0f9ae`
- RPM bytes: `12540967`
- RPM: `outputs/silisili-native-devel-1.1.0-1.57.aarch64.rpm`
- Build date: `2026-08-24`
- Device install status: installed on `2026-08-24`; the exact transferred
  SHA-256 was verified, 1.56 was upgraded, and
  `rpm -V silisili-native-devel` finished clean.

Latest installed development package:

- NEVRA: `silisili-native-devel-1.1.0-1.57.aarch64`
- RPM SHA-256: `6960aa8795478ecdabf70bad048ec924617be6ac06f91a5e0d92e8a322b0f9ae`
- RPM bytes: `12540967`
- RPM: `outputs/silisili-native-devel-1.1.0-1.57.aarch64.rpm`
- Build/install date: `2026-08-24`
- stable package state during this validation: absent

## Latest 1.57 in-application compact-player close lifecycle

- The compact-player close button no longer detaches only its visible surface.
  It synchronously stops the complete `PlaybackSession`, stops mpv, releases
  the shared video texture and direct host, and lets the existing Cover object
  return to idle with all three action icon sources empty.
- The device probe loaded a real 1080P VOD, required a live shared texture in
  the in-application compact player, physically opened its controls, read the
  close center `(1003,1920)` from current runtime geometry, and physically
  tapped that coordinate.
- The handling marker started with `sessionActiveBefore=true`,
  `mediaKindBefore=video`, and `playingBefore=true`. The synchronous completion
  marker reported `sessionActive=false|compact=false|playing=false|mediaKind=none`.
  The same PID and start time survived while Cover reported
  `content=idle|actionsEnabled=false|actions=0`; pause, presentation, and close
  icon sources were all empty.
- The terminal result was
  `native_compact_close_stop=ready|run=compact-close-20260824T154700Z|package=silisili-native-devel-1.1.0-1.57.aarch64|pid=22696|close=1003,1920|session_active=0|playing=0|compact=0|cover=idle|actions=0|same_pid=1|rpm_verify=clean|visual_model=unused`
  and `sailfish_test=ready|checks=12/12`. No visual model was used.

## Latest 1.56 Home compact-player Cover lifecycle

- Cover playback eligibility now accepts either an explicit playback page or
  an active, unfinished Home compact-player session. A residual session on an
  unrelated page remains in the idle Cover state.
- The device probe started a real VOD, moved it from the detail page to the
  actual Home page compact player, and required
  `eligiblePage=false|compactActive=true|content=playback|actionsEnabled=true`.
  A physical background gesture retained live shared-texture Cover frames, all
  three actions, PID `40237`, and the original process start time.
- The terminal result was
  `native_compact_cover_context=ready|run=compact-cover-20260823-230827|package=silisili-native-devel-1.1.0-1.56.aarch64|pid=40237|transition=video-detail-to-home|session_active=1|compact_active=1|content=playback|actions_enabled=1|actions=3|background_entry=physical-gesture|mode_restored=pip|same_pid=1|rpm_verify=clean|visual_model=unused`.
- The fresh Cover artifact is
  [silisili-compact-home-cover.png](screenshots/5x-test/silisili-compact-home-cover.png).
  PNG integrity is `1080x2160`, `2028166` bytes, SHA-256
  `2765ec393e52691c6e60a128e2acaae4e2a305e079eefda47d6f58038d466699`.
  This is artifact-integrity evidence; no visual model was used.

## Latest 1.56 idle Cover action lifecycle

- The 1.56 AArch64 candidate was built in the Sailfish VM as
  `silisili-native-devel-1.1.0-1.56.aarch64` and its local SHA-256 is
  `b28f307b84dc6c7fc1087e41782b4faa01995be11d85b5011b5d023dc3bddfb6`.
- Sailfish 5.2 retained stale Cover action pixels after disabling or replacing
  an existing `CoverActionList`. The final implementation keeps one
  `CoverPage.qml` and one three-action list for the process lifetime. When the
  current page/session is not playback-eligible, all three existing
  `iconSource` bindings become empty in place and every handler rejects a stale
  trigger. Idle artwork is still only the tiled watermark and centered Logo.
- The exact RPM transfer/install transaction matched the local SHA-256,
  installed the expected NEVRA, and completed with `rpm_verify=clean`.
- A fresh playback Cover was captured after a physical background gesture as
  [silisili-cover-stop-before.png](screenshots/5x-test/silisili-cover-stop-before.png).
  A physical tap at Cover close coordinate `(442,808)` emitted
  `native cover: stop action handled`, changed the same process to
  `session_active=0|content=idle|actions=0`, and emitted the marker that all
  three icon sources were empty. PID `37856` and start time `16037388` were
  unchanged. The fresh result is
  [silisili-cover-stop-after.png](screenshots/5x-test/silisili-cover-stop-after.png).
- PNG integrity checks passed at `1080x2160`. Playback/idle SHA-256 values are
  `d3d44e858bb8cb2d59ebe3779196c105b8de99f8d244cd8087c4129690e3314b`
  and `501826677d9ee31cf61b105f9d7a9baa4db2e782bf7c295718f5c578731f8677`.
  The current-package cold-idle reference SHA-256 is
  `23eb9a57f82a0d7672b437b74f3d4da0633af542b1078fefac111016c203488d`.
- Conventional alpha-template NCC at the known cancel center measured
  `0.9932` before stop and `0.1080` after stop. The after-stop pause,
  presentation and cancel `48x48` RGBA regions are each byte-for-byte equal to
  the freshly captured current-package cold-idle Cover regions, while
  respectively 2304, 1158 and 1939 of 2304 pixels changed from playback. This
  closes both the semantic and stale-Lipstick-pixel boundaries. No visual
  model was used.

## Latest 1.55 anonymous default quality validation

- Anonymous ordinary video and PGC playback now request QN 64 (720P) by
  default. Signed-in cold starts retain QN 80 by using synchronously loaded
  `SESSDATA`/`DedeUserID` credentials while `/nav` is still pending.
- The exact-qn DASH request remains authoritative. If an anonymous QN 64
  response exposes only a 480P DASH track, the resolver retries the QN 64
  progressive endpoint and publishes its real 720P media instead of silently
  lowering the default.
- The source gate requires the account-quality properties, QN 64/80 policy,
  PGC coverage, and the isolated anonymous quality probe.
- The first 1.55 device run confirmed the anonymous policy marker and one
  media load, but the upstream DASH response for the fixed sample contained
  only QN 32. That diagnostic led to the bounded progressive-720P fallback;
  it is not counted as a final pass.
- The final package was reinstalled after the Home prefetch/fullscreen entry
  audit and passed the isolated real-device probe:
  `native_anonymous_default_quality=ready|run=anonymous-quality-20260822-final|package=silisili-native-devel-1.1.0-1.55.aarch64|bvid=BV1P4ddBBEJF|cid=37630051884|logged_in=0|session_credentials=0|requested_qn=64|selected_qn=64|video=1280x720|route=progressive-720p|loads=1|first_frames=1|same_pid=1|rpm_verify=clean|production_account=untouched|visual_model=unused`.

## Latest 1.54 page-aware idle Cover validation

- The checksum-closed 1.54 AArch64 RPM was built in the `MeeGo Build` VM,
  verified as `silisili-native-devel-1.1.0-1.54.aarch64`, transferred with the
  same SHA-256, installed on Sailfish OS 5.2.0.16, and passed
  `rpm -V silisili-native-devel`.
- Video detail, PGC detail, full-player and live-player pages now expose one
  explicit `coverPlaybackPage` marker. Cover playback content requires both an
  eligible current page and an active, unfinished playback session. All other
  pages select the idle watermark and Logo even if the shared player session
  remains active.
- Sailfish `CoverActionList` exposes `enabled`, not a visual-item `visible`
  property. Its enabled state now follows the same page-aware Cover state, and
  every action handler independently rejects a stale trigger when the state is
  idle.
- The device probe established real playback on a video detail page, observed
  `content=playback` with actions enabled, then used the existing compact
  transition to open a non-video navigation page without stopping playback.
  It observed `session_active=1`, `content=idle`, and `actions_enabled=0`, then
  sent a physical background gesture and retained the same PID. The original
  `pip` preference was restored and the test process was stopped:
  `native_idle_cover_context=ready|run=idle-cover-20260822-135717|package=silisili-native-devel-1.1.0-1.54.aarch64|pid=43017|transition=video-detail-to-non-video|session_active=1|content=idle|actions_enabled=0|background_entry=physical-gesture|mode_restored=pip|same_pid=1|rpm_verify=clean|visual_model=unused`.
- Source verification passed with 55 active native sources and 45 QRC
  resources. No visual model was used.

## Latest 1.53 compact drag, comment type and two-column validation

- The checksum-closed 1.53 AArch64 RPM was built in the `MeeGo Build` Sailfish
  VM, verified as `silisili-native-devel-1.1.0-1.53.aarch64`, transferred to
  Sailfish OS 5.2.0.16 with the same SHA-256, installed, and passed
  `rpm -V silisili-native-devel`.
- The compact player no longer instantiates `PlayerGestureArea`; one full-size
  `compactDragArea` owns video-area dragging, taps and double taps, while the
  bottom controls remain above it. Compact playback therefore has no seek,
  brightness or volume gesture branch to intercept repositioning.
- A physical center drag moved the compact surface from
  `(358,1573,702,395)` to `(218,1478,702,395)`. Brightness stayed at `17`, raw
  `x-maemo` media volume stayed at `55117`, no `native gesture:` or system
  control write marker appeared, PID `28469` stayed unchanged, and RPM
  verification remained clean:
  `native_compact_drag=ready|package=silisili-native-devel-1.1.0-1.53.aarch64|pid=28469|initial_geometry=358,1573,702,395|dragged_geometry=218,1478,702,395|brightness=17|volume_raw=55117|system_gestures=absent|same_pid=1|rpm_verify=clean|visual_model=unused`.
- The paired detail-player regression changed StreamRestore media volume from
  `55117` to `31492` through a physical right-side gesture and restored it to
  `55117` after playback stopped. PID `34571` remained unchanged and RPM
  verification stayed clean:
  `native_volume_gesture=ready|package=silisili-native-devel-1.1.0-1.53.aarch64|pid=34571|surface=video-detail-inline|direction=down|initial_raw=55117|changed_raw=31492|restored_raw=55117|route=pulse-stream-restore-x-maemo|physical_gesture=handled|same_pid=1|rpm_verify=clean|visual_model=unused`.
- Comment bodies in video-detail preview, the full comment page, the root
  reply, and nested replies now explicitly use `Theme.fontSizeSmall` through
  the global small/medium/large scaling helper. Author, time and action-label
  hierarchy is unchanged.
- `AppSettings` now uses two columns when `ui/contentColumns` has never been
  saved. An explicit one-column or two-column user preference is preserved.
  The post-install device preflight reported `content_columns=2` and
  `font_size_mode=0`, so the tested phone is currently on the requested
  two-column layout and small global type mode.
- Source verification passed with 55 active native sources and 45 QRC
  resources. No visual model was used.

## Latest 1.52 detail-only system controls and media-volume validation

- The final checksum-closed 1.52 AArch64 RPM was built in the `MeeGo Build`
  Sailfish VM, transferred through USB RNDIS to the Pixel 3a XL running
  Sailfish OS 5.2.0.16, installed with exact SHA-256/NEVRA checks, and passed
  `rpm -V silisili-native-devel`.
- System brightness and volume gestures are now deliberately limited to the
  ordinary-video detail player, PGC detail player, full-screen player and live
  player. The in-app compact player sets
  `systemControlGesturesEnabled: false` and has no `SystemControls` route.
- Sailfish 5.2 keeps its actual media level in PulseAudio StreamRestore entry
  `sink-input-by-media-role:x-maemo`; the default sink remains at 100% and is
  not the user-visible media level. `SystemControls` therefore reads and writes
  that entry through the PulseAudio peer D-Bus socket, without spawning one
  `pactl` process for every move event. The active sink/sink-input `pactl` path
  remains a compatibility fallback when StreamRestore is unavailable.
- The physical detail-page gesture probe received the QML handling marker,
  kept one process, changed the raw `x-maemo` value from `45875` to `65536`,
  and restored it exactly to `45875` after playback stopped:
  `native_volume_gesture=ready|package=silisili-native-devel-1.1.0-1.52.aarch64|pid=24706|surface=video-detail-inline|direction=up|initial_raw=45875|changed_raw=65536|restored_raw=45875|route=pulse-stream-restore-x-maemo|physical_gesture=handled|same_pid=1|rpm_verify=clean|visual_model=unused`.
- The compact-player negative probe injected physical vertical swipes on both
  sides of the visible `702x395` compact surface. Both were handled as disabled
  system-control gestures, brightness stayed at `1`, raw media volume stayed at
  `45875`, and no brightness/volume write marker appeared:
  `native_compact_system_controls=ready|package=silisili-native-devel-1.1.0-1.52.aarch64|pid=25383|geometry=358,1573,702,395|left_vertical=ignored|right_vertical=ignored|brightness=1|volume_raw=45875|same_pid=1|rpm_verify=clean|visual_model=unused`.
- Source verification passed with 55 active native sources and 45 QRC
  resources. No visual model was used for either device test.

## Latest 1.51 minimedia boot-race and VM build-record validation

- Correct build entrypoint is the running Parallels VM `MeeGo Build`, invoked
  from macOS with
  `prlctl exec 'MeeGo Build' /usr/bin/env REUSE_OBJECTS=1 /bin/bash /media/psf/AllFiles/Users/zerox/Documents/Codex/2026-07-31/silisili-native-sailfish/work/vm-build-native-rpm.sh`.
  The macOS shell holds the shared source tree and `outputs/` artifacts but is
  not itself the Sailfish SDK. Treat `/opt/sailfish-hadk`/`sb2` absence on
  macOS as a context issue, not as a build blocker.
- `work/vm-build-native-rpm.sh` now includes `appsettings.cpp`,
  `systemcontrols.cpp`, their moc objects, and every RPM stage asset required
  by the current spec: minimedia shim, minimedia wrapper, systemd unit,
  privileges, and Cover mode icons. Source verification now checks this wrapper
  so future hand-maintained list drift fails before link or RPM packaging.
- The minimedia compatibility wrapper now uses an atomic
  `/run/silisili-native-minimedia.lock`, exits immediately if another wrapper
  is already starting, waits through the known boot race window, and yields if a
  real `/system/bin/minimediaservice` is already present. The unit is ordered
  `After=local-fs.target droid-hal-init.service` to reduce the Android-init
  race window before the wrapper starts.
- The 1.51 RPM was built and installed successfully:
  `native_fast_install=ready|nevra=silisili-native-devel-1.1.0-1.51.aarch64|sha256=9724b4738e7ce9613b90c5a8ff7b2ba905e7f3b1186ce13a59d24bb866e810e6|rpm_verify=clean|visual_model=unused`.
- Read-only phone audit reported exactly one minimediaservice process, the
  guard present in the installed wrapper, the unit ordering present, and clean
  RPM verification:
  `native_minimedia_boot_race=ready|package=silisili-native-devel-1.1.0-1.51.aarch64|processes=1|service=active|result=success|mainpid=37408|camera_processes=10|droid_hal_processes=3|rpm_verify=clean|wrapper_guard=present|unit_after=droid-hal-init|visual_model=unused`.
  Camera-related processes were in normal sleeping state during this audit; no
  duplicate minimediaservice or kernel D-state deadlock was observed.
- The explicit reboot-cycle validation was then run with
  `vm-deploy/scripts/probe-silisili-native-minimedia-reboot-cycle.sh`.
  The debug-shell port went down and came back after reboot, and the post-boot
  read-only audit again found exactly one minimediaservice process:
  `native_minimedia_boot_race=ready|package=silisili-native-devel-1.1.0-1.51.aarch64|processes=1|service=active|result=success|mainpid=6284|camera_processes=2|droid_hal_processes=3|rpm_verify=clean|wrapper_guard=present|unit_after=droid-hal-init|visual_model=unused`.
  The cycle finished with
  `native_minimedia_reboot_cycle=ready|run=20260821T181109Z|phone=192.168.2.15:2323|visual_model=unused`.

## Latest 1.50 system controls and font-size build validation

- The exact checksum-closed 1.50 AArch64 RPM was built in the Sailfish SDK and
  passed RPM digest and NEVRA checks as
  `silisili-native-devel-1.1.0-1.50.aarch64`.
- Full-screen vertical gestures now call `SystemControls` instead of changing
  libmpv-local brightness or volume. The left side now prefers Sailfish
  `mcetool --set-display-brightness` and keeps writable sysfs backlight as a
  fallback; the right side writes PulseAudio media volume through the active
  user's runtime socket. Playback start records the original values for
  playback-ended, playback-inactive and application-quit restoration.
- `AppSettings` now stores a persistent small/medium/large font-size mode.
  Explicit QML `Theme.fontSize*` usages across lists, details, comments,
  settings, Cover and player gesture hints route through
  `appSettings.scaledFontSize(..., appSettings.fontSizeMode)` so the binding
  is recalculated as soon as the user changes the mode; the danmaku overlay
  keeps its dedicated danmaku-size setting.
- Source verification passed with 55 active native sources and 45 QRC
  resources. The new regression gates reject a future return to local
  `controller.setVolume()` / `controller.setBrightness()` gesture handling and
  require the system-control restore hooks to remain connected.
- No visual model was used. The corrected read-only system-control probe ran
  on the phone and confirmed Sailfish OS 5.2.0.16, `mcetool` brightness status
  `Brightness: 80 (1-100)`, PulseAudio default sink `sink.primary_output`, and
  the active user socket `/run/user/100000/pulse/native`.
- A bounded backend transaction changed brightness from `80` to `75` and
  restored it to `80`, then changed PulseAudio media volume from `100` to `95`
  and restored it to `100`. The still-running 1.48 process was then closed
  (`silisili_stop_pre_pids=17832`, `silisili_stop_post_pids=`) so the next
  launcher start uses the installed 1.49 binary.
- Follow-up manual testing confirmed the brightness path worked but volume did
  not affect the current playback stream. PulseAudio diagnosis while
  `silisili-native` was playing found an active `Sink Input #48` owned by
  process `24214`, `application.process.binary = "silisili-native"`,
  `application.name = "mpv"`, and stream volume `79%` while the default sink
  was `52%`. 1.50 therefore writes both the default sink and the active
  `silisili-native` sink-input.
- The 1.50 RPM was installed successfully:
  `native_fast_install=ready|nevra=silisili-native-devel-1.1.0-1.50.aarch64|sha256=5a338f125713d2009e70039149a40deec48cfaba4d86a8e0452e50bbcfb9363f|rpm_verify=clean|visual_model=unused`.
  The still-running 1.49 process was closed before handoff
  (`silisili_stop_pre_pids=24214`, `silisili_stop_post_pids=`), so the next
  launcher start uses the installed 1.50 binary.

## Latest 1.47 Cover action icon validation

- The exact checksum-closed 1.47 AArch64 RPM was installed through the device
  debug shell. The installed package identity matched the candidate NEVRA and
  `rpm -V silisili-native-devel` was clean.
- The Cover/mini-player presentation switch remains the middle action in the
  three-action system Cover bar. Its image source now points at public RPM
  payloads under `/usr/share/icons/hicolor/86x86/apps/`, rather than the
  application-only `qrc:/` resource namespace that Lipstick cannot reliably
  resolve while rendering a Cover action.
- A fixed VOD was launched, backgrounded through the physical input injector,
  and captured through the device screenshot helper. The same process remained
  inactive behind Lipstick while the Cover reported one active layout, shared
  persistent texture ownership and advancing frame serials; no system PiP
  surface was shown in Cover mode.
- The raw device PNG is `1080x2160`, `1835616` bytes, with SHA-256
  `0e95a6a2da219005f9d628752f075e788e44c7d41a9c6397234cc6a839e9e5b1`.
  Screenshot collection was used as a user-review artifact only; acceptance
  evidence came from package, process, background-state and frame markers, and
  no visual model was used.

## Latest 1.44 balanced Cover layout validation

- The exact checksum-closed 1.44 AArch64 RPM was built from a clean full source
  tree, verified on the host and phone, installed on the device and remained
  clean under `rpm -V`.
- A fixed 1080P VOD resumed at 14 seconds through the production hardware path.
  The single load reached its first shared texture without software fallback,
  then the transformed physical edge gesture put the same PID in the
  background without pausing or seeking.
- The active Cover reported the required resolution, video, single-line title,
  progress and three-action order. Its three dynamic gaps measured 63 pixels;
  occupied and available content heights both measured 602 pixels, satisfying
  the runtime balanced-layout invariant.
- The real Cover scene graph shared the persistent video texture and presented
  advancing frames 24 through 54. The session retained one media load and the
  same process identity with no hidden seek, software fallback, QML error or
  renderer error.
- Source verification passed with 51 active sources and 42 QRC resources. All
  evidence came from package, process, physical-input, decoder, frame-serial
  and QML geometry markers; no screenshot interpretation or visual model was
  used.

## Historical 1.43 Cover and system PiP presentation validation

- The exact checksum-closed 1.43 AArch64 RPM was rebuilt from the current QML
  resources, verified in the SDK VM and on the phone, installed over the prior
  development build and remained clean under `rpm -V`.
- The idle Cover instantiated only the supplied `144x56` brand Logo over 40
  staggered, diagonally tiled handheld-console silhouettes. The active Cover
  instantiated the ordered resolution, moving video, single-line title,
  progress/time and action layout with exactly three Cover actions.
- A real live stream advanced Cover shared-texture serial 39 through 69. Cover
  and system PiP each submitted one media load, used one shared decoder and
  returned without a background pause, hidden seek recovery or software
  fallback. The PiP path identified the session as live.
- Closing the application while PiP was active released its one decoder and
  one buffer generation symmetrically. Application, overlay and playback
  process counts were all zero afterward, and background mode was restored to
  Cover.
- Source verification passed with 51 active sources and 42 QRC resources. All
  evidence came from package, process, decoder, frame-serial, QML semantic and
  cleanup markers; no screenshot interpretation or visual model was used.

## Latest 1.40 full-source live presentation and orientation-stable quality switching

- The exact checksum-closed 1.40 RPM was transferred through the debug shell,
  verified again on the phone, installed over the previous development build
  and remained clean under `rpm -V`.
- A cold direct live request used application quality `0` and wire quality
  `qn=10000`. The selected test room exposed three qualities
  (`10000,400,250`), so the device performed a real quality transition rather
  than marking the multi-quality path not applicable.
- The original live stream entered DroidMedia/OMX as `1920x1080@60`. The
  full-screen shared framebuffer was `2160x1080`, its effective fitted video
  viewport was the full `1920x1080`, and the semantic gate reported
  `profile=fullscreen-native` plus `sourcePixelsPreserved=true`. This closes
  the prior case where a true 1080p decoder input was visibly blurred by an
  `800x400` final shared framebuffer.
- The quality cycle changed from `qn=10000` to `qn=250` in the same process.
  Physical pause/resume remained functional, hardware frame serial advanced
  from 61 to 1861 over the following 60 seconds at `29.82 fps`, free CMA stayed
  above the `32768 KiB` guard, and no first-frame timeout or software fallback
  occurred.
- `PlaybackSession` now retains the last confirmed video aspect while a VOD or
  live decoder geometry is deliberately cleared for quality replacement. A
  real full-screen VOD panel selection changed `qn=112` (1080P+) to `qn=80`
  (1080P) while the same PID and `2160x1080` player page remained landscape.
  No `vod-player orientation portrait` marker, decoder fallback or process
  reconstruction occurred. The live switch likewise retained aspect
  `1.77778` and emitted no portrait page layout.
- Runtime, process, physical-input, decoder, shared-texture and effective
  viewport markers were used throughout. No screenshot interpretation or
  visual model was used.

## Historical 1.39 real live quality and background presentation

- The exact checksum-closed 1.39 RPM was transferred through the debug shell,
  verified again on the phone, installed over development package 1.38 and
  remained clean under `rpm -V`.
- A cold direct room request used application quality `0` and wire quality
  `qn=10000` instead of the old fixed `qn=250`. The resolver accepted the
  server's actual `current_qn`, passed capability-aware AVC/HEVC candidate
  selection and emitted the decoded width/height/source-fps quality marker.
- The current test room exposed one server-advertised quality, so the physical
  multi-quality cycle was correctly recorded as not applicable. A separate
  sample of 20 currently live rooms also advertised only `qn=10000`; no
  multi-quality pass is inferred or fabricated from that server state.
- Live playback retained one process for 60 seconds. Hardware frame serial
  advanced from 61 to 1861 at `29.80 fps`, physical pause/resume changed the
  live transport state in the same PID, free CMA stayed at `114648 KiB`, and
  no first-frame timeout, stall, queue pressure or software fallback occurred.
- Live Cover presented advancing shared-texture frames 37 through 67 with one
  media load and no pause or seek recovery. Live system PiP reported
  `mediaKind=live`, retained one load/decoder, stayed above its display-frame
  guard and returned to the same foreground session without a hidden seek.
- Closing the application while live system PiP was visible completed the
  shutdown barrier. Its one DroidMedia decoder generation released one
  balanced buffer-reference generation; application, overlay and playback
  process counts were all zero afterward.
- The normal Invoker launch was restored with package 1.39, PID `25821` was the
  Lipstick topmost PID, background mode was restored to Cover and the system's
  normal display blanking policy was restored. The debug launcher now waits
  for the real mapplauncherd application command prefix and foreground PID,
  avoiding false failures caused by padded booster command lines.
- Runtime, process, package, physical-input, decoder and shared-texture markers
  were used throughout. No screenshot interpretation or visual model was used.

## Historical 1.38 decoder lifetime, quality matrix and shutdown closure

- Droidmedia's client-owned strong reference for every created gralloc buffer
  is now tracked explicitly. A buffer-queue release only records the release
  boundary; references are destroyed after demux/presentation workers stop and
  their raw-pointer queues are empty. This fixes both long-run CMA exhaustion
  and the first attempted immediate-release teardown race.
- The full real-device VOD matrix switched through every quality advertised by
  the test asset (`qn=16,32,64,80,112`, 360P through 1080P+) in one process.
  All six decoder generations balanced their created/destroyed references and
  free CMA remained at least `70412 KiB`.
- Six deterministic full-screen 1080P+ video-stall injections recovered in the
  same PID, advanced generation 1 through 7, retained the current texture,
  kept audio reloads at zero and media loads at one, and recovered at
  `30.12 fps`. Every retired decoder generation balanced its buffer references.
- The 1080P60/4K/8K guard ran 60 seconds with 63 frame windows and minimum
  `55.773 fps`. Unsupported 4K/8K requests stayed on the verified real
  1920x1080 hardware representation, with no unsafe UHD OMX attempt, software
  fallback or frame-queue pressure.
- Closing the primary application while system PiP was visible exercised the
  close-event and `aboutToQuit` barriers. PiP timers, input region, notification
  surface, playback session, hardware decoder and persistent GL/mpv backend
  were released; post-exit application-process, overlay and playback-process
  counts were all zero.
- Three non-zero history starts each resumed at 14 seconds with one media load,
  kept audio gated until the target frame, and avoided software fallback. The
  maximum media-command-to-frame time was `1675 ms` and maximum full
  request-to-frame time was `1966 ms`.
- Live playback ran 60 seconds at `30.01 fps`. Its Cover advanced shared frames
  31 to 61, and live system PiP used `mediaKind=live`; both modes retained one
  decoder and one media load with no hidden seek, pause or software fallback.
- The installed RPM passed `rpm -V`; all of these gates used runtime/process,
  media, frame, resource and physical-input markers without a visual model.

## Historical 1.35 unified VOD/live session and background presentation

- `PlaybackSession` is now the common presentation owner for ordinary VOD,
  PGC and live. It alone owns the persistent player, foreground surface,
  shared texture, pause/stop state, Cover, system PiP and foreground recovery.
- `PlaybackResolver` and `LiveResolver` remain separate source adapters. VOD
  retains history, seek, speed, multi-part continuation and its `127` quality
  ceiling; live retains server QN values, non-seekable/non-speed semantics and
  cancels an outstanding room request when its session closes.
- A live-to-VOD/PGC handoff now cancels the old live resolution before the
  on-demand resolver is allowed to publish, retains the presentation surface,
  and resets playback speed to 1x. Entering live also resets speed, so a prior
  VOD 1.25x/2x setting cannot leak into the non-seekable stream.
- A live page no longer pauses itself when Sailfish backgrounds the app and no
  longer loads a URL directly. The selected background mode therefore mirrors
  the same advancing live texture in Cover or system PiP without a second
  decoder or media reload.

Current 1.35 device results:

- One live room ran for 60 seconds in one PID. Hardware frame serial advanced
  from 61 to 1861 at `29.92 fps`; physical pause/resume worked, only one media
  load was submitted and no software fallback occurred.
- Live Cover advanced real shared-texture frames from 27 to 57. Returning to
  foreground retained the same process, decoder and single load, without a
  hidden seek or background pause.
- Live system PiP logged `mediaKind=live`, advanced real frames and returned to
  foreground with one load, no hidden seek, no background pause and no
  fallback. The user-selected background mode was restored to Cover afterward.
- Ordinary VOD Cover advanced frames from 91 to 121 with the same decoder and
  zero reloads. Ordinary VOD system PiP passed two background/restore cycles
  with zero low-frame windows, zero remap flashes and no fallback.
- Two-part VOD auto-next used two hardware decoder generations in the same
  process and withdrew the first part texture before part two was loaded and
  presented.
- Three history-position starts each presented the requested 14-second frame
  from one load while audio stayed gated until confirmation. Maximum
  media-load-to-frame latency was `2241 ms`; maximum full request-to-frame was
  `2780 ms`. The functional isolation gate passes, but the full path remains
  above the separate 2-second startup performance target.
- The package remained clean under `rpm -V`; all evidence came from process,
  decoder, load-serial, shared-texture and physical-input markers. No screenshot
  interpretation or visual model was used.

## 1.34 live, global texture sharing and regression closure

All gates used application, decoder, shared-texture, process, package and
physical-input markers. No screenshot interpretation or visual model was used.

- The live-only repair preserves the 1.25 VOD paint path. A live load waits
  for the process-lifetime renderer, normalizes wallclock-like FLV/HLS PTS to
  the libmpv audio clock, and gives only live containers the larger audio
  discovery probe. Normal DASH VOD continues through `loadSourceWithAudio()`
  with the old probe budget and strict Qt share-group check.
- Sailfish 5.1 did not create Qt's global share context from
  `AA_ShareOpenGLContexts` before a cold direct page. Sharing the offscreen
  renderer only with the main window fixed foreground live video but left the
  separately rendered Cover outside that group. 1.34 seeds Qt's exported
  process-wide global share context before either QQuick scene graph exists;
  foreground, Cover and system PiP then all join the same group.
- A cold direct live room ran for 60 seconds in one PID. Hardware frame serial
  advanced from 61 to 1861 at `29.96 fps`, physical pause/resume worked, CMA
  remained stable, the streaming timeline was normalized and no software
  fallback occurred.
- The ordinary Home first-card VOD used its prepared hardware frame in the
  same process after a physical tap. The main scene graph reported texture
  sharing true and did not enter first-frame fallback.
- Cover reported texture sharing true and presented different live hardware
  frames 98 and 128. Returning to foreground retained the decoder and media
  load, with no seek recovery. System PiP then passed two complete
  background/foreground cycles, two appearances, two restore guards, zero
  remap flashes and no display window below 45 fps.
- Three 14-second history resumes each used one media load with
  `audio_before_target=0`; maximum media-command-to-frame latency was 1801 ms
  and maximum full request-to-frame latency was 2375 ms. The functional gate
  passes, while the latter remains above the separate 2-second performance
  target and is not reported as closed.
- The deterministic stalled-frame gate restarted only decoder generation 1 to
  2 in the same PID. Audio reloads stayed 0, media loads stayed 1, the current
  texture was retained and recovered source cadence was `33.09 fps`.
- Exact seek did not recreate the decoder; 2x hold and 1x restoration did not
  reload media. Two-part auto-next withdrew the first part's old texture
  before publishing part two. The physical quality picker kept all five ids
  `116,80,64,32,16` across 1080P -> 720P -> 1080P and retained position.
- A 4K request safely used the verified 1920x1080/60 representation for 60
  seconds with 63 windows and minimum `54.455 fps`; 8K used the same guard.
  Neither attempted an unsafe UHD OMX allocation or software fallback.
- During a real Home swipe Wi-Fi was disabled and restored. All 12 subsequent
  physical swipes succeeded in the same PID, contentY reached 6398 and request
  failures stayed 0. A separate 64-attempt recovery gate produced no offline
  request storm and completed a fresh request in the same process.
- Final production state is one PID (`18497` at cleanup), no
  `SILISILI_NATIVE_TEST_*` environment variables, Cover background mode,
  connected Wi-Fi, normal blanking policy and clean `rpm -V`.

## Historical 1.26 live hardware timeline and non-seekable fallback

- The captured 1.25 failure resolved a real FLV live source and started audio,
  but its first video PTS was tens of thousands of seconds from zero. The
  hardware packet limiter compared that raw timestamp with libmpv's zero-based
  live clock, held every video packet, expired the first-frame watchdog, and
  produced no shared texture.
- Hardware live playback now anchors the first real container timestamp to
  libmpv's current clock. Initial entry maps it to zero; a same-source decoder
  restart maps it to the retained audio position without attempting an FLV
  seek.
- If hardware still fails, live software fallback restarts at the stream head
  instead of applying an impossible non-zero initial-position gate to a
  non-seekable source.
- `SILISILI_NATIVE_TEST_PAGE=live-player` plus
  `SILISILI_NATIVE_TEST_ROOM_ID` opens a current room directly. Optional
  `SILISILI_NATIVE_TEST_CONTENT_MODE=quality-cycle` changes to one different
  advertised quality and requires another real frame on the same player.

## 1.25 initial-position startup synchronization

All checks used libmpv position, droidmedia texture, load-serial, playback,
process and package markers. No screenshot interpretation or visual model was
used.

- The previous path started libmpv audio at time zero, then issued an
  `absolute+exact` seek only after `FILE_LOADED`. On a real 14-second history
  resume, droidmedia had decoded the target window but presentation stayed
  gated; the 3500 ms first-frame watchdog then incorrectly forced a second
  software media load. The first visible frame arrived about 7.5 seconds after
  the original media load while audio had already been running.
- A non-zero initial position is now carried by the per-file `start` option
  with playback paused. A stale `time-pos` from the replaced source cannot
  satisfy the gate. Older libmpv builds retain a bounded exact-seek fallback,
  but audio remains held throughout that compatibility path.
- The gate now requires two independent conditions before audio is released:
  the new file has confirmed the requested position, and a real
  application-owned video texture is ready. The first frame is therefore
  reported at the requested 14-second position instead of after audio has
  advanced. A successfully decoded hardware texture also cancels the codec
  watchdog even if publication is still waiting for clock alignment.
- Three consecutive history-resume launches each used one media load, logged
  `audio_before_target=0`, retained the hardware route and produced no
  first-frame timeout or software fallback. Media-command-to-first-frame times
  were `2147`, `1955` and `2350 ms`; request-to-first-frame maximum was
  `2816 ms`.
- The deterministic mid-play stall gate still recovered generation 1 to 2 in
  the same PID with audio reloads at 0, media loads at 1 and the existing
  texture retained. Post-recovery unique source cadence measured `32.52 fps`
  for the 30 FPS test representation.
- The follow-up 1080P60/UHD gate held 63 stable one-second windows for 60
  seconds with a minimum `56.436 fps`, accepted physical pause/resume, kept
  queue pressure at zero, and safely resolved both 4K and 8K requests to the
  verified 1920x1080 representation. The final package passed `rpm -V` and the
  production launcher was restored.
- Final RPM SHA-256:
  `7bdd5a32007d2e2b959e92e868979bf4e74ceaf7b891543b63991577819e0337`.

## Historical 1.24 mid-play hardware-frame stall recovery

All checks used deterministic decoder-frame suppression plus resolver, audio
clock, decoder generation, shared-texture serial, process, memory and package
markers. No screenshot interpretation or visual model was used.

- The droidmedia frame callback no longer waits for display-queue space on its
  Binder delivery thread. Backpressure now runs on the private demux thread.
  An eight-credit bootstrap window satisfies H.264/HEVC reference-frame
  reordering after load or seek; after the requested target is decoded, normal
  video uses a matching eight-frame sliding window and UHD narrows to its
  one-frame CMA-safe waiting limit. The validated 30 FPS run logged zero
  callback frame drops.
- A 500 ms progress monitor is active only during genuinely running hardware
  playback. If the shared-texture serial is unchanged for at least 3 seconds
  while the separate audio/playback position advances by at least 1 second,
  it restarts only the same-quality droidmedia video decoder at the retained
  audio-clock position. It does not reload libmpv audio, change the media-load
  serial, withdraw the current texture or manipulate the quality selection.
- The deterministic gate suppressed generation 1 after frame serial 60. The
  watchdog detected the stall, restarted generation 2 in the same PID, kept
  audio reloads at 0 and media loads at 1, retained the visible texture, and
  resumed source frames at `30.09 fps` for the real 30 FPS representation.
  Free CMA was `66488 KiB`; the exact installed RPM passed `rpm -V`.
- The follow-up 1080P60/UHD safety gate accepted physical pause/resume, then
  held 63 stable one-second windows for 60 seconds with a minimum
  `55.944 fps`. Frame indices advanced in every sample, callback drops and
  queue pressure remained zero, and CMA stayed above the `32768 KiB` guard.
  Requests for 4K and 8K still selected the verified 1920x1080/60 hardware
  representation without attempting an unsafe UHD OMX allocation.
- Android's gbinder workaround diagnostic can still be emitted by this device,
  but the callback no longer blocks on the application queue and neither
  validated run stopped video progression.
- Final RPM SHA-256:
  `7c8cf3bf3ba0df5b45388a467add9689f50345bcc25f90413eb56fb4689de5a6`.

## Historical 1.23 UHD loading, controls and input pacing

All checks used resolver, decoder, playback-session, physical touchscreen,
memory, frame-window and package markers. No screenshot interpretation or
visual model was used.

- A direct hardware decoder that missed its first-frame deadline could restart
  the same source through the software path with a newer media-load serial.
  The playback session previously kept waiting for the older serial even while
  new video frames were being presented, leaving the loading spinner active
  and disabling the transport controls. The session now adopts a newer serial
  only within the same active load and continues to reject genuinely stale
  frames from older videos.
- The droidmedia packet feeder now limits compressed video to 1500 ms ahead of
  libmpv's master clock and discards packets from an obsolete seek serial.
  FFmpeg can no longer enqueue an entire long DASH representation into the
  asynchronous OMX adaptation and exhaust device memory or CMA while the user
  waits at a spinner.
- The 4K request (`qn=120`) for `BV1P4ddBBEJF` safely selected quality 116 at
  1920x1080/60 on this device. It resumed from the recorded `14s` history
  position, cleared loading, and accepted physical touchscreen pause and resume
  without changing the process.
- The final 60-second run collected 63 qualifying display windows with a
  minimum `55.281 fps`. Queue pressure remained zero, CMA stayed above the
  32768 KiB guard, no unverified UHD OMX allocation or UHD software fallback
  occurred, and the 8K request (`qn=127`) obeyed the same safe ceiling.
- The exact installed RPM passed `rpm -V`; its final SHA-256 is
  `8b7106a175da121a38bd4fd02e74f3dbcb34be47a05cd4b00c84cd118d05597b`.

## Historical 1.22 UHD safety and continuous playback

All checks used resolver, decoder, process, memory, frame-window and package
markers. No screenshot interpretation or visual model was used.

- The complete server-advertised quality catalog remains visible, including
  4K and 8K. Because droidmedia capability enumeration alone did not prove
  that this adaptation could allocate and present UHD OMX buffers, the default
  operational ceiling for an unverified device is quality 116 (real
  1920x1080/60). Explicitly verified devices can opt into the guarded UHD
  first-frame path with `SILISILI_NATIVE_ALLOW_UNVERIFIED_ULTRAHD=1`.
- The 4K request (`qn=120`) and 8K request (`qn=127`) for
  `BV1P4ddBBEJF` both selected quality 116 at 1920x1080. Neither test attempted
  an UHD OMX allocation or phone-side UHD software decode.
- The 4K-request regression held playback for 60 seconds, collected 63
  qualifying frame windows and measured a minimum `46.766 fps`, above the
  required 45 fps floor. Frame indices advanced throughout, frame-queue
  pressure remained zero, and free CMA stayed above the 32768 KiB guard.
- The subsequent 8K-request guard held the same safe representation for 20
  seconds with advancing frames. The production launcher then started
  normally; the package stayed installed and `rpm -V` was clean.

## Historical 1.22 physical Wi-Fi disconnect recovery

All checks used physical touchscreen input plus request/model, process, package
and QML markers. The exact user sequence disabled Wi-Fi during an in-flight
home-page swipe, restored it during cleanup, and did not use a visual model.

- Every bounded `QNetworkReply` now observes Qt's online state, the owning
  manager's accessibility and the default bearer identity. A transition to
  offline or a different bearer marks and aborts the obsolete reply instead of
  waiting for its 7–12 second hard timeout.
- Home, live, dynamic and inbox refresh/category operations cancel their active
  reply. Generation guards ignore a late response, preventing stale rows or an
  old error from overwriting the new page state. Danmaku requests use the same
  central timeout and connectivity lifecycle instead of a separate raw timer.
- Home pagination now publishes the failure/error gate before
  `loadingChanged(false)`. The list-end observers therefore cannot re-enter
  `loadMore()` and start an unbounded offline request loop while the user keeps
  scrolling.
- With Wi-Fi disabled in the middle of a real swipe, the application retained
  the same PID. All 12 subsequent physical swipes were accepted, the UI
  emitted a scroll-end marker, `contentY` advanced to 6403, and no request
  failures accumulated. Wi-Fi was restored before the gate exited.
- The deterministic follow-up injected a connection transition into the first
  home request, then exercised 64 continued-scroll load attempts. It observed
  no offline request storm, refreshed successfully in the same PID after three
  recovery polls, and started the ordinary production launcher without test
  variables.
- Production PID `22653` loaded the recommended home feed, remained alive with
  the same start time, passed the QML/crash marker scan, and left
  `rpm -V silisili-native-devel` clean. The final AArch64 RPM digest is
  `387f1716a243c50a2bfece0576725934e9acee2061875bf482f29a82e49d3d4c`.

## Latest 1.16 complete quality catalog and exact media selection

All checks below used physical touchscreen events plus application, resolver,
decoder and package markers. No screenshot interpretation or visual model was
used.

- `PlaybackResolver` now separates discovery from playback. One asynchronous
  `qn=127` request reads only the account/content-entitled
  `accept_quality`/description catalog; its media URLs are never published.
  The media request uses the exact selected `qn`, so a menu row cannot silently
  play a higher or lower representation.
- The tested VOD advertised five real profiles in descending order:
  `116,80,64,32,16` (`1080P60`, `1080P`, `720P`, `480P`, `360P`). The catalog
  is merged by content identity and survives later lower-qn responses, rather
  than replacing the menu with a truncated response.
- The in-player bottom sheet shows at most four rows and uses a clipped
  `SilicaListView` with bounded flicking and a scroll decorator. On the real
  2160×1080 landscape player, the five-row content was 750 units high inside a
  620-unit viewport. A physical swipe moved it from `contentY=0` to the bounded
  end at `contentY=130` and emitted both movement start/end markers.
- A single-process physical-touch regression started with exact DASH quality
  80 at 1920×1080, selected row 64 and resolved exact DASH quality 64 at
  1280×720, reopened the sheet with all five ids still present and selected 80
  again. The final marker was
  `native_quality_switch_116=ready`, with one PID/start time, retained playback
  position, zero hardware fallback, clean `rpm -V`, and
  `visual_model=unused`.
- The regression also caught and closed two false-success paths during
  development: the original capability request could label a quality-80 row
  while publishing quality 116, and the old 720P progressive path could return
  actual quality 16. Exact-qn DASH is now used for every advertised row;
  progressive media is retained only as the bounded compatibility fallback
  after a DASH request fails.

## Latest 1.10 direct Android OMX hardware decoding

The direct video architecture was adapted from
[`RootGPT-YouTube/RooTheater-SailfishOS`](https://github.com/RootGPT-YouTube/RooTheater-SailfishOS):
FFmpeg demuxes the video elementary stream, `droidmedia` selects an Android
codec with `DROID_MEDIA_CODEC_HW_ONLY`, and decoded gralloc buffers enter an
external-OES texture through `EGLImage`. SiliSili then samples that texture into
its application-owned double-buffered `GL_TEXTURE_2D` framebuffer, so the same
frame remains available to detail, full-screen, compact-player and Sailfish
Cover scene graphs without a CPU pixel copy. libmpv retains the separate DASH
audio stream and master playback clock.

All 1.10 checks below used package/process/decoder/texture/presentation markers;
no screenshot interpretation or visual model was used.

- The installed RPM passed `rpm -V`; its app-scoped minimedia compatibility
  unit was enabled and active, and the final service PID was `13816`.
- The device capability probe reported hardware support for 8/8 requested
  profiles: H.264 720p/1080p at 30/60, HEVC 1080p at 30/60, and VP9 1080p at
  30/60. The real VOD gate then created an Android OMX H.264 decoder with
  `HW_ONLY`, mapped `libdroidmedia` in the application, produced gralloc-backed
  shared textures with zero CPU pixel copies, and did not enter software
  fallback.
- The direct 1080p source averaged `28.3956` decoded frames/s, consistent with
  its real 30 FPS source cadence. A 16 ms presentation-only timer re-presents
  the current GPU texture at the 60 Hz Qt/Lipstick cadence without decoding or
  copying another source frame. The continuous 65-second gate measured 63
  one-second display windows, minimum `54.0806` FPS and zero windows below the
  required 45 FPS floor.
- EGL render fences retain gralloc buffers until the external-OES sample has
  completed. The validated run reported no fence backlog and no per-frame
  `glFinish`; a bounded emergency drain remains for EGL stacks with broken
  fence signaling.
- Hardware seek flushed the live OMX codec and repositioned FFmpeg in place.
  The shared-frame checkpoint advanced from 61 to 121 after the exact seek,
  with zero decoder recreation and zero media reload. Holding 2× and restoring
  1× speed both passed against the libmpv master clock.
- Cover used the same active texture and decoder. Inactive Cover presentation
  advanced from frame serial 82 to 112, preserved aspect ratio, and returned to
  the foreground without reload, hidden seek, decoder replacement or fallback.
- The deterministic two-part VOD gate performed exactly two loads and two OMX
  starts. Before P2 loaded, P1's non-zero shared-texture serial was withdrawn;
  P2 then published a hardware frame in the same application process and on the
  retained playback surface. This closes both automatic multi-P continuation
  and the stale-previous-frame regression for the direct hardware route.
- Capability, codec creation, asynchronous OMX failure, EGLImage/shader failure
  and fence failure all converge on the existing complete libmpv/FFmpeg
  software route at the current position. On this device, stopping the
  app-scoped minimedia unit did not create a valid negative-injection test
  because Android's codec service remained available and OMX continued to
  start; the final audit therefore does not misreport that experiment as a
  software-fallback device pass.
- Source engineering verification passed with CMake/qmake parity, 49 native
  source/header entries, 39 QRC resources, production desktop metadata and a
  clean `git diff --check` result.

## Latest 1.06 native-resolution, About and release-engineering validation

All checks used application/model/rendering markers and device process/package
state. No visual model or screenshot interpretation was used.

- The reported `高清 1080P` representation was verified as a real 1920×1080
  source. The old full-screen path first rendered it into an 800×450 shared
  framebuffer and then let Qt enlarge that intermediate texture, which was the
  direct cause of the visibly soft full-screen image.
- Full-screen now promotes the retained shared renderer to a centered,
  aspect-fitted 1920×1080 host only after orientation settles. The source,
  framebuffer texture and actual video viewport all reported 1920×1080; the
  inline detail, compact player and Cover stay on the bounded framebuffer and
  continue to share one decoder, source and playback clock.
- libmpv swap timing is fed from the real Qt/Lipstick window flip rather than
  the offscreen render. The inactive half of the double-buffered shared texture
  is submitted with `glFlush`, avoiding the old per-frame `glFinish` stall
  without publishing the framebuffer currently being written.
- On the final RPM, the short clarity gate reported one media load, no decoder
  reload and nine stable windows with no frame below 45 FPS. The independent
  64-second journal capture recorded 63 one-second display-swap windows,
  minimum 56.4356 FPS, zero windows below 45 FPS, zero media reloads, no QML or
  crash marker, and a clean `rpm -V` result.
- The About page now identifies `silisili-native-devel` version `1.1.0-1.06`,
  Sailfish OS `5.1.0.11`, `arm64`, Qt `5.6.3` and libmpv API `2.2`, and explains
  playback architecture, compatibility policy, package isolation, licensing
  and the project source link. Its direct device gate completed with no QML
  errors and a clean package verification.
- The PGC consistency regression switched between bangumi and cinema eight
  times. Each category performed one initial commit, all eight return cycles
  retained its original signature, empty-cursor pagination remained zero and
  rapid-switch stale replies were ignored.
- Release review now checks spec/CMake/qmake version agreement, all 47 active
  native source/header entries, all 39 QRC resources, the production desktop
  entry, and the deliberate exclusion of the failed system-level PiP path.
  The Sailfish 5.1 qmake configure gate also passed with the account-library,
  image-network and display-monitor sources plus GLESv2 present.
- The review additionally fixed region-category response races: a new category
  now cancels the previous request, clears mismatched rows immediately and
  rejects late replies by generation. Region and related-video requests now
  have bounded 12-second timeouts instead of leaving loading state unbounded.
- Final cleanup launched the installed application through its ordinary Home
  path with every `SILISILI_NATIVE_TEST_*` and forced-orientation variable
  absent. Account startup completed, the process stayed alive, the QML/runtime
  error scan was empty, and `rpm -V` remained clean.

## Latest 0.73 content, startup and long-playback validation

The final 0.73 aarch64 RPM was checksum-verified before installation. Both
`silisili-native-devel` and the retained stable package passed `rpm -V`. All
checks below used application/model/decoder markers and device state; no visual
model or screenshot interpretation was used.

- Account-library direct routes loaded History 20, Favorites 1,
  Subscriptions 14, Anime 20, Cinema 0 (valid empty account result), and Watch
  later 58. All six independent launches completed without request timeout or
  QML error. The blocking missing `../components` import and the early account
  session/user-id race were fixed.
- A non-video dynamic card opened `DynamicDetailPage` with four real images;
  the comment model did not open implicitly. Its first visible avatar loaded
  from the primary `i0.hdslb.com` candidate with retry index 0.
- UP-space profile data now comes from `/x/web-interface/card`: the old public
  profile endpoint returned `-401` on-device, while the replacement returned
  code 0 with both name and avatar. The final slow-scroll gate loaded 20 videos
  and 12 dynamics initially, then reached three video/dynamic pages and 36
  dynamics. The avatar loaded on the primary CDN and no QML undefined-field
  errors remained.
- The deterministic 1080P60 VOD resolved through WBI/DASH, used the Sailfish
  droidmedia hardware plugin, and reached its first decoded frame 8.652 seconds
  after direct page creation (6.381 seconds after the playback request). API
  resolution took about 0.29 seconds and proxy response headers about 0.27
  seconds; the remaining interval was hardware-decoder cold start.
- Inline, full-player and compact hosts retain the selected cover plus loading
  state until the first decoded frame, so cold hardware startup does not expose
  an old frame or black surface. Audio remains gated until that same frame.
- The forced-landscape compact player reported `907x510`, aspect 1.7778 and
  `landscapeWindow true`. A continuous 60-second hardware-frame gate recorded
  60 one-second windows, minimum 55.8276 fps, zero windows below 45 fps, no
  software fallback, no hidden seek, and no QML/runtime error.
- The local video proxy now closes only after upstream data and client socket
  buffers drain. Normal hardware playback no longer performs periodic hidden
  `QMediaPlayer::setPosition()` corrections, which previously could flush the
  decoded surface while audio continued.
- A fresh normal-orientation Cover round trip resumed at 60.6362 fps with the
  same PID/start time. Decoder-start, first-frame and DASH-resolve counts did
  not increase, and the post-foreground interval contained no reload, hidden
  seek or software fallback.

## Latest 0.72 responsive landscape and movable in-app player validation

Built and installed on the Pixel 3a XL through the Sailfish debug shell as
`outputs/silisili-native-devel-1.1.0-0.72.aarch64.rpm`. The final RPM is an
aarch64 package with installed payload size 28,981,648 bytes. Its digest, NEVRA
and RPM digests were checked before installation; both the development and
stable packages passed `rpm -V` after the tests.

Changes covered in this validation pass:

- Pages now report shared responsive metrics and follow device orientation in
  production. A development-only environment override and initial-page route
  allow deterministic real-device regression tests without changing the normal
  Home startup path.
- Navigation and account/library actions use two columns in landscape. Video
  and PGC detail pages use a landscape split with the player on the left and
  details on the right. Full VOD controls use a single compact action row in
  landscape; comment pages cap and center their readable width.
- The old fixed compact strip is replaced by a 16:9 application-internal
  floating player. It can be dragged in both axes, is clamped inside the app,
  remembers relative placement across geometry changes, and retains in-window
  pause, close and tap-to-return actions.
- Compact playback reuses the existing `PlaybackSession` and video output.
  Dragging does not activate the return action, while an ordinary tap restores
  the original detail page without issuing another playback request.

Non-visual real-device evidence:

- The direct Navigation route settled at `2160x1080`, reported `columns 2`,
  retained one process/start time and produced no QML/type/reference errors.
- The direct Video Detail route settled at `2160x1080`, reported `columns 2`,
  and divided the page into a 1382-pixel player region and a 778-pixel detail
  region. Both regions were non-zero and the process remained stable.
- The compact route resolved the test VOD to a 36-second duration and moved to
  an in-app Navigation page. Its floating player reported an initial
  `702x395` rectangle at `(358,1573)`.
- A real `/dev/input` touch swipe moved that same floating player to
  `(82,1149)`. The app remained topmost with the same PID and process start
  time, and no QML error was logged.
- A subsequent real touch at `(433,1346)` activated the floating player and
  restored the existing detail page. Playback-request count stayed 1 before
  and after activation, ruling out a reload-based return path.
- The test VOD first selected the Sailfish QtMultimedia/GStreamer device
  adaptation, then its first-frame timeout triggered the existing synchronized
  mpv software fallback. The responsive layout, application-internal surface
  ownership and drag/return checks passed across that fallback; no visual-frame
  claim is made by this semantic-only validation.
- The final clean launch omitted all test environment variables, reported
  orientation `device`, opened Home in portrait at `1080x2160`, remained the
  topmost process and left `silisili-sailfish-1.0.0-7.aarch64` unchanged.

No screenshot or visual model was used for the 0.72 validation.

## Latest 0.71 dynamics, author space, repost and typed-comment validation

Built and installed on the Pixel 3a XL through the Sailfish debug shell as
`outputs/silisili-native-devel-1.1.0-0.71.aarch64.rpm`. The RPM payload hash,
NEVRA and installed files were checked before and after installation; the stable
package remained `silisili-sailfish-1.0.0-7.aarch64`.

Changes covered in this validation pass:

- More content now exposes independent `视频动态` and `图文与转发` entries.
  The video route requests the video feed, while the non-video route advances
  through the all-dynamics cursor and filters out archive/video cards.
- A section-generation guard clears the previous model immediately and ignores
  late replies from the old section, preventing video cards from leaking into
  the non-video list after a fast route switch.
- Dynamic lists and author spaces use cursor/offset pagination plus several
  bounded near-bottom triggers. Loading therefore depends on list position and
  request state instead of swipe velocity.
- Author-space parsing now covers archive, draw/opus, article, PGC, common and
  forward cards. Reposts expose their original source text/media/images and
  engagement counts rather than appearing as empty cards.
- Dynamic cards carry the Bilibili comment resource type. Commentable non-video
  and author-space dynamic cards open typed comments from the whole card, with
  the small comment action retained as an additional target.

Non-visual real-device evidence:

- Video dynamics loaded from 20 to 40 items under deliberate slow scrolling.
- Switching sections produced
  `stale reply ignored section "video" generation 2 current 4`; the non-video
  model then loaded independently from 12 to 20 items. One intervening server
  page contained only video items (`added 0 shown 12`) and pagination correctly
  continued to the next cursor instead of treating that page as end-of-feed.
- Opening a non-video card loaded typed comments with resource type 11:
  20 comments shown from a 79-comment thread.
- The selected author space advanced its dynamics 12, 24, 36, 48 and 60 items
  using 1.1-second scroll gestures with a pause between gestures. An author
  dynamic opened its type-1 comment thread successfully.
- A separate authenticated author-space API sample contained 12 dynamics,
  including 7 reposts; all 7 reposts supplied original-source data and all 12
  cards supplied comment resources. The selected UI test author happened to
  have zero reposts in the sampled pages, so this API probe verifies availability
  of real repost source data without making a false visual claim.
- The final 0.71 process remained alive with the same start time, had no QML,
  type/reference, segmentation or `ANOM_ABEND` errors, and both development and
  stable packages passed `rpm -V`.

Search note: the authenticated fuzzy-search implementation was validated on the
same device before 0.71 and was not changed by the 0.71 dynamics work. Partial
query `SailfishOS` and typo query `SailfihOS` each returned 20 results; anonymous
requests returned HTTP 412, confirming that the native search request must keep
the account Cookie header. A fresh 0.71 UI-entry rerun was inconclusive because
the coordinate-only PulleyMenu automation did not reopen the search page; it did
not produce a search error or application crash, so it is not recorded as a
fresh 0.71 search pass.

## Latest 0.30 quality picker, Cover idle state and surface hand-off

Built and installed on the Pixel 3a XL through the Sailfish debug shell as
`outputs/silisili-native-devel-1.1.0-0.30.aarch64.rpm`.

- RPM SHA-256: `c2276402f2eaf27e2c73e736461a452a5beabb68093df4044656d4a7d013f7fd`
- Install gate passed with markers `__SILISILI_RPM_UPGRADE_PASS__` and `__SILISILI_INSTALL_PASS__`.
- Installed development package: `silisili-native-devel-1.1.0-0.30.aarch64`.
- Stable validation package retained: `silisili-sailfish-1.0.0-7.aarch64`.

Changes covered in this validation pass:

- VOD and live full-player quality selection now uses `QualityPickerPanel`, a bounded in-page bottom panel, instead of
  pushing `QualityDialog.qml` as a full page that covers the entire video.
- The Cover empty state now shows a small SiliSili card/status hint instead of a plain empty surface.
- `PlaybackSession::useHost()` now routes host changes through the shared mpv item's `claimSurface()` /
  `releaseSurface()` hand-off and requests a refresh after active host changes, reducing the repeated compact/fullscreen
  black-FBO failure mode.
- Test/deploy scripts were restored to the reliable Python debug-shell transport and a one-pass regression batch was
  added for install, Home pagination, playback, fullscreen, quality, and surface cycling checks.

Device validation:

- 0.30 launched through Sailjail with the existing native account session:
  `native account: loaded native session ... cookieCount 7` and `nav parsed loggedIn true`.
- Recommended Home loaded real content, then the one-pass batch scrolled the default recommendation feed through pages
  2, 3, 4 and 5: shown counts increased from 28 to 140. Visual evidence:
  [0.30 infinite recommendation feed](screenshots/5x-test/native-batch-02-home-infinite.png).
- Opening a recommendation resolved >720p DASH playback on device:
  `native player: DASH source resolved, quality 116 label "高清 1080P60" video 1920 x 1080 ... choices 5`.
  The same batch loaded danmaku (`items 96`) and the comments page model loaded 20 visible comments from a 441-comment
  thread.
- The batch completed with marker `__SILISILI_NATIVE_BATCH_PASS__`. Its coordinate-only fullscreen quality screenshot
  was later found to have tapped the comment publisher instead of the quality control, so that screenshot is not used as
  evidence for the picker.
- A focused quality-picker test then entered real fullscreen landscape playback and opened the new bounded picker with
  the video still visible behind it. Visual evidence:
  [0.30 fullscreen controls](screenshots/5x-test/native-quality-05-landscape-controls.png) and
  [0.30 bounded quality picker](screenshots/5x-test/native-quality-09-panel-tap-245-850.png).
- Fullscreen orientation followed the 16:9 video into landscape during the focused test. The player frame remained
  visible after entering fullscreen and after the quality panel was opened.

Testing notes:

- On this device, landscape screenshots are 1920x1080 while the direct-touch coordinates may still be reported in the
  portrait 1080x1920 coordinate space. The validated quality button tap used the converted coordinate `245,850`.
- The Sailfish screenshot affordance can temporarily bring the screenshot preview/editor to the foreground; focused
  tests should avoid taking an intermediate screenshot before subsequent touch actions.

## Latest 0.25 launcher, comments preview, VOD hold speed and live back swipe

Built and installed on `2026-08-04` as `outputs/silisili-native-devel-1.1.0-0.25.aarch64.rpm`.

- RPM SHA-256: `9a15d2592f3e3177379cd52da3afff4bfbe4c5958fb15b6bc321432568d1fed1`
- Install gate passed with marker `__SILISILI_INSTALL_PASS__`.
- Installed development package: `silisili-native-devel-1.1.0-0.25.aarch64`.
- Stable validation package retained: `silisili-sailfish-1.0.0-7.aarch64`.

Changes covered in this validation pass:

- Desktop launcher name is `SiliSili`; the installed desktop file still uses the native development app id
  `cn.silisili.native.desktop`, keeping it distinct from the stable package.
- The launcher icon was regenerated from `/Users/zerox/Downloads/ICON2高清改222.png` as an 86x86 RGBA Sailfish icon
  and installed as `/usr/share/icons/hicolor/86x86/apps/silisili-native-devel.png`.
- Home title now uses `SiliSili` consistently.
- Video detail comment preview now shows up to seven loaded main comments and labels the area as a preview with a
  clear "view all" path, instead of implying that only three comments exist.
- VOD player gestures now support press-and-hold 2x speed in the video area and restore 1x on release.
- Live player keeps brightness/volume/tap controls but disables horizontal seek handling; live streams are still
  returned from by a left-edge swipe/back gesture instead of trying to scrub a non-DVR timeline.

Device validation:

- Clean Sailjail launch loaded the existing native account session from
  `/home/defaultuser/.config/cn.silisili.native/account_session.json` and parsed the account nav response as logged in
  without printing cookie values.
- Recommended Home feed loaded 28 real items after launch.
- Home screenshot after 0.25 install: [0.25 Home](screenshots/5x-test/native-0.25-home.png).
- Opening a recommended VOD resolved `高清 1080P+`, created one persistent mpv instance, loaded a 1920x1080 stream and
  loaded the first comments page with seven shown items in the model.
- Press-and-hold speed test passed with log sequence: `native player: speed 2`,
  `native gesture: speed hold 2.0`, `native player: speed 1`, `native gesture: speed restored`.
- Live list opened from the Home `直播` tile and a real live room loaded through the native live player:
  `native live: source resolved, quality 250 choices 2`, `native player: video geometry 1280 x 720 aspect 1.77778`.
  Visual evidence: [0.25 live player](screenshots/5x-test/native-0.25-live-player-direct.png).
- A horizontal/edge swipe from the live player returned to the live room list, releasing the live host and stopping the
  stream without any `native gesture: seek` log. Visual evidence:
  [0.25 after live swipe back](screenshots/5x-test/native-0.25-after-live-swipe-back.png).

## Latest 0.24 launcher and playback gesture base

Built and installed on `2026-08-04` as `outputs/silisili-native-devel-1.1.0-0.24.aarch64.rpm`.

- RPM SHA-256: `9b3240dd2b6919a06118c62c68f508f334c87b9606d871e133d6dcbf48b252ae`
- Install gate passed with marker `__SILISILI_INSTALL_PASS__`.
- Installed development package: `silisili-native-devel-1.1.0-0.24.aarch64`.
- Stable validation package retained: `silisili-sailfish-1.0.0-7.aarch64`.

0.24 introduced the native mpv speed bridge, the shared `PlayerGestureArea` long-press scaffolding, `SwipeBackArea`
for full VOD/live player pages, live `seekEnabled: false`, the refreshed launcher icon crop, and the shorter launcher
name. 0.25 supersedes it with the in-app title/comment-preview cleanup and the device gesture validation above.

## Latest 0.23 login persistence and Sailjail migration

Built and installed on `2026-08-04` as `outputs/silisili-native-devel-1.1.0-0.23.aarch64.rpm`.

- RPM SHA-256: `49fdbde60f3e505ee265af3860c9eba4ea6da54735e706fa7237c9d0bc534065`
- Install gate passed with marker `__SILISILI_INSTALL_PASS__`.
- Installed development package: `silisili-native-devel-1.1.0-0.23.aarch64`.
- Stable validation package retained: `silisili-sailfish-1.0.0-7.aarch64`.

The login persistence failure had two related causes:

- QR/native sessions must be stored under Sailjail's whitelisted private config directory,
  `/home/defaultuser/.config/cn.silisili.native`, not the earlier development path
  `/home/defaultuser/.config/silisili-native`.
- The stable app's original config under `/home/defaultuser/.config/silisili/silisili_config.json` is not visible to
  the app process after Sailjail starts, so the RPM now seeds a private `stable_config_snapshot.json` into
  `/home/defaultuser/.config/cn.silisili.native` during `%post` when no native session already exists.

Device validation avoided printing cookie values. The seeded snapshot contained exactly one each of the expected
cookie keys (`SESSDATA`, `bili_jct`, `DedeUserID`). On first launch after seeding, the app wrote
`/home/defaultuser/.config/cn.silisili.native/account_session.json`, size `503` bytes, with the same key counts.
A second clean Sailjail launch then loaded the native session directly and completed the account status request:

- log marker: `native account: loaded native session from "/home/defaultuser/.config/cn.silisili.native/account_session.json" cookieCount 7`
- log marker: `native account: nav parsed loggedIn true cookieCount 7`

This closes the "does not keep login information" regression for the current 5.1 test device. If the stable cookie
itself expires, the native app will still need QR login again, but the new QR session is saved in the whitelisted
native directory and should survive launcher/Cover/restart cycles.

## Built 0.21 high-quality playback attempt, pending device install

Built on `2026-08-04` as `outputs/silisili-native-devel-1.1.0-0.21.aarch64.rpm`.

- RPM SHA-256: `5cb6c37841ad33f52b9a7a70c8e08cfd41ca14ec0b05e7860d686b4b0e228657`
- Release purpose: prefer 1080P60 (`qn=116`) VOD/PGC requests, enable DASH/fourk playurl parameters, pass the DASH
  audio track to mpv, and automatically fall back to the old 720P progressive path when the account or selected video
  does not expose an actual >720P DASH video stream.

Local API probing without a valid logged-in account showed why the fallback is required: a public test video reported
1080P/1080P60 in `accept_quality`, but the actual DASH video list only exposed 480P/360P tracks; the old progressive
request still returned 720P. Therefore 0.21 intentionally treats "no actual >720P DASH track" as a fallback condition
instead of playing a lower-resolution DASH stream.

Device install was not completed in this record because the Pixel debug endpoint became unreachable from the VM
(`192.168.2.15` stopped responding to ping/telnet). The VM-hosted RPM service at `10.211.55.7:18087` was reachable
from the device before the disconnect, and a manual phone-side download test verified the 0.21 SHA-256. Install and
playback-log validation should resume after the debug connection is restored.

## Latest 0.20 live crash and stale-lock recovery

Built and installed through the Sailfish SDK/phone path. `rpm -V silisili-native-devel` passed after install, the
installed development package was `silisili-native-devel-1.1.0-0.20.aarch64`, and the stable validation package
remained installed as `silisili-sailfish-1.0.0-7.aarch64`.

This package fixes the live-entry crash class reported after opening live playback:

- the live player no longer creates and destroys a page-local mpv/QQuickFramebufferObject instance;
- live playback reuses the process-lifetime `playbackVideo` item, stops any VOD `PlaybackSession` first, and claims a
  direct live host surface;
- stale live play-url network replies are ignored through latest-wins request serials;
- `PlaybackSession::stop()` now clears pending surface-release/foreground-refresh timers and host references before
  live claims the global video item;
- the process single-instance `QLockFile` now uses stale-lock recovery instead of treating every leftover lock as a
  permanent "already running" state.

Device validation performed on the 5.1 Pixel 3a XL:

- Sailjail launch succeeded, the default recommended feed parsed 30 real items, and the application stayed in the
  foreground.
- Home → Live opened the real live list once during manual coordinate testing:
  [0.20 live feed](screenshots/5x-test/0.20-live-feed.png).
- A deliberate SIGKILL left `/tmp/silisili-native-defaultuser.lock` in place. Starting again without deleting the lock
  succeeded: first PID `48656`, relaunched PID `48799`, topmost PID `(48799,)`, with marker
  `__SILISILI_STALE_LOCK_PASS__`.

The automated touch coordinates for entering a specific live room were not reliable after the Home/navigation layout
changes, so this record does not claim a fresh 0.20 live-room playback screenshot. Manual follow-up should still
recheck room entry, playback frame, quality dialog, and back/foreground transitions, but the crash-after-live
single-instance lock failure is closed by the forced-stale-lock test.

## Latest 0.19 portrait full-player control layout

Built and installed through the same Sailfish SDK/phone path as the previous packages. The RPM checksum was verified
before install, `rpm -V silisili-native-devel` passed after install, and the stable validation package remained
installed as `silisili-sailfish-1.0.0-7.aarch64`.

This package refines the 0.18 full-player control reflow for narrow portrait layouts: the portrait-only branch now
keeps the seek slider on a native-margin row, groups seek backward/seek forward/orientation controls on an icon row,
puts the quality `ValueButton` on its own full-width row, and groups danmaku toggle/settings into a final two-button
row. This avoids making the quality label and danmaku toggle compete for one half-width row in portrait fullscreen.

Device smoke validation after installing 0.19:

- Sailjail launch succeeded and the default recommended feed parsed 30 real items.
- Opening the first recommendation started real VOD playback with one persistent mpv instance.
- Playback resolved quality 64, loaded a 1280×720 stream, and loaded danmaku segments for CID `40485454388`
  (`561`, then `473`, then `363` items in the captured log tail).

Visual evidence for this smoke pass: [0.19 detail playback before full-player entry](screenshots/5x-test/0.19-fullscreen-controls-fast-rightbottom.png).
The automated coordinate path did not reliably hit the hidden inline fullscreen button before the inline controls
auto-hide, so this record does not claim a fresh 0.19 full-player screenshot. The immediately preceding 0.18 package
did capture the full-player control surface after entering fullscreen:
[0.18 full-player controls](screenshots/5x-test/0.18-portrait-fullscreen-controls-2.png). A manual 0.19 fullscreen
capture is still the next verification step for the portrait-only branch.

## Latest 0.17 compact-player return target

Validated through the Sailjail app path after installing the checksum-verified RPM. A VOD detail page started real
inline playback, the "all comments" page moved the shared playback surface into the in-app compact player, and tapping
the compact player returned to the original video detail page instead of opening the full-page player.

The log showed the surface moving from the compact host back to the inline detail host:

- compact host: `foreground surface refresh reload false host 295.111 x 166`
- restored inline host: `foreground surface refresh reload false host 1080 x 607.5`

Visual evidence: [comments page with compact player](screenshots/5x-test/0.17-after-comment-tap-second.png) and
[compact tap restored the detail page](screenshots/5x-test/0.17-compact-tap-restores-detail.png). The restored capture
is at video EOF (`9:29 / 9:29`), so the black video area is the ended inline-player state, not a full-page navigation.

## Latest 0.16 home navigation cleanup

Validated through the Sailjail app path after installing the checksum-verified RPM. The Home page no longer shows the
duplicated in-page "More functions" menu; secondary navigation remains available from the native pull-down "More
content" item. The default recommended feed still loaded real content: `home feed parsed "recommended" 30 items`.

Visual evidence: [0.16 Home without duplicated inline More menu](screenshots/5x-test/0.16-home-no-inline-more.png).

## Latest 0.15 foreground-restore black-screen fix

Validated through the Sailjail app path on the Pixel 3a XL test device after the 0.14 lightweight nudge still resumed
with a black video surface during manual testing. The 0.15 package restores the reliable foreground recovery path:
foreground activation first refreshes the QML/Wayland video surface, then a delayed refresh reloads the current mpv
source at the preserved playback position and pause state.

The foreground/Cover round trip kept the same application PID and one process:

- foreground PID before restore: `65132`
- foreground PID after restore: `65132`
- process count after restore: `1`
- log markers: `foreground surface refresh reload false`, `foreground surface refresh reload true`,
  `foreground video reload requested at 127.136 paused false`, then `load command submitted serial 2` and `file loaded`

The restored inline player showed a live decoded video frame instead of the audio-only black surface:
[before Cover restore](screenshots/5x-test/0.15-video-before-bg.png) and
[after Cover restore](screenshots/5x-test/0.15-video-after-bg-restore.png). This path intentionally preserves the
small foreground-resume pause caused by reloading the current source; it is currently preferred over the smoother 0.14
nudge because it avoids the black-screen regression on device.

## Latest 0.14 foreground-restore smoothing

Validated through the Sailjail app path. The 0.13 black-screen fix was smoothed in 0.14: foreground restore now does
a surface refresh followed by a lightweight current-position mpv nudge instead of reloading the network source.

Manual follow-up testing found that this lighter path can still return from Cover/background with an audio-only black
video surface on the device. 0.14 is therefore retained as a failed smoothing experiment, not the current recommended
package.

The foreground/Cover round trip kept the same application PID and one process:

- foreground PID before restore: `49809`
- foreground PID after restore: `49809`
- process count after restore: `1`
- log markers: `foreground surface refresh nudge false`, `foreground surface refresh nudge true`,
  `foreground video nudge requested at 178.013 paused false`
- no second load was submitted after restore; the log stayed at `load command submitted serial 1`

The restored inline player continued showing video content/progress without reverting to the prior audio-only black
surface: [0.14 after Cover restore](screenshots/5x-test/0.14-video-after-bg-restore.png). The captured frame is a
black-background text/title segment from the current video, not the earlier blank render-surface failure.

## 0.13 foreground-restore regression

Validated through the Sailjail app path (`/usr/bin/sailjail -p cn.silisili.native -- /usr/bin/silisili-native`), not a
bare debug-only launch. The recommended feed loaded real content, a VOD detail page opened from the default
recommendation list, mpv created one persistent client instance, and the inline player reached a real decoded frame:
[before Cover restore](screenshots/5x-test/0.13-video-before-bg.png).

The foreground/Cover round trip kept the same application PID and one process:

- foreground PID before restore: `32765`
- foreground PID after restore: `32765`
- process count after restore: `1`
- log markers: `foreground surface refresh`, `foreground video refresh requested`,
  `foreground video reload requested at 581.158 paused false`, then `load command submitted serial 2` and `file loaded`

The restored inline player showed live video instead of a black frame, with the passive progress line aligned from the
left edge of the player: [after Cover restore](screenshots/5x-test/0.13-video-after-bg-restore.png). Fullscreen entry
also showed the seek slider centered after reducing the reserved back-swipe corridor:
[fullscreen progress layout](screenshots/5x-test/0.13-fullscreen-progress.png). That fullscreen capture is at EOF
(`15:16 / 15:16`), so the black video area there is the ended state, not the foreground-restore black-screen bug.

Final installed development package in this record:

- NEVRA: `silisili-native-devel-1.1.0-0.7.aarch64`
- RPM SHA-256: `a97c1b3cdcdf5d28fb5766d4e0e60c8cccdb006724713a0abb36c2bc3bc1573a`
- RPM build time: `1785699348` (`2026-08-03 03:35:48 +0800`)
- the clean full-build RPM, HTTP-served payload and exact downloaded phone payload had the same SHA-256
- `rpm -V silisili-native-devel` completed cleanly
- stable package retained: `silisili-sailfish-1.0.0-7.aarch64`
- stable configuration SHA-256 before/after native launches:
  `06cfd2fed5f36d558b98e1de43b598cc59f64b0098bf125e726dee97313bdb97`

The previous checksum-closed 0.6 package and its screenshots remain below as historical regression evidence. The
new inline/fullscreen/PGC/live closure screenshots cited in their final-package rows were captured after installing
the checksum-closed 0.7 RPM; earlier 0.7 Home, comment and Cover images remain explicitly identified as staged evidence.

## Verified gates

| Gate | Evidence |
|---|---|
| Package identity and coexistence | Mac/HTTP/phone SHA-256 matched `a97c1b3c…1573a`; exact 0.7 NEVRA and `rpm -V` passed, while stable `silisili-sailfish-1.0.0-7.aarch64` and its configuration checksum remained unchanged |
| Application single instance | Final 0.7 deliberate second launch passed the `QLockFile` gate: one exact application process, start time and shared VOD backend remained |
| Default recommendation feed and direct navigation | The 0.5 launch log parsed 28 real recommended items. Staged 0.7 retained recommendation as the selected default in a compact four-item row for live, recommended, popular and PGC content: [home with real recommendation content](screenshots/5x-test/native-home-final-0.7.png). Secondary search, region, dynamic, messages and account actions open from a native `ContextMenu`: [menu](screenshots/5x-test/native-home-more-menu-final-0.7.png), [search](screenshots/5x-test/native-home-more-search-final-0.7.png), [region](screenshots/5x-test/native-home-more-region-final-0.7.png) |
| Fixed inline video while detail content scrolls | The final package kept the live VOD frame fixed while metadata/comments remained independently scrollable: [passive inline playback](screenshots/5x-test/native-inline-passive-final-0.7.png). Earlier ordinary and PGC fixed-player evidence remains available in [ordinary detail](screenshots/5x-test/native-video-sticky-player.png) and [PGC detail](screenshots/5x-test/native-pgc-sticky-player.png) |
| Inline progress, controls and gestures | Final 0.7 shows the thin passive progress line with controls hidden and the native `Slider`/fullscreen control when shown: [passive state](screenshots/5x-test/native-inline-passive-final-0.7.png), [controls](screenshots/5x-test/native-inline-controls-final-0.7.png). Horizontal seek, left-side brightness and right-side volume all passed on the final VOD |
| Comment preview and complete entry | Staged 0.7 deliberately limits the detail preview to three main comments while showing the full total and reply links: [three-row preview and all-comments entry](screenshots/5x-test/native-comments-preview-all-entry-final-0.7.png). The dedicated page still exposes the complete list: [all-comments page](screenshots/5x-test/native-all-comments-final-0.7.png). The earlier verified page contained 21 main comments of 9549 total with complete reply links |
| Comment cursor pagination | [continued comment list](screenshots/5x-test/native-pgc-comments-paginated.png); device log: page 0 added 21, page 2 added 20, page 3 added 19, shown 60, total 9549 |
| Complete reply thread | [native reply-thread page](screenshots/5x-test/native-comment-reply-thread.png) |
| Full-page shared playback | [full player at 2:37/6:59 and 720P](screenshots/5x-test/native-fullscreen-danmaku.png) |
| Aspect-aware fullscreen and transient controls | Final 0.7 resolved a 16:9 VOD to the 2160×1080 landscape page, continued real playback and hid controls automatically: [playing with controls hidden](screenshots/5x-test/native-fullscreen-playing-controls-hidden-final-0.7.png). The reserved PageStack corridor returned to the portrait detail page: [portrait return](screenshots/5x-test/native-fullscreen-page-return-final-0.7.png). Earlier 0.5 and dense-danmaku captures remain historical rotation evidence |
| Fullscreen state preservation | [0.5 paused fullscreen at the preserved 4:52 position](screenshots/5x-test/native-fullscreen-paused-state-preserved-0.5b.png); renderer-recreation log twice recorded `load command submitted at 292.233 paused true`, then playback resumed from that point and controls hid normally |
| In-app compact playback | [home compact player with live frame and 213/419 progress](screenshots/5x-test/native-in-app-compact.png) |
| System Cover playback control | Final 0.7 passed three foreground/Cover round trips with the same PID, process start time, shared VOD backend and media load count. The Cover remains deliberately static art/title/progress/quality with native pause/stop actions: [0.7 Cover](screenshots/5x-test/native-single-session-persistent-cover-1-0.7.png). The checksum-closed 0.6 advance/pause/resume/stop captures remain the historical long-form behavior proof |
| Native quality selection | Final 0.7 opened the quality Dialog inside the 2160×1080 full player; the Dialog stayed 2160×1080 landscape and displayed both 720P and 360P choices: [landscape quality Dialog](screenshots/5x-test/native-landscape-quality-final-0.7.png). Earlier device evidence retains the [portrait VOD quality Dialog](screenshots/5x-test/native-player-quality-dialog.png) and [360P result](screenshots/5x-test/native-player-quality-switched.png). The danmaku-settings Dialog shares the orientation-inheritance implementation but was not separately captured in this final gate |
| Player gestures | Final 0.7 passed horizontal seek, left-side brightness and right-side volume on inline VOD; PGC and live repeated all three gesture paths. Earlier numeric VOD logs recorded seek 34, brightness 44, volume 100 and volume 59 |
| Live feed | Final 0.7 loaded real live rooms: [live feed](screenshots/5x-test/native-live-feed-final-0.7.png) |
| Live playback | Final 0.7 played a real 1920×1080 stream and passed DVR seek, brightness and volume gestures: [live player](screenshots/5x-test/native-live-player-final-0.7.png) |
| Live quality selection | [native quality Dialog](screenshots/5x-test/native-live-quality-dialog.png) |
| PGC feed and detail | Final 0.7 loaded 12 real PGC feed items: [PGC feed](screenshots/5x-test/native-pgc-feed-final-0.7.png). Earlier season-detail evidence retains the complete episode entry |
| PGC inline playback and danmaku | Final 0.7 played a real PGC episode and passed seek, brightness and volume gestures: [PGC inline passive playback](screenshots/5x-test/native-pgc-inline-passive-final-0.7.png). Earlier device logs resolved quality 64 with two choices and loaded 2774 danmaku items |
| PGC full-page shared playback | [PGC episode in the common full-page player](screenshots/5x-test/native-pgc-fullscreen.png); the same session retained 720P, progress and timed danmaku and loaded 621 items for the captured episode |
| Mixed dynamic feed | [repost video and nine-image native cards](screenshots/5x-test/native-dynamic-expanded.png) and [continued image cards](screenshots/5x-test/native-dynamic-paginated.png); device log appended 26 → 46 items through the offset cursor |
| Dynamic video hand-off | [video card opened in the fixed-player detail page](screenshots/5x-test/native-dynamic-video-detail.png) |
| Message categories | [native category selector](screenshots/5x-test/native-inbox-categories.png), [five real mention messages](screenshots/5x-test/native-inbox-mentions.png), and a valid empty state for the current account's like feed |
| Message cursor and detail | [reply cursor finished after 20 → 32 items](screenshots/5x-test/native-inbox-paginated.png) and [full native message detail](screenshots/5x-test/native-inbox-detail.png) |
| QR login presentation | [system-rendered login QR and polling state](screenshots/5x-test/native-qr-login.png) |
| Native account controls | [restored account with QR switch and logout controls](screenshots/5x-test/native-account-page.png) |
| Player swipe-back corridor | Final VOD returned from the 2160×1080 full player to portrait detail through the reserved PageStack corridor: [final return](screenshots/5x-test/native-fullscreen-page-return-final-0.7.png). Earlier live inset-swipe evidence is retained separately |
| System outer-edge minimize | [staged 0.7 system launcher after the physical outer-edge gesture](screenshots/5x-test/native-fullscreen-edge-return-0.7.png). This proves that the gesture minimized the application to the system launcher; it is not PageStack back-navigation evidence |
| Runtime and display policy | Final 0.7 runtime error scan was clean. Immediately after pausing inline VOD, `mcetool` reported `Display state: on`, `Display never blank: disabled` and `Blank inhibit: disabled`; an independent check 40 seconds later reported `Display state: off` with both policies still disabled. Paused playback therefore passed automatic display blanking on the final package. The timed 0.6 regression remains the recorded proof that active foreground playback stays on and that end-of-file also releases the inhibit |

## Final 0.7 implementation closure

- `main.cpp` holds a process-lifetime `QLockFile` before constructing the QML view. The deliberate second-launch gate
  passed with one exact process, start time and application-level VOD backend.
- VOD requests now use latest-wins arbitration: a new video, episode or quality request aborts the active reply and
  advances a request serial so a queued stale completion cannot publish an old URL. The implementation is included
  in the checksum-closed artifact; synthetic delayed-network races remain an optional hardening test.
- `PlaybackSession` now separates media-state `changed` notification from surface-only `surfaceChanged` notification.
  Surface claims therefore no longer synchronously invalidate the `wantsPlaybackSurface` binding that initiated the
  claim. Release remains delayed for 220 ms so an incoming full-player or returning detail host can claim the same
  item without an intermediate fallback reparent. Final fullscreen entry/return and three Cover cycles passed; the
  final runtime error scan found no binding-loop, ownership, VO-init, EGL or FBO failure.
- The VOD `PlaybackSession` is shared by inline detail, full-page playback, compact playback and Cover. The live page
  intentionally retains a separate `MpvVideoItem`; application single-instance, VOD backend single-instance and
  renderer attachment counts must not be conflated in validation output.
- The final package left both the global never-blank and blank-inhibit switches disabled after pausing inline VOD.
  `mcetool` reported the display on immediately after pause and off on an independent check 40 seconds later, so
  final 0.7 paused-playback automatic blanking passed. The earlier timed 0.6 foreground-playback and end-of-file
  results remain the corresponding evidence for those states; background Cover timing remains a future power test.

The comment-posting endpoint is implemented but was not invoked: validation must not create a public comment without
user-supplied content and explicit intent. QR generation/polling and private credential persistence are implemented;
the QR was not scanned and logout was not accepted, so no account credentials were changed during this validation.
The current live room exposed only one quality, so live quality state-preservation remains a code-path review rather
than a multi-quality device switch.
The message tests were read-only. The current account returned no entries from the like feed; this verifies the
category request and native empty state, but not rendering of a non-empty like item.

The checksum-closed 0.6 player core exposes actual `playing` and `ended` state from mpv events. Display blanking and
control auto-hide use `playing`, so pause, loading, errors, background/inactive pages and normal end-of-file all
release the display inhibit. When Qt recreates the renderer during inline/fullscreen/compact transitions, the current
confirmed or pending-seek position and the requested pause state are used instead of the original load values.

The checksum-closed 0.6 Cover record remains the historical advance/pause/resume proof. Final 0.7 instead keeps the
Cover static and preserves the shared VOD backend behind the application host; three repeated foreground/Cover cycles
kept the same PID, start time, backend and load count, and the final runtime error scan was clean.
