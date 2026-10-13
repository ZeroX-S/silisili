# Native RPM GitHub release process

Every GitHub source update that advances the native package version must also
publish the tested AArch64 RPM as a GitHub Release asset. A source-only update
is not a complete native release.

## Required release contents

- Tag: `native-vVERSION-RELEASE`, for example `native-v1.1.0-1.22`.
- Release title: `SiliSili Native VERSION-RELEASE`.
- RPM: `silisili-native-devel-VERSION-RELEASE.aarch64.rpm`.
- Sidecar checksum: the same filename with `.sha256` appended.
- The exact source commit used for the release, recorded in the release notes.

The native package remains a development build, so the GitHub Release is
published as a prerelease.

## Gate and publish

First build the RPM, complete the relevant real-device regressions, and update
`packaging/apps/silisili-native/release-asset.sha256` with the final artifact
digest. The manifest filename must match the Version and Release fields in the
RPM spec.

Validate locally without changing GitHub:

```sh
bash vm-deploy/scripts/publish-silisili-native-github-release.sh --check
```

Commit and push the reviewed source changes. Publishing intentionally refuses
to continue unless the worktree is clean and the current commit is already the
tip of the matching remote branch. Install and authenticate the GitHub CLI,
then run:

```sh
bash vm-deploy/scripts/publish-silisili-native-github-release.sh --publish
```

Use `--rpm PATH` for a dedicated output directory and `--notes-file PATH` for
the complete changes since the previous published release. The script adds the
exact source commit, RPM identity and checksum before those notes. For 1.58:

```sh
bash vm-deploy/scripts/publish-silisili-native-github-release.sh --publish \
  --rpm /path/to/silisili-native-devel-1.1.0-1.58.aarch64.rpm \
  --notes-file docs/releases/native-v1.1.0-1.58.md
```

The release tag targets the verified commit SHA rather than a moving branch.

The script revalidates the source manifest, RPM filename, optional RPM metadata
and the checked-in SHA-256. It then creates the release or replaces both assets
on the existing release only when the tag still points to the same commit. It
will not move an existing version tag to a different commit.

Never publish an RPM that has not passed its device regression, and never
reuse a Version/Release pair for a different payload after that tag has been
published.
