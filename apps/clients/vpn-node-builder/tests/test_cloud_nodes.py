from __future__ import annotations

import json
from pathlib import Path

from vpn_node_builder.cloud import CLOUD_VAGRANT_VBOX
from vpn_node_builder.cloud.credentials import CloudSession
from vpn_node_builder.cloud.nodes import get_node_state, list_nodes, parse_node_from_output
from vpn_node_builder.cloud.power import start_node, stop_node
from vpn_node_builder.core.process import CommandResult


def test_parse_node_from_output(tmp_path: Path) -> None:
    output = (
        tmp_path
        / "sandbox"
        / "aws"
        / "us-east-1"
        / "output.json"
    )
    output.parent.mkdir(parents=True)
    output.write_text(
        json.dumps(
            {
                "cb_managed_instances": {
                    "value": [
                        {
                            "name": "n1",
                            "id": "i-1",
                            "fqdn": "n1.example",
                            "public_ip": "1.2.3.4",
                            "root_user": "ubuntu",
                            "root_passwd": "x",
                            "ssh_key": "KEY",
                        }
                    ]
                },
                "cb_node_version": {"value": "appbricks-bastion_1.2.3"},
                "cb_vpn_type": {"value": "ipsec"},
            }
        ),
        encoding="utf-8",
    )
    record = parse_node_from_output(output, workspace_root=tmp_path)
    assert record.node_type == "sandbox"
    assert record.cloud == "aws"
    assert record.region == "us-east-1"
    assert record.address == "n1.example"
    assert record.version == "1.2.3"


def test_parse_vagrant_vbox_without_region(tmp_path: Path) -> None:
    output = tmp_path / "sandbox" / CLOUD_VAGRANT_VBOX / "output.json"
    output.parent.mkdir(parents=True)
    output.write_text(
        json.dumps(
            {
                "cb_managed_instances": {
                    "value": [{"name": "vm", "id": "vm1", "private_ip": "10.0.0.2"}]
                },
                "cb_node_version": {"value": "x"},
                "cb_vpn_type": {"value": None},
            }
        ),
        encoding="utf-8",
    )
    record = parse_node_from_output(output, workspace_root=tmp_path)
    assert record.cloud == CLOUD_VAGRANT_VBOX
    assert record.region == ""
    assert record.address.endswith("[private]")


def test_get_node_state_vagrant_vbox(monkeypatch) -> None:
    def fake_run(args, **kwargs):
        return CommandResult(
            args=tuple(args),
            returncode=0,
            stdout="State:       powered off (since ...)\n",
            stderr="",
        )

    monkeypatch.setattr("vpn_node_builder.cloud.nodes.run_cmd", fake_run)
    state = get_node_state(
        CLOUD_VAGRANT_VBOX,
        "",
        "vm1",
        session=CloudSession(),
        environ={},
    )
    assert state == "stopped"


def test_list_nodes_uses_state_fn(tmp_path: Path) -> None:
    output = tmp_path / "sandbox" / "aws" / "us-east-1" / "output.json"
    output.parent.mkdir(parents=True)
    output.write_text(
        json.dumps(
            {
                "cb_managed_instances": {
                    "value": [{"name": "n1", "id": "i-1", "public_ip": "1.1.1.1"}]
                },
                "cb_node_version": {"value": "v_9"},
                "cb_vpn_type": {"value": "ipsec"},
            }
        ),
        encoding="utf-8",
    )

    def fake_state(*args, **kwargs):
        return "running"

    nodes = list_nodes(
        tmp_path,
        session=CloudSession(),
        environ={},
        state_fn=fake_state,
    )
    assert len(nodes) == 1
    assert nodes[0].state == "running"


def test_start_stop_vagrant_vbox(monkeypatch) -> None:
    calls: list[tuple[str, ...]] = []

    def fake_run(args, **kwargs):
        calls.append(tuple(args))
        return CommandResult(args=tuple(args), returncode=0, stdout="", stderr="")

    monkeypatch.setattr("vpn_node_builder.cloud.power.run_cmd", fake_run)
    session = CloudSession()
    start_node(CLOUD_VAGRANT_VBOX, "", "vm1", session=session, environ={})
    stop_node(CLOUD_VAGRANT_VBOX, "", "vm1", session=session, environ={})
    assert calls[0][:2] == ("vboxmanage", "startvm")
    assert calls[1][:2] == ("vboxmanage", "controlvm")
