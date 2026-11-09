"""The final publication exemption is smaller than the bundle or build roots."""

import unittest

from helper_support import source
import native


class GeneratedOutputTests(unittest.TestCase):
    def test_exact_native_files_and_controlled_directory_descendants(self):
        expected = (
            "test/Plugins/Shell Execute.bundle/Contents/MacOS/Shell Execute",
            "test/Plugins/Shell Execute.bundle/Contents/Info.plist",
            "test/Plugins/Shell Execute.bundle/Contents/Resources/English.lproj/InfoPlist.strings",
            "test/Plugins/Shell Execute.bundle/Contents/_CodeSignature/CodeResources",
            "test/Plugins/Shell Execute.bundle/Contents/Windows64/Shell Execute.4DX",
            "test/Plugins/Shell Execute.bundle/Contents/Resources/constants.xlf",
            "test/Plugins/Shell Execute.bundle/Contents/Resources/manifest.json",
            "build/XCBuildData/build.db",
            "build/XCBuildData/build.db-wal",
            "build/Shell Execute.build/Objects-normal/arm64/main.o",
            "build/Default/Shell Execute.build/build.db",
            "test/Plugins/Shell Execute.build/Objects/file.o",
            "test/Plugins/Default/Shell Execute.build/Objects/file.o",
        )
        for path in expected:
            with self.subTest(path=path):
                self.assertTrue(native.generated(path))

    def test_every_resource_source_or_unproven_output_stays_protected(self):
        excluded = (
            "test/Plugins/Shell Execute.bundle/Contents/MacOS/runtime.dylib",
            "test/Plugins/Shell Execute.bundle/Contents/QuickLook/Thumbnail.png",
            "test/Plugins/Default/Shell Execute.bundle/Contents/Info.plist",
            "test/Plugins/Default/keep", "build/XCBuildData-evil/build.db",
            "build/unexpected-source.cpp",
            "build/Shell Execute.build-evil/injected.cpp",
            "test/Plugins/Shell Execute.bundle/Contents/_CodeSignature-evil/file",
            "test/Plugins/Shell Execute.bundle/Contents/Info.plist.backup",
            *map(str, source.SOURCE_PATHS),
        )
        for path in excluded:
            with self.subTest(path=path):
                self.assertFalse(native.generated(path))
