# Native Sailfish test/deploy tooling notes

Current device: Pixel 3a XL Sailfish OS 5.2.0.16 through the Sailfish debug shell at `192.168.2.15:2323`.
The USB interface name in the build VM is deliberately not fixed: it is generated from the
RNDIS MAC and can change after reconnecting the phone.

Important context boundary: the macOS workspace stores the source tree and the
RPM artifacts, but it is not the Sailfish SDK environment. Full native RPM
builds are run from the Linux/Sailfish build VM through the shared path
`/media/psf/AllFiles/Users/zerox/Documents/Codex/2026-07-31/silisili-native-sailfish`.
If `/opt/sailfish-hadk`, `sb2`, or `/media/psf/...` are missing from the
current shell, do not conclude that the project cannot build; switch to the VM
entrypoint below.

Use these transport rules for this project:

- Large files, especially RPMs, must be uploaded with
  `vm-deploy/scripts/send-phone-file-python.py`. It writes through the debug shell and verifies SHA-256 on the phone.
  Do not use a long phone-side `curl` download through `telnet-cmd.sh`; the command can be truncated before the RPM
  is complete.
- Multi-step device tests may be sent with `vm-deploy/scripts/run-phone-script.py` when bounded captured output and the
  final exit code are needed, or `vm-deploy/scripts/send-phone-script-python.py` when live remote output is useful.
  `run-phone-script.py` folds Base64 payloads to terminal-safe 76-character lines, paces the prefix/payload/suffix and
  can atomically retain evidence with `--output`. Avoid long inline `telnet-cmd.sh` snippets because command echo can
  look like success markers and the wrapper can return before the remote work actually reached its own sentinel.
- For UI-coordinate tests on rotated fullscreen video, remember that the screenshot may be landscape while
  `/tmp/bonito-direct-touch` can still behave like portrait coordinates. Convert or verify with a no-intermediate-
  screenshot touch script.
- `telnet-cmd.sh` is still fine for short, read-only probes and simple one-line actions.

Current native install path:

- Build from the Linux/Sailfish build VM:
  `cd /media/psf/AllFiles/Users/zerox/Documents/Codex/2026-07-31/silisili-native-sailfish/work && bash vm-build-native-rpm.sh`
  The script copies the macOS-shared source into `/home/builder`, uses
  `/opt/sailfish-hadk/platform/sdks/sfossdk/sdk-chroot`, the tested
  `SailfishOS-5.1.0.11-aarch64` target by default, and writes the final RPM
  back to the macOS-visible `outputs/` directory.
- Install from the same VM:
  `bash work/vm-install-native-phone.sh outputs/silisili-native-devel-VERSION-RELEASE.aarch64.rpm`.
  With no argument it installs the newest `outputs/silisili-native-devel-*.rpm`.
  The wrapper first runs `vm-setup-sailfish-debug.sh`, which discovers the
  `rndis_host` interface, brings it up and assigns the VM peer address, then
  delegates to `vm-deploy/scripts/install-silisili-native-fast.sh` for SHA-256,
  NEVRA and `rpm -V` verification. Set `PHONE_IP` and/or
  `SAILFISH_DEBUG_HOST_CIDR` only when the phone-side debug endpoint has
  intentionally changed.
- Launch: `work/vm-launch-native-sailjail.sh`
- One-pass regression smoke: `work/vm-test-native-regression-batch.sh`

For checksum-closed candidate work, use these bounded helpers:

- `probe-silisili-native-device-preflight.sh` records OS/package/process state,
  `rpm -V`, background mode and exact candidate bytes/SHA/NEVRA. Its local
  watchdog works on Sailfish images that do not provide GNU `timeout`.
- `relink-silisili-native-qml-candidate.sh` relinks QML/resource-only changes
  under SB2 and verifies that execution really entered the build target.
- `package-silisili-native-candidate.sh` packages the relinked tree and closes
  the final RPM identity before deployment.
- `probe-silisili-native-live-background-presentation.sh` chooses a currently
  active live room, exercises both Cover and system PiP, and asserts shared
  decoder/load, advancing frame serials, QML layout markers and clean recovery.
- `probe-silisili-native-vod-cover-layout.sh` uses a fixed VOD and accepts only
  a balanced Cover geometry plus advancing shared-texture frames after the
  verified background state. It avoids making layout acceptance depend on a
  randomly selected live source.
- `probe-silisili-native-system-controls.sh` is a read-only preflight for the
  system brightness/volume gesture path. It reports writable backlight
  candidates, the PulseAudio default sink and MCE display-related methods
  without changing device brightness or volume.
- `probe-silisili-native-system-controls-transaction.sh` performs a bounded
  backend write/read/restore check for Sailfish display brightness and
  PulseAudio media volume. Use it only when a temporary system-control change
  is acceptable.
- `probe-silisili-native-volume-gesture.sh` launches a real detail-page VOD,
  injects a physical right-side vertical gesture, requires the
  `pulse-stream-restore-x-maemo` route and verifies exact automatic volume
  restoration in the same process.
- `probe-silisili-native-compact-system-controls.sh` is the compact-player drag
  gate: a physical drag from the video-area center must move the floating
  geometry while leaving Sailfish brightness and `x-maemo` media volume
  unchanged. It also rejects any compact-player `native gesture:` marker.
- `probe-silisili-native-compact-cover-context.sh` starts a real detail-page
  VOD, moves it into the actual Home page's visible application mini-player,
  then backgrounds the app through a physical gesture. It requires the Cover
  to retain live playback content and all three actions with
  `eligiblePage=false|compactActive=true`, captures a fresh device screenshot,
  preserves one PID, and restores the user's original Cover/PiP preference.
- `probe-silisili-native-anonymous-default-quality.sh` launches the production
  player with an isolated credential-free `HOME`, so the account session files
  used by the real user are never touched. It requires the anonymous initial
  policy to request QN 64 (720P), one source load, a real `1280x720` selected
  video, one first-frame marker, an unchanged process start time, clean
  `rpm -V`, and no QML or hardware-fallback errors. When the anonymous DASH
  response exposes only QN 32/480P, the probe accepts only the bounded
  QN 64 progressive retry and reports `route=progressive-720p`.

  Run it through the Sailfish debug shell with a unique run id:

  ```sh
  python3 vm-deploy/scripts/run-phone-script.py \
    vm-deploy/scripts/probe-silisili-native-anonymous-default-quality.sh \
    anonymous-quality-$(date -u +%Y%m%dT%H%M%SZ)
  ```

  A successful run emits both `sailfish_test=ready` and
  `native_anonymous_default_quality=ready`; `logged_in=0`,
  `session_credentials=0`, `requested_qn=64`, `selected_qn=64`, and
  `production_account=untouched` are mandatory fields.
- `stop-silisili-native-app.sh` terminates the current `silisili-native`
  process so a just-installed RPM is not confused with an already-running old
  binary.
- `cleanup-silisili-native-device-test-state.sh` is the common bounded cleanup
  path for application/PiP/playback processes, background mode and blanking.
- `diagnose-silisili-native-launch-failure.sh` records loader, private runtime,
  process and journal evidence when a candidate does not launch.
- `restore-silisili-native-known-good.sh` reinstalls an exact checksum-closed
  fallback RPM and restores Cover mode when a candidate must be rolled back.

## Release-source verification

Before an RPM build or Git commit, run:

```sh
bash vm-deploy/scripts/verify-silisili-native-source.sh
```

The gate rejects spec/CMake/qmake version drift, missing or extra active native
sources, missing QRC resources, a test-enabled desktop entry, or accidentally
re-enabling the device-rejected system PiP implementation. It also keeps the
legacy qmake project aligned with the primary CMake build. For Sailfish 5.1,
configure the qmake project with `SILISILI_MPV_PREFIX` pointing at the validated
private libmpv runtime.

The 1.06 full-screen performance gate follows the device journal into a
dedicated file for at least 60 seconds. Do not compare two complete journal
snapshots: the deliberately small phone journal can rotate startup evidence
during the gate and create a false load/texture failure. Zero-valued counters
must be emitted numerically (`value + 0` in awk) so `set -u` shell assertions
retain all expected fields.
