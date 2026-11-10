#!/usr/bin/env python3
"""Unsigned synthetic host: actual dispatcher, all wrappers, complete unchanged SDK."""
import argparse
import hashlib
import os
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
BASELINE = "df878b989e39df282f558098e5c4bd3cf5da0199"
SDK_BLOBS = {
    "4DPluginAPI.c": "62f745e91d81ef2c3c901c656ea8e175d3b173e8",
    "4DPluginAPI.h": "528bf1d2552df08d6a8b1bc95011a9b72934ad5c",
    "4DPluginAPI.def": "5bbdb82fb724b6f8e307feb01d9f158b802de89d",
    "EntryPoints.h": "da428d5f6ca23b0a30371c7288a01d29aa3c466a",
    "Flags.h": "7a5a35539f27430a3fd9cb711d6b789051316471",
    "PrivateTypes.h": "a3098cb662cdbc43ba574fdef72a059c4c6d1cd4",
    "PublicTypes.h": "9ae20b001bff9128f690fff3e6c3f873b6238333",
}
CASES = (
    "scalar-setters", "picture-setter", "reference-setters", "property-getters",
    "property-mismatches", "property-errors", "stringify-errors",
    "stringify-success", "arrays", "resize-limit", "text", "dispatcher", "blob",
    "array-copy", "array-assignment", "blob-copy", "blob-assignment",
)
BASELINE_FAILURES = {
    "scalar-setters", "picture-setter", "property-getters", "property-mismatches",
    "property-errors", "stringify-errors", "dispatcher",
    "array-copy", "array-assignment", "blob-copy", "blob-assignment",
}
BASELINE_DIAGNOSTICS = {
    "scalar-setters": "OWNER IMBALANCE strings=13 handles=0 refs=0 pictures=0",
    "picture-setter": "OWNER IMBALANCE strings=0 handles=0 refs=0 pictures=1",
    "property-getters": "OWNER IMBALANCE strings=3 handles=0 refs=0 pictures=0",
    "property-mismatches": "OWNER IMBALANCE strings=4 handles=0 refs=2 pictures=4",
    "property-errors": "Assertion failed: (threw)",
    "stringify-errors": 'Assertion failed: (threw && output == u8("unchanged"))',
    "dispatcher": "Assertion failed: (object->owners == 1)",
    **{case: "ERROR: AddressSanitizer: heap-use-after-free"
       for case in ("array-copy", "array-assignment", "blob-copy", "blob-assignment")},
}


def run(command, **kwargs):
    return subprocess.run(command, check=True, text=True, **kwargs)


def build(source, work):
    for name, expected in SDK_BLOBS.items():
        data = (source / "4D Plugin API" / name).read_bytes()
        actual = hashlib.sha1(f"blob {len(data)}\0".encode() + data).hexdigest()
        if actual != expected:
            raise RuntimeError(f"Bundled SDK blob changed: {name}: {actual}")
    common = [
        "clang++", "-std=c++17", "-g", "-O1", "-fsanitize=address,undefined",
        "-fno-sanitize-recover=all", "-fno-omit-frame-pointer",
        "-Wno-deprecated-declarations", "-Wno-multichar",
        "-I" + str(source / "4D Plugin API"),
        "-I" + str(source / "4D Plugin API/Classes"), "-I" + str(source),
        "-I" + str(source / "support"),
        "-include", str(ROOT / ".github/tests/offline_platform.h"),
        "-x", "objective-c++",
    ]
    sources = [
        source / "4D Plugin API/4DPluginAPI.c",
        *sorted((source / "4D Plugin API/Classes").glob("*.cpp")),
        source / "support/4DPlugin-JSON.cpp",
        source / "4DPlugin-Shell-Execute.cpp",
        ROOT / ".github/tests/ownership_host.mm",
    ]
    objects = []
    for index, path in enumerate(sources):
        obj = work / f"{index}.o"
        run(common + ["-c", str(path), "-o", str(obj)])
        objects.append(str(obj))
    imports = run(["nm", "-u", *objects], capture_output=True).stdout
    forbidden = (
        "_OBJC_CLASS_$_NSRunningApplication", "_OBJC_CLASS_$_NSWorkspace",
        "_OBJC_CLASS_$_NSBundle", "_OBJC_CLASS_$_NSURL",
        "_CFURLCreateWithFileSystemPath", "_CFURLCopyFileSystemPath",
        "_LSGetApplicationForInfo", "_system", "_popen", "_exec", "_posix_spawn",
        "_kill", "_proc_", "_sysctl", "_ShellExecute", "_CreateToolhelp32Snapshot",
        "_OBJC_CLASS_$_NSTask", "_OBJC_CLASS_$_NSFileManager",
        "_OBJC_CLASS_$_NSAppleScript", "_LSOpen", "_NSPerformService",
        "_fopen", "_open", "_unlink", "_remove", "_rename", "_socket", "_connect",
    )
    for symbol in forbidden:
        if any(line.strip().startswith(symbol) for line in imports.splitlines()):
            raise RuntimeError(f"Forbidden platform import: {symbol}")
    binary = work / "ownership"
    run(["clang++", "-fsanitize=address,undefined", *objects,
         "-framework", "Cocoa", "-framework", "CoreServices", "-o", str(binary)])
    print(f"Compiled {len(sources)} actual translation units; "
          f"{len(SDK_BLOBS)} SDK blobs verified; forbidden imports absent", flush=True)
    return binary


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--baseline", action="store_true")
    args = parser.parse_args()
    with tempfile.TemporaryDirectory(prefix="shell-ownership-") as directory:
        work = Path(directory)
        source = ROOT
        if args.baseline:
            source = work / "baseline"
            source.mkdir()
            archive = work / "baseline.tar"
            with archive.open("wb") as output:
                subprocess.run(["git", "archive", BASELINE], cwd=ROOT,
                               stdout=output, check=True)
            run(["tar", "-xf", str(archive), "-C", str(source)])
        binary = build(source, work)
        failures = []
        for case in CASES:
            result = subprocess.run(
                [str(binary), case], text=True, capture_output=True,
                env={**os.environ, "ASAN_OPTIONS": "detect_leaks=0",
                     "UBSAN_OPTIONS": "halt_on_error=1"},
            )
            print(f"{'FAIL' if result.returncode else 'PASS'} {case}", flush=True)
            print(result.stdout + result.stderr, end="", flush=True)
            if result.returncode:
                failures.append(case)
                if args.baseline and case in BASELINE_DIAGNOSTICS:
                    if BASELINE_DIAGNOSTICS[case] not in result.stdout + result.stderr:
                        raise SystemExit(f"Unexpected baseline diagnostic for {case}")
        print(f"RESULT {len(CASES) - len(failures)}/{len(CASES)} passed; failures={failures}")
        if args.baseline:
            if set(failures) != BASELINE_FAILURES:
                raise SystemExit("Baseline failure signature changed")
        elif failures:
            raise SystemExit(1)


if __name__ == "__main__":
    main()
