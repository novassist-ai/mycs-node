from __future__ import annotations

from node_builder.cloud.credentials import CloudSession
from node_builder.core.process import CommandResult


def test_ensure_aws_maps_keys() -> None:
    session = CloudSession()
    env = {"AWS_ACCESS_KEY": "A", "AWS_SECRET_KEY": "S"}
    session.bind_environ(env)
    session.ensure_aws()
    assert env["AWS_ACCESS_KEY_ID"] == "A"
    assert env["AWS_SECRET_ACCESS_KEY"] == "S"
    assert session.aws_ready is True
    # second call is no-op
    session.ensure_aws()


def test_ensure_azure_logs_in_once(monkeypatch) -> None:
    calls: list[tuple[str, ...]] = []

    def fake_run(args, **kwargs):
        calls.append(tuple(args))
        return CommandResult(args=tuple(args), returncode=0, stdout="", stderr="")

    monkeypatch.setattr("node_builder.cloud.credentials.run_cmd", fake_run)
    session = CloudSession()
    env = {
        "ARM_CLIENT_ID": "id",
        "ARM_CLIENT_SECRET": "secret",
        "ARM_TENANT_ID": "tenant",
    }
    session.bind_environ(env)
    session.ensure_azure()
    session.ensure_azure()
    assert len(calls) == 1
    assert calls[0][0] == "az"
