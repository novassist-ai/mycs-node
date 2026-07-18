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


def test_set_debug_only_true() -> None:
    set_debug(True)
    assert is_debug() is True
    set_debug(False)
    assert is_debug() is False
    set_debug("yes")  # type: ignore[arg-type]
    assert is_debug() is False
