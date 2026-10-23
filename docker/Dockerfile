# syntax=docker/dockerfile:1.7
# Inputs are sanitized, reproducibly repacked layers from the pinned target
# artifacts. No build step executes a target binary, including cross-arch builds.
FROM scratch AS runtime
ADD rootfs.tar.gz /
ADD system.tar.gz /

ENV container=oci \
    ELIXOS_RUNTIME=container \
    ELIXOS_CONSOLE=0 \
    PATH=/toolchain:/usr/local/bin:/bin:/usr/bin \
    SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt

# PID 1 needs the ordinary container root capabilities to start the BEAM as
# 1000:1000 and PostgreSQL as 70:70. No host devices or privileges are needed.
USER 0:0
WORKDIR /
VOLUME ["/priv"]
STOPSIGNAL SIGTERM
ENTRYPOINT ["/init"]

# Keep the compiler outside /priv so an empty persistent volume cannot hide it.
FROM runtime AS sdk
ADD toolchain.tar.gz /
