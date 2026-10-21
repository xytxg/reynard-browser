# Upstream synchronization and provenance

Date: 2026-10-21

| Item | Commit |
| --- | --- |
| Original fork main before synchronization | `064a8e6511505a861bec2b985644bab727707231` |
| Latest upstream merged | `6e84bfca9c16b2204dc64c93d2089b5410039897` |
| True two-parent merge commit | `21fc98aebe993767b9a539487b8206c6e83d44df` |

The merge preserves both parent histories. The resulting tree uses upstream's latest source as the baseline because the earlier fork's 8 changed paths had already been incorporated or superseded upstream. This avoids restoring obsolete Swift APIs or outdated translation files on top of newer upstream code.

## Localization changes

The upstream snapshot contains 471 main `.xcstrings` keys and 41 settings keys. Localized Chinese entries are not automatically complete just because the `zh-Hans` locale object exists: some have `state: needs_review` or an empty value. The fork reviews 34 such missing/empty entries (including remote debugging, reader mode, page errors and printing) and checks positional Swift format specifiers. Existing upstream translations are preserved rather than mass-replaced.

## Build provenance

The fork uses a separate GitHub Actions workflow to validate catalog coverage and invoke an upstream-derived reusable macOS build workflow for normal IPA and TrollStore TIPA. Only successful runs with actual assets should be presented as releases. The earlier 2026-08-08 experimental build failed with Swift API incompatibilities, so its artifacts must **not** be described as a successful release.

## Future merges

1. Fetch upstream `main` and review commits, source/Gecko version and Xcode build workflow changes.
2. Merge upstream into a separate branch with two-parent history; resolve local translation changes intentionally.
3. Run `python3 tools/tests/check_zh_hans.py` and inspect any new `needs_review` keys.
4. Validate the workflow and build a real IPA; test at least one supported iOS installation method before promoting a prerelease.
5. Document the exact upstream SHA and testing limitations. Do not falsify Stars, download statistics, active users, or security findings.

Note: The fork can receive future upstream changes; the SHA above refers only to this sync.
