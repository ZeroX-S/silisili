# Native Sailfish test/deploy tooling notes

Current device: Pixel 3a XL Sailfish OS 5.1.0.11 through the Sailfish debug shell at `192.168.2.15:2323`.
The USB interface name in the build VM is deliberately not fixed: it is generated from the
RNDIS MAC and can change after reconnecting the phone.

Use these transport rules for this project:

- Large files, especially RPMs, must be uploaded with
  `vm-deploy/scripts/send-phone-file-python.py`. It writes through the debug shell and verifies SHA-256 on the phone.
  Do not use a long phone-side `curl` download through `telnet-cmd.sh`; the command can be truncated before the RPM
  is complete.
- Multi-step device tests may be sent with `vm-deploy/scripts/run-phone-script.py` when only the final exit code is
  needed, or `vm-deploy/scripts/send-phone-script-python.py` when live remote output is useful. Both base64-inject a
  complete shell script. Avoid long inline `telnet-cmd.sh` snippets because command echo can look like success markers
  and the wrapper can return before the remote work actually reached its own sentinel.
- For UI-coordinate tests on rotated fullscreen video, remember that the screenshot may be landscape while
  `/tmp/bonito-direct-touch` can still behave like portrait coordinates. Convert or verify with a no-intermediate-
  screenshot touch script.
- `telnet-cmd.sh` is still fine for short, read-only probes and simple one-line actions.

Current native install path:

- Build: `work/vm-build-native-rpm.sh`
- Install: `work/vm-install-native-phone.sh` (first runs `vm-setup-sailfish-debug.sh`, which
  discovers the `rndis_host` interface, brings it up and assigns the VM peer address). Set
  `PHONE_IP` and/or `SAILFISH_DEBUG_HOST_CIDR` only when the phone-side debug endpoint has
  intentionally changed.
- Launch: `work/vm-launch-native-sailjail.sh`
- One-pass regression smoke: `work/vm-test-native-regression-batch.sh`

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
