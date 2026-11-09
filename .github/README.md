# Manual source and release workflows

`Bump version` and `Build` are independent manual workflows. Bump has one
required `patch`/`minor`/`major` choice (default `patch`); Build has no custom
inputs. Select the branch or tag using GitHub's built-in ref selector.
Neither workflow dispatches the other. There are no tag or push triggers.
Every checkout uses the immutable event SHA.

## Source authority

The intake is `b9e5e5329b962465e49dc8c67e662b58a802c9c1`, with canonical
version **1.0.4**. The rename-follow Bump history initially preferred marketing
version (`1c3f6172f329d50c33e14f45a6af538b48e7b264`), but
`141c30c30f9360bc12b7046e510ea5b3ab9f3709` explicitly superseded that with
coordinated MARKETING_VERSION, CURRENT_PROJECT_VERSION and plist versions.
Its implementation accidentally updated only marketing version. This migration
aligns the six stale source CURRENT tokens from 1.0.2 to 1.0.4, without
incrementing the existing authority.

The six configurations are Development, Deployment and Default at project and
target levels in `Shell Execute.xcodeproj/project.pbxproj`. `Info.plist` requires
CFBundleShortVersionString; its absent CFBundleVersion stays absent.
`English.lproj/InfoPlist.strings` is actually copied into the native bundle and
overrides display metadata, so its stale 2.0.0 display tokens are aligned and
co-bumped. Prebuilt destination metadata is not authority and remains untouched.
Known version references are retained; invalid, cyclic, duplicate, missing,
unresolved or drifting metadata aborts before any writes. Edits replace only
version token spans, preserving encodings, line endings, modes and other bytes.

## Bump safety

The committed executable `.github/hooks/pre-push` is mandatory before editing
and rechecked before pushing. Bump compares the selected event SHA to the exact
remote branch, creates one nonempty source-only direct child with explicit
Actions bot identities and the co-author trailer, then checks Git's actual
old-SHA advertisement. There is exactly one nonforce branch update; followed
tags are disabled through both configuration and `--no-follow-tags`.
An advance, rewind, deletion or same-result race fails rather than retrying.
It never builds, tags, releases or dispatches anything.

## Build and publication safety

Build retains Windows Release x64 MSBuild followed by macOS Default universal
arm64+x86_64, deployment override 11.0, existing frameworks/static libraries,
resources and the `test/Plugins/Shell Execute.bundle` package root. It does not
run 4D or add another runtime/dependency policy. Cleanup is selective and fatal
on errors; it does not delete entire bundles or unrelated Default siblings.
Built plist and the actual copied/compiled English localization are validated.
Signing is strictly verified; both notarization exit status and JSON Accepted
status are required, followed by stapling.

A constant repository-wide publication concurrency group has cancellation
disabled. This is serialization, not a FIFO guarantee. There is no new
default-branch-only restriction. Explicit GH_TOKEN authentication and early
availability checks precede native work. Final checks follow signing,
notarization and stapling. Source/configuration index entries and raw worktree
bytes must still match selected HEAD, independently; only exact generated
outputs and proven native intermediates may differ at the final gate.
Pre-existing ignored build databases fail the initial gate; freshly generated
XCBuildData is retained at the final gate, not reset to fake cleanliness.

Publication checks all release pages through the empty page, including drafts,
the exact API tag ref and exact Git advertisement. Reads fail closed. It then
uses separate create-only POSTs for the tag at selected SHA, a new public
release ID, and each asset. The original empty-body/no-generated-notes policy
is retained. Local assets are `Shell Execute-X.Y.Z.zip` and `.dmg`; GitHub's
actual remote names use dots in place of spaces (`Shell.Execute-X.Y.Z.*`).
Existing tags/releases are never reused, updated, clobbered or deleted.
The intake already has a v1.0.4 release, so Build on this unchanged source
version deliberately refuses publication. Run Bump separately before a new
release; this migration itself does not consume a version.

**Manual recovery:** any failure after a POST may leave a tag, release or
assets, including a request whose successful response was lost. Inspect the
reported tag/release ID and retained uploads manually. No automatic rollback,
deletion or retry occurs; a same-SHA tag race also fails. Resolve partial state
deliberately before another Build attempt.

## Offline validation

Run `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s tests -v`
and `actionlint` (requires PowerShell for native workflow regressions).
Tests use local bare Git origins and closed-PATH native/credential/API doubles,
never real signing, notarization, compilers or 4D. Original fixtures are pinned
to the immutable intake; live version expectations also work after a genuine
guarded Bump. Reference provenance is recorded in `tests/reference-pins.json`.
