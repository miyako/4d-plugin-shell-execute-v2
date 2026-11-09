"""Rebuild only proven native outputs; never discard packaged siblings."""

import argparse
from pathlib import Path
import shutil


PRODUCT = "Shell Execute"
BASE = Path("test/Plugins")
BUNDLE = BASE / (PRODUCT + ".bundle")
WINDOWS = BUNDLE / f"Contents/Windows64/{PRODUCT}.4DX"
WINDOWS_SOURCE = Path("test/plugins") / (PRODUCT + ".bundle") / f"contents/windows64/{PRODUCT}.4DX"
FILES = tuple(BUNDLE / relative for relative in (
    f"Contents/MacOS/{PRODUCT}", "Contents/Info.plist",
    "Contents/Resources/English.lproj/InfoPlist.strings",
    "Contents/Resources/constants.xlf", "Contents/Resources/manifest.json",
    f"Contents/Windows64/{PRODUCT}.4DX", "Contents/_CodeSignature/CodeResources",
))
DIRECTORIES = (
    Path("build/XCBuildData"),
    Path("build") / (PRODUCT + ".build"),
    Path("build/Default") / (PRODUCT + ".build"),
    BASE / (PRODUCT + ".build"),
    BASE / "Default" / (PRODUCT + ".build"),
)
WINDOWS_DIRECTORIES = (Path("Objs/Release"),)


def generated(path):
    return (path in set(map(str, FILES)) | {f"winbuild/{PRODUCT}.4DX"}
            or any(path.startswith(str(directory) + "/")
                   for directory in (*DIRECTORIES, *WINDOWS_DIRECTORIES)))


def validate_paths(paths):
    root = Path.cwd().resolve()
    for path in paths:
        for parent in (path, *path.parents):
            if parent == Path("."):
                break
            if parent.is_symlink():
                raise ValueError(f"Refusing symlink output: {parent}")
        if not path.resolve().is_relative_to(root):
            raise ValueError(f"Output escapes checkout: {path}")
        if path.is_dir():
            for descendant in path.rglob("*"):
                if descendant.is_symlink():
                    raise ValueError(f"Refusing symlink output: {descendant}")


def prepare(platform="macos"):
    if platform == "macos":
        files = FILES
        directories = DIRECTORIES
    elif platform == "windows":
        files = (WINDOWS, WINDOWS_SOURCE, *(WINDOWS_SOURCE.with_suffix(suffix)
                 for suffix in (".exp", ".lib", ".pdb", ".ilk")))
        directories = WINDOWS_DIRECTORIES
    else:
        raise ValueError(f"Unknown native platform: {platform}")
    validate_paths((*files, *directories))
    for path in files:
        path.unlink(missing_ok=True)
    for path in directories:
        if path.exists():
            shutil.rmtree(path)


def require_file(path):
    validate_paths((path,))
    if not path.is_file() or path.stat().st_size == 0:
        raise ValueError(f"Missing or empty native output: {path}")


def normalize_windows():
    # This is the actual vcxproj OutDir, not a recursive first-match search.
    require_file(WINDOWS_SOURCE)
    validate_paths((WINDOWS,))
    WINDOWS.parent.mkdir(parents=True, exist_ok=True)
    if not WINDOWS.exists() or not WINDOWS_SOURCE.samefile(WINDOWS):
        shutil.copyfile(WINDOWS_SOURCE, WINDOWS)
    require_file(WINDOWS)


def merge_windows():
    artifact = Path("winbuild") / (PRODUCT + ".4DX")
    require_file(artifact)
    validate_paths((WINDOWS,))
    WINDOWS.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(artifact, WINDOWS)
    require_file(WINDOWS)


def verify_resources():
    for name in ("manifest.json", "constants.xlf"):
        copied = BUNDLE / "Contents/Resources" / name
        require_file(copied)
        if copied.read_bytes() != Path(name).read_bytes():
            raise ValueError(f"Copied resource differs from source: {copied}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("phase", choices=("clean-macos", "clean-windows", "normalize-windows",
                                        "merge-windows", "verify-resources"))
    phase = parser.parse_args().phase
    if phase.startswith("clean-"):
        prepare(phase.removeprefix("clean-"))
    elif phase == "normalize-windows":
        normalize_windows()
    elif phase == "merge-windows":
        merge_windows()
    else:
        verify_resources()
