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


class OpenHostSmokeTests(unittest.TestCase):
    @unittest.skipUnless(platform.system() == "Darwin", "openHost smoke test requires macOS")
    @unittest.skipUnless(shutil.which("xcrun"), "openHost smoke test requires xcrun")
    def test_legacy_menu_item_reaches_openhost_dry_run(self):
        with tempfile.TemporaryDirectory(prefix="shuttle-openhost-") as temp_dir:
            binary = objc_harness.build_harness(ROOT / "tests" / "openhost_smoke.m", temp_dir)

            env = os.environ.copy()
            env["SHUTTLE_OPENHOST_DRY_RUN"] = "1"
            result = subprocess.run([str(binary)], cwd=ROOT, env=env, capture_output=True, text=True)

        output = result.stdout + result.stderr
        self.assertEqual(result.returncode, 0, output)
        self.assertIn("SHUTTLE_OPENHOST_DRY_RUN", output)
        self.assertIn("echo shuttle-openhost-smoke-legacy", output)
        self.assertIn("echo shuttle-openhost-smoke-dictionary", output)
        self.assertIn("echo shuttle-openhost-smoke-built", output)


if __name__ == "__main__":
    unittest.main()
