# Build and Push Automation

When properly setup, these scripts can automatically be called by the Docker hub
infrastructure whenever a build of this project is requested. They will figure
out the list of current [tags] for the official source repository and
automatically build (and push) a version of this image with the same tag. The
name of the official (and local) tag is passed through the `PORTAINER_VERSION`
variable as a build argument. Building is not only aware of the official tags, but also of this repository. The current git commit sha is stored as label and used to detect when the image should be rebuilt.

  [tags]: https://hub.docker.com/r/portainer/portainer-ce/tags