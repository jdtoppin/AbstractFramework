#!/usr/bin/env python3
"""Regression tests for the package-external pin policy."""

from __future__ import annotations

import subprocess
import tempfile
import textwrap
import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
CHECKER = REPO_ROOT / "scripts" / "check-external-pins.py"


def run_check(contents: str) -> subprocess.CompletedProcess[str]:
    with tempfile.TemporaryDirectory() as directory:
        pkgmeta = Path(directory) / ".pkgmeta"
        pkgmeta.write_text(textwrap.dedent(contents).lstrip(), encoding="utf-8")
        return subprocess.run(
            ["python3", str(CHECKER), str(pkgmeta)],
            check=False,
            capture_output=True,
            text=True,
        )


class ExternalPinPolicyTest(unittest.TestCase):
    def test_accepts_full_git_sha_and_svn_peg(self) -> None:
        result = run_check(
            """
            externals:
              Libs/GitLib:
                url: https://github.com/example/library
                commit: 0123456789abcdef0123456789abcdef01234567
              Libs/SvnLib:
                url: https://repos.example.invalid/library/trunk@42
                type: svn

            ignore:
              - tests
            """
        )
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_rejects_scalar_url(self) -> None:
        result = run_check(
            """
            externals:
              Libs/Floating: https://github.com/example/library
            """
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("floating scalar URL", result.stderr)

    def test_rejects_short_or_named_git_revision(self) -> None:
        for revision in ("abc1234", "default", "latest"):
            with self.subTest(revision=revision):
                result = run_check(
                    f"""
                    externals:
                      Libs/GitLib:
                        url: https://github.com/example/library
                        commit: {revision}
                    """
                )
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("40-character SHA", result.stderr)

    def test_rejects_unpegged_svn_url(self) -> None:
        result = run_check(
            """
            externals:
              Libs/SvnLib:
                url: https://repos.example.invalid/library/trunk
                type: svn
            """
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("numeric peg revision", result.stderr)

    def test_rejects_branch_or_tag_selectors(self) -> None:
        for selector in ("branch", "tag"):
            with self.subTest(selector=selector):
                result = run_check(
                    f"""
                    externals:
                      Libs/GitLib:
                        url: https://github.com/example/library
                        commit: 0123456789abcdef0123456789abcdef01234567
                        {selector}: moving
                    """
                )
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("forbidden floating selector", result.stderr)


if __name__ == "__main__":
    unittest.main()
