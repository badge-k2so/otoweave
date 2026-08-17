"""Mac (Apple Silicon / Intel) port: repo-root shell launcher/setup scripts.

Mirrors tests/test_distribution_package.py's PowerShellSyntaxTests for the
Windows .ps1 scripts -- a syntax-only check (`bash -n`) so a typo in
setup_mac.sh / run_otoweave.sh / verify_setup_mac.sh / the double-click
.command launcher is caught without needing a Mac to run them.
"""
from __future__ import annotations

import shutil
import subprocess
import unittest
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent

MAC_SHELL_SCRIPTS = (
    "setup_mac.sh",
    "run_otoweave.sh",
    "verify_setup_mac.sh",
    "OtoWeaveを起動.command",
)


@unittest.skipUnless(shutil.which("bash"), "bash が見つかりません")
class MacShellScriptSyntaxTests(unittest.TestCase):
    def test_scripts_parse_without_errors(self) -> None:
        for name in MAC_SHELL_SCRIPTS:
            path = REPO_ROOT / name
            with self.subTest(file=name):
                self.assertTrue(path.is_file(), f"{name} が見つかりません")
                result = subprocess.run(
                    ["bash", "-n", str(path)],
                    capture_output=True,
                    text=True,
                    timeout=30,
                )
                self.assertEqual(
                    result.returncode,
                    0,
                    f"{name} に構文エラー: {result.stderr}",
                )

    def test_scripts_are_executable_in_git(self) -> None:
        """All four are tracked with the executable bit (git mode 100755)
        so `git clone` / GitHub's "Download ZIP" both restore it on macOS
        without the user needing a manual `chmod +x` first -- that manual
        step used to be required and is now only a documented fallback."""
        result = subprocess.run(
            ["git", "ls-files", "-s", "-z", *MAC_SHELL_SCRIPTS],
            cwd=REPO_ROOT,
            capture_output=True,
            text=True,
            timeout=10,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        # "-z" NUL-separates entries and leaves the path unquoted (plain
        # `git ls-files -s` octal-escapes non-ASCII names like the
        # Japanese .command file, which would break the name lookup below).
        lines = {}
        for entry in result.stdout.split("\0"):
            if not entry:
                continue
            meta, _, path = entry.partition("\t")
            mode = meta.split()[0]
            lines[path] = mode
        for name in MAC_SHELL_SCRIPTS:
            with self.subTest(file=name):
                self.assertIn(name, lines, f"{name} がgit管理下にありません")
                self.assertEqual(
                    lines[name],
                    "100755",
                    f"{name} に実行権限がありません（git update-index --chmod=+x が必要です）",
                )


if __name__ == "__main__":
    unittest.main()
