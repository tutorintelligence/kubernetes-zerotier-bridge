# from https://github.com/zerotier/ZeroTierOne/blob/e32fecd16deeab0df65e4aad15ef3e096e35c5a9/ext/installfiles/linux/zerotier-containerized/Dockerfile
FROM debian:buster-slim as builder

## Supports x86_64, x86, arm, and arm64

RUN apt-get update && apt-get install -y curl gnupg
RUN apt-key adv --keyserver pgp.mit.edu --recv-keys 0x1657198823e52a61  && \
    echo "deb http://download.zerotier.com/debian/buster buster main" > /etc/apt/sources.list.d/zerotier.list
RUN apt-get update && apt-get install -y zerotier-one=1.14.0

FROM debian:buster-slim
LABEL version=1.14.0
LABEL description="Containerized ZeroTier One for use on CoreOS or other Docker-only Linux hosts."

# ZeroTier relies on UDP port 9993
EXPOSE 9993/udp

# dependencies for bash script
RUN apt-get update && apt-get install -y curl iproute2 iptables jq procps supervisor && rm -rf /var/lib/apt/lists/*

RUN mkdir -p /var/lib/zerotier-one
COPY --from=builder /usr/sbin/zerotier-cli /usr/sbin/zerotier-cli
COPY --from=builder /usr/sbin/zerotier-idtool /usr/sbin/zerotier-idtool
COPY --from=builder /usr/sbin/zerotier-one /usr/sbin/zerotier-one
COPY files/supervisor-zerotier.conf /etc/supervisor/supervisord.conf
COPY --chmod=755 files/entrypoint.sh /entrypoint.sh

VOLUME ["/var/lib/zerotier-one"]
ENTRYPOINT ["/entrypoint.sh"]
