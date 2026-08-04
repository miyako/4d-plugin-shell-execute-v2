![version](https://img.shields.io/badge/version-17%2B-3E8B93)
![platform](https://img.shields.io/static/v1?label=platform&message=mac-intel%20|%20mac-arm%20|%20win-64&color=blue)
[![license](https://img.shields.io/github/license/miyako/4d-plugin-shell-execute-v2)](LICENSE)
![downloads](https://img.shields.io/github/downloads/miyako/4d-plugin-shell-execute-v2/total)

# 4d-plugin-shell-execute-v2

The Shell Execute plugin drives OS-native file-association and process APIs from 4D: `AssocQueryString`/`LSGetApplicationForInfo` to find the app a file type resolves to, `Toolhelp32`/`NSWorkspace` to list running processes, and `ShellExecute`/`NSWorkspace` to open or print a document with a specific application. Results come back as plain `Text` or a `Collection` of `Object`.

> **A note on this doc's sourcing:** it's written directly from the plugin's C++ source (`4DPlugin-Shell-Execute.cpp`/`.h`). No `manifest.json` and no sample `.4dm` test files were available, so exact command names, parameter names, and 4D-side return-type tokens below are **inferred from the plugin's internal function names and parameter-reading order**, not copied from a verified manifest. Treat the command names as "what they're almost certainly called" rather than a guaranteed-exact spelling — confirm against your own `manifest.json` if you have one.

| Command | Returns | Purpose |
|---|---|---|
| [Find best application](#find-best-application) | Text | Resolve the default/associated application for a file or extension |
| [Get process list](#get-process-list) | Collection | List running processes (Windows) or running applications (macOS) |
| [Open with application](#open-with-application) | *(none)* | Open a document using a specific application |
| [Print with application](#print-with-application) | *(none)* | Print a document using a specific application |

**Platforms:** Windows and macOS.

---

## Requirements & platform notes

- **No optional parameters anywhere in this plugin.** Every parameter is read unconditionally from its position (`fromParamAtIndex`/equivalent) — there's no code path that supplies a default when a parameter is omitted. Pass all parameters on every call.
- **`Open with application` and `Print with application` currently return nothing to 4D on any path** (based on the plugin's own dispatch code — the result pointer is commented out in both handlers). Call them as statement-only commands, not inside an expression expecting a value.
- **`Find best application` behaves differently by platform for what counts as valid input:** on Windows the full string you pass is handed directly to the OS association lookup; on macOS only the file extension is used (the plugin extracts it from your string internally). See the command section below.
- **`Get process list` has a known reliability issue on macOS.** The current source calls a modern process-enumeration API but reads results using key names that belong to an older, unrelated API shape. This is very likely to throw at runtime on macOS rather than silently return incomplete data — see [Error handling](#error-handling--troubleshooting). Test this command specifically before relying on it in production on Mac.
- **Failures are generally silent, not raised as 4D errors.** None of these four commands surfaces a 4D-visible error object — a failed lookup just comes back as empty text, an empty collection, or a no-op. Don't rely on `Last errors` after calling any of them.

---

## Find best application

### Syntax
```4d
Find best application ( path ) → Result
```

| Parameter | Type | Description |
|---|---|---|
| `path` | Text | A file path (macOS) or a file path/extension (Windows) to resolve to its associated application. |
| Result | Text | Full path to the associated application's executable. Empty text if no association is found. |

### Description

**On Windows**, `path` is passed as-is to `AssocQueryString` requesting `ASSOCSTR_EXECUTABLE`. In practice this resolves both bare extensions (`.pdf`) and full file paths, since Windows extracts the relevant association info either way — but only an extension/path Windows itself recognizes will resolve.

**On macOS**, the plugin extracts just the extension from `path` (via `pathExtension`) and looks it up with `LSGetApplicationForInfo`. A bare extension without a leading dot (`pdf` rather than `.pdf`) works the same as a full path ending in that extension, since only the extension component is used either way.

If no association is found on either platform, `Result` comes back as empty text — this is not distinguishable from "found an app with an empty name," so treat empty text as "no association."

**Known gap (Windows only):** if the primary lookup fails but a delegate/UWP execute association exists for the file type, the plugin's fallback code path currently doesn't populate `Result` even when it succeeds internally — you'll get empty text in that case too, rather than the delegate handler's path. This is a plugin-side gap, not something you can work around from 4D.

### Example

```4d
var $path; $app : Text

$path:="/Users/you/Documents/report.pdf"
$app:=Find best application ($path)

If ($app#"")
    ALERT("Default application: "+$app)
Else
    ALERT("No application is associated with this file type.")
End if
```

```4d
// Checking a bare extension
If (Find best application (".docx")#"")
    ALERT("A default application is registered for .docx files.")
End if
```

---

## Get process list

### Syntax
```4d
Get process list → Result
```

| Parameter | Type | Description |
|---|---|---|
| Result | Collection | A collection of objects, one per matched process/application (see fields below). |

Each object in the collection has:

| Property | Type | Description |
|---|---|---|
| `name` | Text | Executable/module file name (Windows), or application name (macOS — see caveat below). |
| `path` | Text | Full path to the executable/application (macOS: empty string `""` if the path couldn't be resolved). |
| `pid` | Number | Process ID. |

### Description

**On Windows**, this walks every running process via `Toolhelp32` and, for each one, looks at its module list to find the module whose name matches the process's own executable name — i.e. it reports each process's main executable, not every DLL it has loaded. `path` is the full path to that executable.

**On macOS**, this iterates `NSWorkspace`'s running-applications list. **Known issue:** the code reads each entry using `valueForKey:` with key names (`NSApplicationName`, `NSApplicationPath`, `NSApplicationProcessIdentifier`) that belong to an older, deprecated app-listing API shape, not the one actually being called here. This is very likely to raise an unhandled key-value-coding exception at runtime on current macOS rather than quietly return wrong data — it hasn't been verified against a running build, but it's a well-documented mismatch between two different Cocoa APIs. **Treat `Get process list` on macOS as unreliable until this is fixed and verified**, regardless of what this doc says its return shape is on paper.

Neither platform branch raises a 4D-visible error if enumeration partially fails (e.g. a permission-restricted process on Windows) — such entries are simply skipped.

### Example

```4d
var $processes : Collection
var $p : Object

$processes:=Get process list

For each ($p; $processes)
    ALERT($p.name+" ("+String($p.pid)+")"+Char(Carriage return)+$p.path)
End for each
```

```4d
// Find a specific running process by name
var $processes : Collection
var $match : Object

$processes:=Get process list
$match:=$processes.query("name = :1"; "notepad.exe").first()

If ($match#Null)
    ALERT("Found, pid="+String($match.pid))
End if
```

---

## Open with application

### Syntax
```4d
Open with application ( document ; application )
```

| Parameter | Type | Description |
|---|---|---|
| `document` | Text | Path to the file to open. |
| `application` | Text | Path to the application to open it with. |
| Result | *(none)* | This command does not return a value. |

### Description

**On Windows**, this calls `ShellExecute` with the `"open"` verb. Neither the file nor application path is quoted before being passed to the OS call — a `document` or `application` path containing spaces may not behave as expected. `ShellExecute`'s own return code isn't checked, so a failure (missing file, missing application, no permission) is silent from 4D's side.

**On macOS**, this calls `NSWorkspace`'s `openFile:withApplication:`. If `application` doesn't resolve to a valid app, the call is silently skipped (no error, no open). Note this Cocoa method is deprecated as of macOS 10.15 in Apple's headers — it still functions on current macOS, but is a candidate for replacement in a future OS release.

There is no confirmation that the open actually succeeded — treat this as fire-and-forget.

### Example

```4d
Open with application ("/Users/you/Documents/report.pdf"; "/Applications/Preview.app")
```

```4d
// Windows
Open with application ("C:\\Users\\you\\Documents\\report.docx"; "C:\\Program Files\\Microsoft Office\\root\\Office16\\WINWORD.EXE")
```

---

## Print with application

### Syntax
```4d
Print with application ( document ; application )
```

| Parameter | Type | Description |
|---|---|---|
| `document` | Text | Path to the file to print. |
| `application` | Text | Path to the application to print it with. |
| Result | *(none)* | This command does not return a value. |

### Description

**On Windows**, this calls `ShellExecute` with the `"print"` verb. Same quoting caveat as `Open with application`: neither path is quoted, and the return code isn't checked.

**On macOS**, this resolves `application` to an `NSBundle`, reads its bundle identifier, and asks `NSWorkspace` to open the document URL for printing via that bundle identifier (`NSWorkspaceLaunchAndPrint`). If `application` isn't a valid app bundle path, the whole print request is silently skipped. This API is also marked deprecated in current macOS headers, functionally still present as of writing.

Like `Open with application`, there's no success/failure signal back to 4D.

### Example

```4d
Print with application ("/Users/you/Documents/report.pdf"; "/Applications/Preview.app")
```

```4d
// Guard against a missing application path before calling
var $app : Text
$app:=Find best application (".pdf")
If ($app#"")
    Print with application ("/Users/you/Documents/report.pdf"; $app)
End if
```

---

## Error handling & troubleshooting

- **Empty text from `Find best application` means "no association found," not an error.** There's no separate error signal — check for `""` explicitly.
- **`Get process list` may throw on macOS.** As documented above, the current macOS implementation reads process-list entries with key names that don't match the API actually being called; verify this command works on your target macOS version before shipping, and treat any crash/exception here as this known issue rather than an environment problem on your end.
- **`Open with application` / `Print with application` give no feedback on failure, on either platform.** A missing file, a missing/invalid application path, or a permissions problem all fail the same way: nothing visibly happens. If you need to confirm success, check for the expected side effect yourself (e.g. poll for the target process, or use `Get process list` afterward) rather than expecting a return value or error.
- **Paths with spaces are not quoted on Windows** for either `Open with application` or `Print with application` — a document or application path containing spaces can behave unpredictably. Avoid unquoted paths with embedded spaces until this is fixed plugin-side.
- **Windows fallback for delegate/UWP file associations in `Find best application` doesn't currently return anything**, even when the OS-level lookup itself would have succeeded — you'll see empty text for those file types rather than the delegate handler's path.
- **Both "with application" commands are fire-and-forget by design in the current source** — neither has a return value, so don't write 4D code that expects one.

---

## Quick reference

```4d
// Resolve and open with the default app
var $doc; $app : Text
$doc:="/Users/you/Documents/report.pdf"
$app:=Find best application ($doc)
If ($app#"")
    Open with application ($doc; $app)
End if

// List running processes/apps
var $processes : Collection
$processes:=Get process list
For each ($p; $processes)
    ALERT($p.name+" — "+$p.path+" ("+String($p.pid)+")")
End for each

// Print with a specific application
Print with application ("/Users/you/Documents/report.pdf"; "/Applications/Preview.app")
```
