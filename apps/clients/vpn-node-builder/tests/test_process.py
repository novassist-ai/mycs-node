from __future__ import annotations

from vpn_node_builder.core.debug import is_debug, set_debug
from vpn_node_builder.core.process import friendly_command_error


def test_friendly_s3_operation_aborted() -> None:
    msg = friendly_command_error(
        ["aws", "s3", "mb", "s3://vpnb-vpn-eu-west-1", "--region", "eu-west-1"],
        returncode=1,
        detail=(
            "make_bucket failed: s3://vpnb-vpn-eu-west-1 An error occurred "
            "(OperationAborted) when calling the CreateBucket operation: "
            "A conflicting conditional operation is currently in progress "
            "against this resource. Please try again."
        ),
    )
    assert "Could not create S3 bucket 'vpnb-vpn-eu-west-1'" in msg
    assert "deleted recently" in msg
    assert "OperationAborted" not in msg


def test_friendly_bucket_already_exists() -> None:
    msg = friendly_command_error(
        ["aws", "s3", "mb", "s3://vpnb-vpn-us-east-1", "--region", "us-east-1"],
        returncode=1,
        detail="An error occurred (BucketAlreadyExists) when calling CreateBucket",
    )
    assert "already exists in another AWS account" in msg
    assert "VPNB_WORKSPACE_NAME" in msg


def test_friendly_fallback_keeps_command() -> None:
    msg = friendly_command_error(
        ["aws", "ec2", "describe-regions"],
        returncode=255,
        detail="SomeUniqueUnmappedFailure XYZ",
    )
    assert "Command failed (255): aws ec2 describe-regions" in msg
    assert "SomeUniqueUnmappedFailure XYZ" in msg


def test_probe_state_storage_local_skipped() -> None:
    from vpn_node_builder.cloud.credentials import CloudSession
    from vpn_node_builder.terraform.backend import probe_state_storage

    status, detail = probe_state_storage(
        "local",
        base_name="demo",
        region=None,
        environ={},
        session=CloudSession(),
    )
    assert status == "skipped"
    assert "no remote" in detail


def test_probe_state_storage_maps_aws_creds(monkeypatch) -> None:
    """cloud-creds uses AWS_ACCESS_KEY; aws CLI needs AWS_ACCESS_KEY_ID."""
    from vpn_node_builder.cloud.credentials import CloudSession
    from vpn_node_builder.core.process import CommandResult
    from vpn_node_builder.terraform.backend import probe_state_storage

    seen_env: dict[str, str] = {}

    def fake_run(args, **kwargs):
        seen_env.update(kwargs.get("environ") or {})
        return CommandResult(
            args=tuple(args),
            returncode=0,
            stdout="2024-01-01 00:00:00 vpnb-demo-us-east-1\n",
            stderr="",
        )

    monkeypatch.setattr("vpn_node_builder.terraform.backend.run_cmd", fake_run)
    env = {"AWS_ACCESS_KEY": "AKIATEST", "AWS_SECRET_KEY": "secret"}
    status, detail = probe_state_storage(
        "s3",
        base_name="demo",
        region="us-east-1",
        environ=env,
        session=CloudSession(),
    )
    assert status == "exists"
    assert seen_env.get("AWS_ACCESS_KEY_ID") == "AKIATEST"
    assert seen_env.get("AWS_SECRET_ACCESS_KEY") == "secret"


def test_set_debug_only_true() -> None:
    set_debug(True)
    assert is_debug() is True
    set_debug(False)
    assert is_debug() is False
    set_debug("yes")  # type: ignore[arg-type]
    assert is_debug() is False
