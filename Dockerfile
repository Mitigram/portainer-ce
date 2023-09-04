# FIRST STAGE: Portainer itself. The version to install can be controlled
# through the build-time argument PORTAINER_VERSION.
ARG PORTAINER_VERSION=latest
FROM portainer/portainer-ce:${PORTAINER_VERSION} AS portainer


# SECOND STAGE: gron makes JSON greppable and is able to convert back to JSON
# from its internal greppable representation. The version to install can be
# controlled through the build-time argument GRON_VERSION.
FROM alpine:3.13.5 AS gron

# Copy the installer utilities into the image
COPY lib/bininstall/*.sh /usr/local/bin/

# Install gron so we can manipulate JSON later
ARG GRON_VERSION=0.6.1
RUN tarinstall.sh -v -x gron https://github.com/tomnomnom/gron/releases/download/v${GRON_VERSION#v*}/gron-linux-amd64-${GRON_VERSION#v*}.tgz


# FINAL STAGE: We build upon a glibc-compatible alpine in order to be able to
# access Alpine's library of packages and install the ones we need for the
# implementation of our entrypoint and initialisation logic. gron requires
# glibc.
FROM yanzinetworks/alpine:3.13.5


# OCI Annotation: https://github.com/opencontainers/image-spec/blob/master/annotations.md
LABEL org.opencontainers.image.title="portainer-ce"
LABEL org.opencontainers.image.description="Easily configurable Portainer"
LABEL org.opencontainers.image.authors="Emmanuel Frecon <efrecon+github@gmail.com>"
LABEL org.opencontainers.image.url="https://github.com/Mitigram/portainer-ce"
LABEL org.opencontainers.image.documentation="https://github.com/Mitigram/portainer-ce/README.md"
LABEL org.opencontainers.image.source="https://github.com/Mitigram/portainer-ce"
LABEL org.opencontainers.image.version="$SRCTAG"
LABEL org.opencontainers.image.created="$BUILD_DATE"
LABEL org.opencontainers.image.vendor="Mitigram AB"
LABEL org.opencontainers.image.licenses="MIT"

# Copy our dependencies from other stages, and fix apk-accessible dependencies.
# Arrange to copy the binaries that portainer depends on, as well as the assets,
# to the same location as in the original image. This is because the
# implementation looks for binaries at the assets path.
COPY --from=gron /usr/local/bin/gron /usr/local/bin/
COPY --from=portainer /portainer /docker* /helm* /kompose* /kubectl* /
COPY --from=portainer /public /public/
RUN apk --no-cache add apache2-utils tini curl jq

# Recreate some well-structured local installation under /usr/local
COPY lib/mg.sh/*.sh /usr/local/share/portainer/lib/
COPY settings.json /usr/local/share/portainer/etc/
COPY *.sh /usr/local/bin/

WORKDIR /
ENV PORTAINER_PORT_NUMBER 9000
ENV PORTAINER_SETTINGS /usr/local/share/portainer/etc/settings.json
EXPOSE 8000 ${PORTAINER_PORT_NUMBER}

# Wrap everything behind tini to enable proper signalling as we will be spawning
# temporary processes in the background. We respected the placement of binaries
# directly under the root of the disk, as in the original image, so we have to
# tell our entrypoint where portainer is located.
ENTRYPOINT [  "tini", "--", \
                "portainer.sh", \
                  "--binary", "/portainer" ]
