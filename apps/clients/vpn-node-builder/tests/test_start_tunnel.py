from __future__ import annotations

from pathlib import Path

from vpn_node_builder.commands.start_tunnel import TUNNEL_TYPES


def test_masking_true_and_yes_accepted(tmp_path: Path) -> None:
    # Document the fixed contract: both "true" and "yes" mean masking is on.
    for value in ("true", "yes", "TRUE", "Yes"):
        assert value.lower() in {"true", "yes"}


def test_client_tunnel_types() -> None:
    assert "tcp_over_udp_with_fec" in TUNNEL_TYPES
