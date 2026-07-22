import tempfile
import unittest
from pathlib import Path
from unittest import mock

import launcher


class LauncherVenvTests(unittest.TestCase):
    def test_unusable_venv_python_is_rejected(self):
        python_bin = Path("C:/project/.venv/Scripts/python.exe")
        completed = subprocess_result(returncode=103)

        with mock.patch("launcher.subprocess.run", return_value=completed):
            self.assertFalse(launcher.is_venv_python_usable(python_bin))

    def test_existing_unusable_venv_is_recreated(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            venv_dir = root / ".venv"
            scripts_dir = venv_dir / "Scripts"
            scripts_dir.mkdir(parents=True)
            old_python = scripts_dir / "python.exe"
            old_python.write_text("stale", encoding="utf-8")

            def create_fresh_venv(command):
                self.assertEqual(command[-2:], ["venv", str(venv_dir)])
                scripts_dir.mkdir(parents=True, exist_ok=True)
                old_python.write_text("fresh", encoding="utf-8")

            with (
                mock.patch.object(launcher, "VENV_DIR", venv_dir),
                mock.patch.object(launcher, "get_venv_python", return_value=old_python),
                mock.patch.object(launcher, "is_venv_python_usable", side_effect=[False, True]),
                mock.patch.object(launcher, "run_logged_command", side_effect=create_fresh_venv) as run_command,
            ):
                self.assertEqual(launcher.ensure_venv(), old_python)

            run_command.assert_called_once()
            self.assertEqual(old_python.read_text(encoding="utf-8"), "fresh")


def subprocess_result(returncode):
    return launcher.subprocess.CompletedProcess(
        args=["python", "--version"],
        returncode=returncode,
        stdout="did not find executable",
    )


if __name__ == "__main__":
    unittest.main()
