from __future__ import annotations

import json

import pytest

from vpn_node_builder.cloud.credentials import CloudSession
from vpn_node_builder.cloud.regions import list_regions, validate_region
from vpn_node_builder.core.errors import VpnNodeBuilderError
from vpn_node_builder.core.process import CommandResult


def test_list_and_validate_aws_regions(monkeypatch) -> None:
    def fake_run(args, **kwargs):
        if args[:3] == ["aws", "ec2", "describe-regions"]:
            return CommandResult(
                args=tuple(args),
                returncode=0,
                stdout=json.dumps(["us-east-1", "eu-west-1"]),
                stderr="",
            )
        raise AssertionError(args)

    monkeypatch.setattr("vpn_node_builder.cloud.regions.run_cmd", fake_run)
    session = CloudSession()
    env = {"AWS_ACCESS_KEY": "a", "AWS_SECRET_KEY": "b"}
    session.bind_environ(env)
    regions = list_regions("aws", session=session, environ=env)
    assert regions == ["eu-west-1", "us-east-1"]
    validate_region("aws", "us-east-1", session=session, environ=env)
    with pytest.raises(VpnNodeBuilderError, match="Unknown aws region"):
        validate_region("aws", "nope", session=session, environ=env)
