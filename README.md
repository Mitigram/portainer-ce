# Easily Configurable Portainer (CE Edition)

This project creates a [portainer] Docker image that can be configured through a
combination of environment variables (starting with `PORTAINER_`), JSON file and
command-line options. In addition, the project provides ways to initialise teams
and users. Team creation facilitates matching between LDAP groups and Portainer
teams, whenever LDAP is used to automatically create users and associate them to
existing teams.

Provided this image is at `mitigram/portainer-ce`, the following command would:

+ start Portainer on port 8080
+ generate a password for the administrator,
+ suppress telemetry
+ Create two teams called `devs` and `admins`.

```shell
docker run -it --rm \
  -e PORTAINER_ENABLETELEMETRY=false \
  mitigram/portainer-ce \
  --port 8080 \
  --teams devs,admins
```

## Building the Image

build-time arguments...

## Using the image

## Implementation Notes

Explain interaction portainer.sh->settings.sh
