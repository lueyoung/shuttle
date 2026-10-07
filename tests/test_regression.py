#!/usr/bin/env python3
import os
import pathlib
import platform
import shutil
import subprocess
import tempfile
import unittest

import objc_harness


ROOT = pathlib.Path(__file__).resolve().parents[1]


@unittest.skipUnless(platform.system() == "Darwin", "regression harness requires macOS")
@unittest.skipUnless(shutil.which("xcrun"), "regression harness requires xcrun")
class RegressionTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.build_dir = tempfile.TemporaryDirectory(prefix="shuttle-regression-build-")
        cls.binary = objc_harness.build_harness(ROOT / "tests" / "regression.m", cls.build_dir.name)

    @classmethod
    def tearDownClass(cls):
        cls.build_dir.cleanup()

    def run_harness(self, *args):
        env = os.environ.copy()
        # Never launch a terminal from a test, even if a case reaches openHost:.
        env["SHUTTLE_OPENHOST_DRY_RUN"] = "1"
        return subprocess.run([str(self.binary), *args], cwd=ROOT, env=env, capture_output=True, text=True)

    def test_regression_cases(self):
        listing = self.run_harness("--list")
        self.assertEqual(listing.returncode, 0, listing.stderr)
        names = listing.stdout.split()
        self.assertTrue(names, "regression harness lists no cases")

        for name in names:
            with self.subTest(case=name):
                result = self.run_harness(name)
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)


if __name__ == "__main__":
    unittest.main()
