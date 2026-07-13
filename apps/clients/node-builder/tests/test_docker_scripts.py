from __future__ import annotations

import subprocess
from pathlib import Path


def test_get_cloud_image_dev() -> None:
    script = (
        Path(__file__).resolve().parents[1]
        / "scripts"
        / "get-cloud-image.sh"
    )
    result = subprocess.run(
        ["bash", str(script), "dev"],
        check=True,
        capture_output=True,
        text=True,
    )
    assert result.stdout.strip() == "mycs-bastion_dev"


def test_get_cloud_image_usage() -> None:
    script = (
        Path(__file__).resolve().parents[1]
        / "scripts"
        / "get-cloud-image.sh"
    )
    result = subprocess.run(
        ["bash", str(script), "nope"],
        capture_output=True,
        text=True,
    )
    assert result.returncode != 0
    assert "Usage:" in result.stderr
