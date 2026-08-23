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
    "distribution/download_models_mac.sh",
    "scripts/build_mac_tester_zip.sh",
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


class MacModelDownloadParityTests(unittest.TestCase):
    """download_models_mac.sh must pull the same model files, from the same
    sources, as the Windows setup_easy.ps1 -- otherwise the two platforms
    quietly drift apart and a Mac tester ends up on different weights."""

    def setUp(self) -> None:
        self.mac = (REPO_ROOT / "distribution" / "download_models_mac.sh").read_text(
            encoding="utf-8"
        )
        self.win = (REPO_ROOT / "distribution" / "setup_easy.ps1").read_text(
            encoding="utf-8"
        )

    def test_every_windows_model_url_is_covered_on_mac(self) -> None:
        import re

        # ffmpeg is the one deliberate difference: Windows downloads a build,
        # macOS gets it from Homebrew in setup_mac.sh instead.
        skip = ("gyan.dev",)
        urls = re.findall(r"https://[^\s'\"]+", self.win)
        model_urls = {
            u
            for u in urls
            if u.endswith((".onnx", ".gguf", ".txt", ".zip", ".tar.bz2"))
            and not any(s in u for s in skip)
        }
        self.assertTrue(model_urls, "Windows側からモデルURLを抽出できませんでした")
        for url in sorted(model_urls):
            with self.subTest(url=url):
                self.assertIn(
                    url,
                    self.mac,
                    f"{url} が download_models_mac.sh に含まれていません",
                )

    def test_reazonspeech_repo_matches(self) -> None:
        for text in (self.mac, self.win):
            self.assertIn("reazon-research/reazonspeech-k2-v2", text)

    def test_four_b_model_is_gated_on_ram(self) -> None:
        """The 4B summary model must stay behind a RAM check on Mac too --
        an 8GB MacBook Air should never spend 2.6GB on a model it cannot run."""
        self.assertIn("hw.memsize", self.mac)
        self.assertIn("DOWNLOAD_4B", self.mac)
        four_b_line = next(
            line for line in self.mac.splitlines() if "Qwen3.5-4B-GGUF" in line
        )
        four_b_index = self.mac.index(four_b_line)
        gate_index = self.mac.index('if [ "$DOWNLOAD_4B" = "1" ]')
        self.assertLess(
            gate_index,
            four_b_index,
            "4Bモデルの取得がメモリ判定の外に出ています",
        )


if __name__ == "__main__":
    unittest.main()
