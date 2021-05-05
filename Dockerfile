# FIRST LAYER: Portainer itself. The version to install can be controlled
# through the build-time argument PORTAINER_VERSION.
ARG PORTAINER_VERSION=latest
FROM portainer/portainer-ce:${PORTAINER_VERSION} AS portainer


# SECOND LAYER: gron makes JSON greppable and is able to convert back to JSON
# from its internal greppable representation. The version to install can be
# controlled through the build-time argument GRON_VERSION.
FROM alpine:3.13.5 AS gron

# Copy the installer utilities into the image
COPY lib/bininstall/*.sh /usr/local/bin/

# Install gron so we can manipulate JSON later
ARG GRON_VERSION=0.6.1
RUN tarinstall.sh -v -x gron https://github.com/tomnomnom/gron/releases/download/v${GRON_VERSION#v*}/gron-linux-amd64-${GRON_VERSION#v*}.tgz


# FINAL LAYER: We build upon a glibc-compatible alpine in order to be able to
# access Alpine's library of packages and install the ones we need for the
# implementation of our entrypoint and initialisation logic. gron requires
# glibc.
FROM yanzinetworks/alpine:3.13.5

# Copy our dependencies from other layers, and fix apk-accessible dependencies
COPY --from=gron /usr/local/bin/gron /usr/local/bin/
COPY --from=portainer /portainer /usr/local/bin/
RUN apk --no-cache add apache2-utils tini curl

# Recreate some well-structured local installation under /usr/local
COPY lib/mg.sh/*.sh /usr/local/share/portainer/lib/
COPY settings.json /usr/local/share/portainer/etc/
COPY *.sh /usr/local/bin/

EXPOSE 8000 9000

# Wrap everything behind tini to enable proper signalling as we will be spawning
# temporary processes in the background.
ENTRYPOINT [  "tini", "--", \
                "entrypoint.sh", \
                  "--settings", "/usr/local/share/portainer/etc/settings.json" ]
