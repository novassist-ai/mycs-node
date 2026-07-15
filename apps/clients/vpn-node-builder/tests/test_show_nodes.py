from __future__ import annotations

from vpn_node_builder.commands.show_nodes import ssh_host_for_address


def test_ssh_host_uses_instance_ip_for_mycs_appbricks_dns() -> None:
    assert (
        ssh_host_for_address("1-2-3-4.mycs.appbricks.org", "1.2.3.4") == "1.2.3.4"
    )


def test_ssh_host_uses_address_for_other_hostnames() -> None:
    assert ssh_host_for_address("node.example.com", "1.2.3.4") == "node.example.com"
    assert ssh_host_for_address("bastion.mycs.example.com", "1.2.3.4") == (
        "bastion.mycs.example.com"
    )
    assert ssh_host_for_address(None, "1.2.3.4") == "1.2.3.4"
