from __future__ import annotations

from pathlib import Path

import pytest

from node_builder.core.errors import NodeBuilderError
from node_builder.core.eula import SKIP_EULA_ENV, check_eula, is_eula_accepted


def test_eula_already_accepted(tmp_path: Path) -> None:
    root = tmp_path / "run"
    root.mkdir()
    (root / "eula_accepted").touch()
    check_eula(root, input_func=lambda _p: "no")
    assert is_eula_accepted(root)


def test_eula_skip_env(tmp_path: Path) -> None:
    root = tmp_path / "run"
    root.mkdir()
    check_eula(
        root,
        environ={SKIP_EULA_ENV: "1"},
        input_func=lambda _p: "no",
    )
    assert not is_eula_accepted(root)


def test_eula_accept(tmp_path: Path) -> None:
    root = tmp_path / "run"
    root.mkdir()
    messages: list[str] = []
    check_eula(
        root,
        environ={},
        input_func=lambda _p: "yes",
        output_func=messages.append,
    )
    assert is_eula_accepted(root)
    assert messages


def test_eula_reject(tmp_path: Path) -> None:
    root = tmp_path / "run"
    root.mkdir()
    with pytest.raises(NodeBuilderError, match="not accepted"):
        check_eula(root, environ={}, input_func=lambda _p: "no")
    assert not is_eula_accepted(root)


def test_eula_quit(tmp_path: Path) -> None:
    root = tmp_path / "run"
    root.mkdir()
    with pytest.raises(NodeBuilderError, match="not accepted"):
        check_eula(root, environ={}, input_func=lambda _p: "q")
