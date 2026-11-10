# Native ownership audit

## Immutable evidence and scope

Baseline: `df878b989e39df282f558098e5c4bd3cf5da0199` (default-branch
worktree). Guidance: `miyako/skills`,
`4d-skills/skills/4dplugin/SKILL.md` at
`e6b492fcb81e5e1a7f7db723594b420e63bf6eb9`, read through the immutable
GitHub contents API. No additional repository checkout was used.

The exact bundled SDK identities below are verified by the regression runner.
The implementation says `rev : v14`; the API header says `rev : v13`.
Neither comment establishes a verified upstream release. SDK implementation,
engine/ABI headers and export definitions are unchanged.

| Path under `4D Plugin API/` | Git blob |
|---|---|
| `4DPluginAPI.c` | `62f745e91d81ef2c3c901c656ea8e175d3b173e8` |
| `4DPluginAPI.h` | `528bf1d2552df08d6a8b1bc95011a9b72934ad5c` |
| `4DPluginAPI.def` | `5bbdb82fb724b6f8e307feb01d9f158b802de89d` |
| `EntryPoints.h` | `da428d5f6ca23b0a30371c7288a01d29aa3c466a` |
| `Flags.h` | `7a5a35539f27430a3fd9cb711d6b789051316471` |
| `PrivateTypes.h` | `a3098cb662cdbc43ba574fdef72a059c4c6d1cd4` |
| `PublicTypes.h` | `9ae20b001bff9128f690fff3e6c3f873b6238333` |

## Tracked source, exports and build inventory

Both `Shell Execute.vcxproj` (also its filters) and the Xcode Sources phase
compile exactly `4DPluginAPI.c`, `Classes/C_TEXT.cpp`,
`support/4DPlugin-JSON.cpp` and `4DPlugin-Shell-Execute.cpp`. Their headers
are the bundled API headers, `C_TEXT.h`, `C_TYPES.h`, the JSON helper header
and dispatcher header. `.sln`, Xcode project/workspace and shared scheme
do not introduce another native implementation. `4DPluginAPI.def` exports
only `FourDPackex`; that SDK entry calls `PluginMain`, whose selectors 1-4
match the source and bundled-resource manifests.

All other tracked native implementations are dormant:
`Classes/ARRAY_TEXT.cpp`, `Classes/C_BLOB.cpp` and `Classes/C_LONGINT.cpp`,
with their corresponding headers. They are nevertheless compiled by the
isolated regression. `CBytes` is defined in `C_BLOB.h/.cpp`; it is a value
owner of a vector. `C_LONGINT` owns only an integer. `C_TEXT`, `ARRAY_TEXT`
and `C_BLOB` own heap pointers deleted by their destructors. `C_TEXT` already
deleted copy construction/assignment; this fix uses that same minimal policy
for the other two. There are no production copies of these dormant classes.
The new tests deliberately instantiate copy construction and assignment on
the baseline: this is latent capability, not a production call-path crash.

The remaining tracked native headers are the vendored JsonCpp set:
`include/json/{allocator,assertions,autolink,config,features,forwards,json,reader,value,version,writer}.h`.
They do not define plugin `PA_*` helpers and are not included by the dispatcher
or the helper named `4DPlugin-JSON`. The linked prebuilt `a/libjsoncpp.a` and
Windows JsonCpp libraries are not rebuilt or changed; unavailable library
internals are not certified. No additional tracked `.c`, `.cpp`, `.m` or
`.mm` implementation exists at baseline. Indexed absence is an inventory
fact, not a proof of runtime safety.

The `.github/scripts/{bump,native,release,repository,source_version}.py`,
`native.sh`, pre-push guards, both existing workflows, project build phases
and shared scheme were inspected before validation. Both workflows are
manual-only. The Deployment Xcode phase signs, packages and submits for
notarization; the release workflow also publishes binaries. No project build,
workflow dispatch, release, signing, packaging or notarization was run.
Tracked archives, bundles, test database/data, resources and binaries remain
unchanged and were not opened as user data.

## Public and dormant ownership surfaces

| Surface | Reachability and contract |
|---|---|
| Selector 1, `Find best application(&T):T` | Copies the input to `C_TEXT`; returns via the engine content setter `PA_SetUnistring`, not a descriptor transfer. macOS path/URL copies are released after use. Windows `AssocQueryString` branch remains native-platform deferred. |
| Selector 2, `GET PROCESS LIST:C` | Builds independently owned name/path strings per object through `ob_set_s` on macOS and `ob_set_a` on Windows. Collection element insertion retains/copies its input; clear each temporary owning object variable after insertion. Return collection is handed to the caller, not immediately disposed. |
| Selectors 3-4, open/print `(&T;&T)` | `C_TEXT` makes input copies; macOS path/URL/bundle temporaries are released synchronously. No string arrays or asynchronous callback string owners. Native application operations are replaced by synthetic stubs in tests. |
| `ARRAY_TEXT` import/export | Dormant. Import copies borrowed element text into independent C++ strings. Export allocates a fresh `PA_Unistring` for every accepted element, including index zero, and does not dispose a transferred alias. Repeated replacement, shrink and final clear are tested. |
| JSON string setter overloads | Wide/narrow key and UTF-8/UTF-16 value variants compile; only wide-key UTF-8 (macOS) and wide-key wide-value (Windows) are called by production. Initialize the temporary as Undefined before shallow string assignment; otherwise an allocated empty string owner is lost. Variable cleanup owns the assigned value; property storage owns an independent copy. |
| JSON picture setter | Compiled but dormant. Undefined initialization avoids losing the picture created by `PA_CreateVariable(eVK_Picture)`. Existing semantics consume the supplied picture owner; property insertion keeps its copy, then the temporary is cleared. This is not a `CPicture` wrapper: none exists here. |
| JSON object/collection setters | Compiled but dormant. Setters shallow-adopt the supplied owning reference, property insertion retains storage ownership, and clearing the temporary consumes the supplied owner. Tests call them with independent creation owners, not borrowed references. |
| JSON property getters | Compiled but dormant. Successful `PA_GetObjectProperty` results are owning, including type mismatches. Copy scalar/string content before cleanup; clean mismatches. `ob_get_c` hands a matching collection owner to its caller, which must dispose it. |
| JSON stringify | Compiled but dormant. Preserve synchronous independent object-copy semantics. Execute OB Copy explicitly so its error and owning result kind can be checked; successful copy and stringify results have scoped cleanup. The input object is only borrowed for the synchronous copy call. |
| `C_BLOB` / `CBytes` | Dormant. Heap owner is now noncopyable; vector-backed `CBytes` remains copyable. Ordinary synthetic byte import/export is covered. Allocation-failure behavior is deferred below. |

For the unchanged SDK, `PA_SetStringInArray` at baseline lines 4933-4947
disposes the old element then shallow-assigns the incoming descriptor only
when the array kind is Unicode, array data is non-null, the descriptor pointer
is non-null, and `0 <= index <= count`. Rejection transfers nothing. Tests
dispose each rejected input normally; no post-transfer dispose is introduced.
Borrowed getter values are copied before replacement. Multiple elements never
share a newly created allocation.

`PA_SetStringVariable` at lines 4254-4259 is shallow and does not dispose an
initialized owner. `PA_CreateVariable(eVK_Unistring)` creates an empty owner
at lines 4029-4030. Allocated-empty and null-empty host models therefore both
matter. Removing all disposal would not fix this leak.

`PA_GetObjectProperty`/`PA_GetCollectionElement` explicitly require successful
returned variables to be cleared (lines 586-652). Error status is checked
before inspecting/adopting an unspecified failure output. The same applies
to string-conversion outputs and command results. In particular,
`PA_ExecuteCommandByID` initializes a raw zero result before allocating its
parameter handle; failure can leave `fType == 0`, while `UnifyVarKind(0)`
normalizes it as a string. A kind check alone is not safe. New helper errors
throw with an operation message; the dispatcher reports caught native
exceptions to stderr instead of silently swallowing them.

## Regression and provenance

Run on macOS without invoking either project build:

```sh
PYTHONDONTWRITEBYTECODE=1 python3 .github/tests/test_ownership.py --baseline
PYTHONDONTWRITEBYTECODE=1 python3 .github/tests/test_ownership.py
```

The same final harness is compiled against immutable `git archive` baseline
and fixed actual sources, including the complete unchanged bundled SDK,
all four wrapper implementation files, helper and dispatcher: eight translation
units including the host. ASan and UBSan are enabled with fatal diagnostics.
Expected baseline failures are asserted by name, not merely a nonzero result.
Explicit owner maps and create/dispose counts cover strings, pictures,
objects/collections and handles; platform leak detection is disabled, not
used to substitute for those balances.

| Named cases | Baseline | Fixed |
|---|---|---|
| `scalar-setters` | 13 lost string owners in allocated-empty iteration | Balanced |
| `picture-setter` | One lost initialized picture owner | Balanced |
| `property-getters` | Three string owners remain after null-empty iteration | Balanced, including matching collection handoff |
| `property-mismatches` | Four strings, two refs and four pictures remain | Balanced |
| `property-errors` | Missing error propagation assertion | Checks error before poisoned output access/adoption |
| `stringify-errors` | Missing error propagation assertion | Handle failure in both commands, command errors, wrong owning kinds and string-conversion failure covered |
| `dispatcher` | Object retains two owners instead of one | Correct retained collection ownership and exact output |
| `array-copy`, `array-assignment`, `blob-copy`, `blob-assignment` | ASan heap-use-after-free | Both copy traits disabled |
| `reference-setters`, `stringify-success`, `arrays`, `resize-limit`, `text`, `blob` | Six passing controls | All pass |

Local result: baseline **6/17** pass with the exact 11 expected failures;
fixed **17/17** pass. Strings preserve exact empty, ASCII, BMP and
supplementary UTF-16 content/lengths, terminators and the synthetic engine's
capacity metadata. The test capacity field is an explicit host model, not an
assertion about undocumented reserved fields in a real 4D engine. No picture
conversion API is used by this target; no copied byte/unit conversion fix
was applied.

Before any compile or dispatch, forced-include `offline_platform.h` redirects
NSWorkspace, NSBundle, NSURL, LaunchServices lookup and filesystem URL
conversion to synthetic stubs. Inputs and returned process rows are synthetic;
all four actual macOS selectors execute, including zero/three process rows
and open/print argument assertions. Unknown SDK selectors abort. An `nm -u`
gate rejects native platform discovery/launch/path imports, so this is not a
macOS no-op dispatcher test. It is also **not Windows branch execution**.
No shell commands, process launch/termination/enumeration, scripts, real
application automation, private data access or system discovery are invoked
by the test subject.

Host-shim prior art was read as immutable files from
`miyako/4d-plugin-running-application` at
`739c2c1e0bed703e27ee610854e2d90f5806db91`
(`.github/tests/ownership_host.mm`, runner and platform header). Its seven SDK
blob identities match this target. The adapted fixtures, dispatcher assertions,
copy probes and baseline expectations above were executed for this target;
other repositories' results were not reused.

## Explicit deferrals

No Windows native execution or real Windows/macOS 4D host run occurred.
There is no claim to reproduce the original Windows 4D crash. Windows
ShellExecute/Toolhelp/association lookup, platform handle error paths, 4D ABI
integration and real engine retain behavior need platform/host execution.
The synthetic macOS rows deliberately provide the legacy keys the current
dispatcher reads. They do not establish that real `NSRunningApplication`
objects accept those keys; the pre-existing API-shape mismatch documented
in the README is not changed or certified by this ownership fix.

`resize-limit` intentionally verifies a real bundled-SDK limitation:
failed `PA_SetHandleSize` leaves physical storage unchanged but
`PA_ResizeArray` still advances logical count (lines 4566-4603). The fixture
restores its original count solely for safe fixture cleanup. It does not call
the dormant export wrapper against that invalid state and does not certify
OOM recovery. Successful array tests are not OOM evidence. Creation/lock/
resize failure preservation for void array/blob wrappers, including
`CBytes::toParamAtIndex` disposing an old handle before new allocation, needs
a separately designed error/failure boundary; no speculative SDK rewrite or
empty-success fallback is introduced here. Allocation failures during
production collection construction and CoreFoundation conversion remain
outside this narrowly verified fix.

No callbacks, pointer-reference wrapper or `CPicture` class exists among the
tracked plugin/helper implementations. This is an indexed scope finding, not
a blanket assertion about unavailable platform or linked library internals.
