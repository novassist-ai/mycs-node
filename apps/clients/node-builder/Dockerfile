# node-builder CLI image (ghcr.io/novassist-ai/node-builder)
#
# Build from repository root:
#   docker build -f apps/clients/node-builder/Dockerfile \
#     --build-arg env=dev \
#     --build-arg version=dev \
#     --build-arg bastion_image_name=mycs-node-image_dev \
#     -t ghcr.io/novassist-ai/node-builder:dev .

FROM python:3.12-slim-bookworm

ARG env=dev
ARG version=dev
ARG bastion_image_name=mycs-node-image_dev

ENV env=${env}
ENV version=${version}
ENV TF_VAR_bastion_image_name=${bastion_image_name}
ENV NB_COOKBOOK_PATH=/usr/local/lib/node-builder/cloud/cookbook
ENV PATH="/usr/local/lib/node-builder/.build/bin:${PATH}"

RUN apt-get update && apt-get install -y --no-install-recommends \
    bash ca-certificates curl git jq openssh-client sshpass unzip zip \
    build-essential autoconf automake libtool pkg-config \
    iptables libqrencode4 \
    && rm -rf /var/lib/apt/lists/*

# Go — build cookbook helper binaries into the image
RUN ARCH="$(dpkg --print-architecture)" \
    && curl -fsSL "https://go.dev/dl/go1.22.5.linux-${ARCH}.tar.gz" \
    | tar -C /usr/local -xz
ENV PATH="/usr/local/go/bin:${PATH}"

COPY libs/shared/app/golang /build/libs/shared/app/golang
COPY apps/clients/node-builder/scripts/build-utils.sh /build/apps/clients/node-builder/scripts/build-utils.sh
WORKDIR /build
RUN bash apps/clients/node-builder/scripts/build-utils.sh :dev:clean-all: \
    && mkdir -p /usr/local/lib/node-builder/.build \
    && cp -a .build/bin /usr/local/lib/node-builder/.build/

COPY cloud/cookbook /usr/local/lib/node-builder/cloud/cookbook
COPY apps/clients/node-builder /tmp/node-builder
RUN pip install --no-cache-dir /tmp/node-builder \
    && rm -rf /tmp/node-builder

COPY apps/clients/node-builder/scripts/prepare-image.sh /tmp/prepare-image.sh
RUN chmod +x /tmp/prepare-image.sh && /tmp/prepare-image.sh \
    && rm -f /tmp/prepare-image.sh

WORKDIR /work
ENTRYPOINT ["nb"]
