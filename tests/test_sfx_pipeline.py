"""Task 23 pytest coverage for the SFX synthesis pipeline.

Deviations from the implementation plan's draft test:
  * The plan assumed an ``SFX_OUT_DIR`` env var; the real tool has no env
    support, so the monkeypatch was dropped. A ``--out-dir`` CLI flag was
    added to generate_sfx.py instead (default unchanged: assets/audio/sfx/)
    so the test writes to a pytest tmp dir without touching committed assets.
  * Paths are resolved from this file's location instead of relying on the
    pytest invocation cwd being the repo root.
  * ``sys.executable`` is used instead of a literal ``python3``.
"""

import subprocess
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent


def test_sfx_spec_has_required_keys():
    sys.path.insert(0, str(REPO_ROOT / "src" / "tools" / "config"))
    from sfx_spec import SFX_SPECS
    required_sfx = [
        "bullet_fire", "explosion", "hostage_board", "hostage_death",
        "landing", "tank_fire", "jet_fire", "engine_loop",
        "ui_select", "ui_confirm",
    ]
    for sfx in required_sfx:
        assert sfx in SFX_SPECS, f"Missing SFX spec: {sfx}"


def test_generate_sfx_produces_ogg(tmp_path):
    result = subprocess.run(
        [sys.executable, str(REPO_ROOT / "src" / "tools" / "generate_sfx.py"),
         "--sfx", "bullet_fire", "--out-dir", str(tmp_path)],
        capture_output=True, text=True,
    )
    assert result.returncode == 0, result.stderr
    assert (tmp_path / "bullet_fire.ogg").exists()
