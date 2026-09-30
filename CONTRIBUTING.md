# Contributing

Thanks for wanting to help! Bug reports, fixes and new ideas are all welcome.

## Getting set up

You need macOS 14+ and Swift 5.10 or newer. Xcode works, and so do the Command Line Tools on their own.

```bash
./Scripts/test.sh        # run the tests
./Scripts/build-app.sh   # build build/MacDirStat.app
open build/MacDirStat.app --args --scan ~/Downloads
```

## Guidelines

- **Keep it fast.** The scanner and treemap must stay responsive on multi-million-file disks. If a change
  touches `DiskScanner`, `TreemapLayout` or `TreemapRenderer`, try it on a big folder (or all of Macintosh HD).
- **Keep it safe.** Anything that touches the disk must go through `FileIdentity.verify`. Tree changes must go
  through `TreeEdit`, so totals, sort order and hard-link ownership stay correct.
- **Add tests** in `Tests/MacDirStatTests` for model or scanner changes. Tests use real files in a temporary
  folder; follow the existing `Fixture` helper.
- **Match the style.** Swift API naming, small focused types, and comments that explain *why*.
- UI changes: please attach before/after screenshots to the pull request, ideally in both a light and a dark
  theme.

## Releasing (maintainers)

1. Push a version tag: `git tag v1.2.0 && git push origin v1.2.0`.
2. The **Release** workflow runs the tests, builds a universal (Apple silicon + Intel) app, packages
   `MacDirStat-1.2.0.dmg` and a `.zip`, and publishes a GitHub Release with install notes.

You can build the same files locally with `VERSION=1.2.0 UNIVERSAL=1 ./Scripts/package-release.sh`.

Releases are unsigned by default. To ship signed and notarized builds, add the Developer ID and notary secrets
listed at the top of `.github/workflows/release.yml`. The workflow picks them up automatically.
