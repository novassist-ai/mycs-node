"""Cloud target identifiers."""

from __future__ import annotations

# Local VM: Vagrant box running on VirtualBox.
CLOUD_VAGRANT_VBOX = "vagrant-vbox"

PUBLIC_CLOUDS = frozenset({"aws", "azure", "google"})
LOCAL_CLOUDS = frozenset({CLOUD_VAGRANT_VBOX, "docker"})
