"""Activate cloud CLI credentials for the current process/session."""

from __future__ import annotations

from collections.abc import Mapping, MutableMapping
from dataclasses import dataclass, field

from vpn_node_builder.core.errors import VpnNodeBuilderError
from vpn_node_builder.core.process import run_cmd


@dataclass
class CloudSession:
    """Tracks which provider CLIs have already been authenticated."""

    aws_ready: bool = False
    azure_ready: bool = False
    google_ready: bool = False
    _environ: MutableMapping[str, str] = field(default_factory=dict)

    def bind_environ(self, environ: MutableMapping[str, str]) -> None:
        self._environ = environ

    def ensure_aws(self, environ: Mapping[str, str] | None = None) -> None:
        env = self._environ if environ is None else dict(environ)
        if self.aws_ready and environ is None:
            return
        access = (env.get("AWS_ACCESS_KEY") or "").strip()
        secret = (env.get("AWS_SECRET_KEY") or "").strip()
        if not access or not secret:
            raise VpnNodeBuilderError(
                'AWS credentials "AWS_ACCESS_KEY" and "AWS_SECRET_KEY" must be set.'
            )
        target = self._environ if environ is None else env
        target["AWS_ACCESS_KEY_ID"] = access
        target["AWS_SECRET_ACCESS_KEY"] = secret
        target.setdefault("AWS_DEFAULT_REGION", "us-east-1")
        if environ is None:
            self.aws_ready = True
        else:
            self._environ.update(env)

    def ensure_azure(self, environ: Mapping[str, str] | None = None) -> None:
        env = dict(self._environ if environ is None else environ)
        if self.azure_ready and environ is None:
            return
        client_id = (env.get("ARM_CLIENT_ID") or "").strip()
        client_secret = (env.get("ARM_CLIENT_SECRET") or "").strip()
        tenant_id = (env.get("ARM_TENANT_ID") or "").strip()
        if not client_id or not client_secret or not tenant_id:
            raise VpnNodeBuilderError(
                'Azure credentials "ARM_CLIENT_ID", "ARM_CLIENT_SECRET" and '
                '"ARM_TENANT_ID" must be set.'
            )
        run_cmd(
            [
                "az",
                "login",
                "--service-principal",
                "--username",
                client_id,
                "--password",
                client_secret,
                "--tenant",
                tenant_id,
            ],
            environ=env,
        )
        if environ is None:
            self.azure_ready = True

    def ensure_google(self, environ: Mapping[str, str] | None = None) -> None:
        env = dict(self._environ if environ is None else environ)
        if self.google_ready and environ is None:
            return
        key_file = (env.get("GOOGLE_CREDENTIALS") or "").strip()
        project = (env.get("GOOGLE_PROJECT") or "").strip()
        if not key_file or not project:
            raise VpnNodeBuilderError(
                'Google credentials "GOOGLE_CREDENTIALS" and "GOOGLE_PROJECT" must be set.'
            )
        run_cmd(
            [
                "gcloud",
                "auth",
                "activate-service-account",
                "--key-file",
                key_file,
                "--quiet",
            ],
            environ=env,
        )
        run_cmd(
            ["gcloud", "config", "set", "project", project, "--quiet"],
            environ=env,
        )
        if environ is None:
            self.google_ready = True


def ensure_cloud_cli(
    cloud: str,
    session: CloudSession,
    environ: MutableMapping[str, str],
) -> None:
    session.bind_environ(environ)
    if cloud == "aws":
        session.ensure_aws()
    elif cloud == "azure":
        session.ensure_azure()
    elif cloud == "google":
        session.ensure_google()
