# Easily Configurable Portainer (CE Edition)

This project creates a [portainer] Docker image that can be configured through a
combination of environment variables (all starting with `PORTAINER_`), JSON file
and command-line options. In addition, the project provides ways to initialise
teams and users. Team creation facilitates matching between LDAP groups and
Portainer teams, whenever LDAP is used to automatically create users and
associate them to existing teams.

  [portainer]: https://portainer.io/

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

**Early note**: This project uses git [submodules]! You need to clone it with
the `--recurse` command-line option, or catch up if you did not.

  [submodules]: https://git-scm.com/book/en/v2/Git-Tools-Submodules

## Using the Image

### Principles

This project overlays an initialisation phase on top of the regular [portainer]
[image][docker-portainer] to facilitate its configuration and ease integration
with complex projects. This implementation is able to automatically configure
all settings of portainer, but also to create users and/or teams. There are
three ways to interact with this initialisation phase and the underlying
portainer:

+ If you are into [12-factor], the behaviour of the initialisation, of portainer
  and its configuration can be modified through setting environment variables.
  All variables start with `PORTAINER_`. For increased security, secret
  information can be provided in many places through variables ending with
  `_FILE`, e.g. when reading information from Docker or Kubernetes secrets.
+ It is possible to provide settings for portainer through a
  [settings](./settings.json) JSON file. You can combine this with
  secret-support in your orchestration platform if necessary.
+ Finally, the entrypoint provides replacements for a few of portainer's
  command-line options, and is able to relay, as-is, all the other ones.

  [12-factor]: https://12factor.net/

The project follows good practices when it comes to security of secrets. Note
however that when run in `debug` mode, passwords may leak into the logs. This is
on purpose and meant as a technique for understanding mistakes that could have
been made. Also, user creation has a feature for generating passwords. These are
meant as temporary passwords and you should change the passwords as soon as
possible.

## Building the Image

### Building Latest

To build the image, you can run a command similar to the following, from the
main directory of this repository.

```shell
docker build -t mitigram/portainer-ce .
```

### Build-Time Configuration

This image recognises two buid-time arguments to pick specific versions of the
underlying dependencies:

+ `PORTAINER_VERSION` should contain the version of portainer to use. This
  should match the [tags][portainer-tags] of the official
  [image][docker-portainer]. The default is to use `latest`.
+ `GRON_VERSION` should contain the version of [gron] to use. It defaults to
  `0.6.1` and there is little purpose in changing it.

  [docker-portainer]: https://hub.docker.com/r/portainer/portainer-ce
  [portainer-tags]: https://hub.docker.com/r/portainer/portainer-ce/tags

### Versioning Conventions

As this image builds upon the official portainer [image][docker-portainer] by
simply providing easier initialisation, it is recommended to follow the same
versioning as [portainer]. For example, to build `2.1.1`, you should use the
following command:

```shell
docker build -t mitigram/portainer-ce:2.1.1 --build-arg PORTAINER_VERSION=2.1.1 .
```

## Implementation Notes

### Portainer Initialisation

Upstart and inialisation is as of the following steps:

1. The [`portainer.sh`](./portainer.sh) is started up. It recognises a number of
   options and/or environment variables. Out of these, it localises the version
   of the [`settings.json`](./settings.json) file to use. It uses the name of
   the keys and their hierarchy to look for matching environment variables. Out
   of these, a new version of the settings JSON structure is saved to a
   temporary location.
2. `portainer.sh` starts [`settings.sh`](./settings.sh) in the background,
   passing through a number of necessary parameters, including the path to the
   temporary settings JSON blob.
3. `portainer.sh` executes Portainer in place, picking a few of the options to
   `portainer.sh` that are relevant to Portainer, together with all command-line
   options that would have been given after the `--` at the prompt when starting
   `portainer.sh`.
4. Portainer starts, it will serve its UI and API on the port specified by
   `portainer.sh`.
5. In the background, [`settings.sh`](./settings.sh) has been waiting for the
   Portainer API to be accessible. `settings.sh` uses various Portainer API
   entrypoints to:
   1. Set the JSON settings that had been prepared by `portainer.sh` in a
      temporary file.
   2. Create teams that should be created, if any.
   3. Create users that should be created, if any. Associate these users to
      their relevant teams.
6. Once done, `settings.sh` cleans away temporary files that would have been
   created by `portainer.sh`. The process ends, configuration is finished.

### Docker Image

This project uses a multi-stage build. The *first* stage consists of the
official [portainer][docker-portainer] image. It exists to bring in binary
dependencies and assets for constructing the Portainer UI. The version of
[portainer] to use at this stage can be controlled through the build-time
argument `PORTAINER_VERSION`, it defaults to `latest`.

The *second* stage uses the features of the [bininstall] project to install the
`tar` [release] of [gron], which contains the relevant binary. [bininstall] is a
submodule of this project. The version of [gron] to use at this stage can be
controlled through the build-time argument `GRON_VERSION`, it defaults to
`0.6.1` (the latest at the time of writing).

The *last* stage starts from an enhanced Alpine [image][yanzi-alpine], with
support for running [glibc] binaries, this is because [gron] requires glibc to
run properly. The last stage will pick up binaries and files from the two
previous stages, and add the various shell scripts, libraries and files
necessary to the initialisation performed by this project.

Finally, the last stage will reconstruct an environment that is similar to the
one used by the original [portainer][docker-portainer] image. All necessary
binaries will be placed at the root of the file system, and the working
directory will be set to the root of the file system. This is necessary as the
implementation of portainer uses the assets path to look up both the HTML, js
and CSS files for the UI, and the binary dependencies such as `kubectl` or
`docker`.

  [bininstall]: https://github.com/efrecon/bininstall
  [release]: https://github.com/tomnomnom/gron/releases
  [gron]: https://github.com/tomnomnom/gron
  [yanzi-alpine]: https://github.com/YanziNetworks/alpine
  [glibc]: https://github.com/sgerrand/alpine-pkg-glibc