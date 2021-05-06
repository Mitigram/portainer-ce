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

+ If you are into [12-factor], the behaviour of the initialisation of portainer
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

### Environment Variables

The behaviour of the scripts of this implementation can be controlled through
environment variables starting with `PORTAINER_`.

#### Variables Affecting General Behaviour

In general, the suffix after `PORTAINER_` in the name of these variables is
named after the corresponding command-line [option](#command-line-options),
though in uppercase. These variables are as follows.

Portainer can automatically create an `admin` user if it does not already exist
when it starts up. To aid, you can specify one of the two following variables.
When both are empty, the default, and the corresponding command-line options
empty as well, the entrypoint `portainer.sh` will generate a random password and
print it in its logging at the `notice` level.

+ `PORTAINER_ADMIN_PASSWORD` is a clear-text password to give to the `admin`
  user. For security reasons, you should really refrain from using this variable
  or the corresponding `--password` option.
+ `PORTAINER_ADMIN_PASSWORD_FILE` is the path to a file containing the password
  of the `admin` account. As this file can be protected by the file-system, this
  is a much more secure way of specifying a password. It is also in line with
  how Docker or Kubernetes carry secrets into containers.

A number of variables are more or less passed through further to `settings.sh`,
which will use the API to initialise the portainer instance. These are:

+ `PORTAINER_SETTINGS` should point to a JSON settings file that contain all
  possible and known settings recognised by the `/settings` endpoint of the API
  (see [below](#variables-related-to-portainer-json-settings)). The default is
  to pick the file called [`settings.json`](./settings.json) at the same
  directory that the one where `portainer.sh` is placed.
+ `PORTAINER_TEAMS` can be used to create a number of teams in the portainer
  instance. The default is not to create teams. This variable has two different
  formats:
  + If it starts with a `@` sign, the remaining of the value should be the path
    to a file containing team names. In that file, empty lines and lines
    starting with a hash mark (comments) will be ignored. Otherwise, the content
    of each line should be the name of a team to be created. See the file
    [`examples/teams.lst`](./examples/teams.lst) as an example.
  + Otherwise, the value of this variable should be a comma-separated list of
    team names to be created.
+ `PORTAINER_USERS` can contain the path to a file containing user
  specifications. An example is provided at
  [`examples/users.db`](./examples/users.db). The default is not to create
  users. In that file, empty lines and lines starting with a hash mark
  (comments) will be ignored. Otherwise lines should contain a number of fields,
  separated by the colon `:` sign. These fields should be, in order:
  1. The name of the user to create.
  2. The password to give to the user. If the password is the letter `x`
     (lowercase), a random password will be generated and appear in the logs, at
     verbosity level `info`.
  3. The role for that user. This should be an integer. `1` for administrators,
     `2` for regular users. When empty, the role will default to `2`.
  4. A comma separated list of team specifications. A team specification is the
     name of a team, separated from a role within that team by a slash `/`. The
     role within the team is an integer: `1` for leaders, `2` for members. If
     the slash and role are omitted, the user will simply be a member (role =
     `2`) within that team.

Two variables affect interaction with the main `portainer` binary:

+ `PORTAINER_PORT` will be the port at which the instance will listen to UI and
  API calls. It defaults to `9000`. This option replace the `--bind` option of
  the regular `portainer` binary.
+ `PORTAINER_BIN` should container the path (or name to look in the `PATH`) of
  the `portainer` binary. It defaults to `portainer`.

#### Variables Related to Portainer JSON Settings

Another set of variables, also starting with `PORTAINER_` correspond to the
various keys that can be present in the JSON [settings](./settings.json) object.
The settings object is hierarchical and can also contain arrays. There is a
representation for both as environment variables. To match (and replace)
individual settings in the JSON array, a variable should be constructed with the
name of the keys down along the hierarchy, but converted to upper case, and with
dots `.`, replaced with an underscore `_`. Whenever a JSON key is an array, it
is possible to insert index numbers in the name, e.g. `0`, `1`, etc. up to a
maximum of `10` (this maximum can however be changed through the environment
variable `PORTAINER_MAX`). If you append the suffix `_FILE` at the end of the
environment variable, its value should be the path to a file with the content to
be put inside the JSON structure. This can be used for passing secrets.

The following examplifies naming conventions based on the following settings
structure:

```json
{
  "AllowBindMountsForRegularUsers": false,
  "AllowContainerCapabilitiesForRegularUsers": true,
  "AllowDeviceMappingForRegularUsers": true,
  "AllowHostNamespaceForRegularUsers": true,
  "AllowPrivilegedModeForRegularUsers": false,
  "AllowStackManagementForRegularUsers": true,
  "AllowVolumeBrowserForRegularUsers": true,
  "AuthenticationMethod": 1,
  "BlackListedLabels": [
    {
      "name": "",
      "value": ""
    }
  ],
  "EdgeAgentCheckinInterval": 5,
  "EnableEdgeComputeFeatures": true,
  "EnableHostManagementFeatures": true,
  "EnableTelemetry": false,
  "LDAPSettings": {
    "AnonymousMode": true,
    "AutoCreateUsers": true,
    "GroupSearchSettings": [
      {
        "GroupAttribute": "",
        "GroupBaseDN": "",
        "GroupFilter": ""
      }
    ],
    "Password": "",
    "ReaderDN": "",
    "SearchSettings": [
      {
        "BaseDN": "",
        "Filter": "",
        "UserNameAttribute": ""
      }
    ],
    "StartTLS": true,
    "TLSConfig": {
      "TLS": true,
      "TLSCACert": "",
      "TLSCert": "",
      "TLSKey": "",
      "TLSSkipVerify": false
    },
    "URL": ""
  },
  "LogoURL": "",
  "OAuthSettings": {
    "AccessTokenURI": "",
    "AuthorizationURI": "",
    "ClientID": "",
    "ClientSecret": "",
    "DefaultTeamID": 0,
    "OAuthAutoCreateUsers": true,
    "RedirectURI": "",
    "ResourceURI": "",
    "Scopes": "",
    "UserIdentifier": ""
  },
  "SnapshotInterval": "5m",
  "TemplatesURL": "https://raw.githubusercontent.com/portainer/templates/master/templates.json",
  "UserSessionTimeout": "5m",
  "displayDonationHeader": true,
  "displayExternalContributors": true
}
```

To turn off host management features, you could set the variable
`PORTAINER_ENABLEHOSTMANAGEMENT_FEATURES` to `false`. And to specify the name of
a label to blacklist, you could specify the variable
`PORTAINER_BLACKLISTEDLABELS0_NAME` (note the `0` just after the uppercased
`BLACKLISTEDLABELS`). Finally, to arrange for the password of the LDAP read-only
user to come from the file at `/var/run/secrets/LDAP_password`, you could set
the variable `PORTAINER_LDAPSETTINGS_PASSWORD_FILE` to
`/var/run/secrets/LDAP_password`.

### Command-Line Options

The main script of this implementation, [`portainer.sh`](./portainer.sh)
supports a number of command-line options. Some of these will replace options
that would otherwise be given to `portainer` directly. However, most of these
options will affect the behaviour of the initialisation phase. If you wanted to
pass specific options to `portainer`, you can still do that after having
specified a `--` at the command-line. Everything after that marker will be
blindly passed to `portainer` when it is started by `portainer.sh`. To get help
for `portainer.sh`, run it with the `--help` (or `-h`) option.

Command-line options, when present and relevant, always have precedence over
environment variables.

All other scripts at the root directory of this repository provides the same
kind of help through being called with the `--help` (or `-h`) option.

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

## API Calls from the CLI

This project also contains a utility [script](./api.sh) to make REST calls to
the Portainer API from the command-line. Apart from options to describe the
connection to the portainer instance, this script takes at least 2 arguments:
The first should be an HTTP verb, such as `GET`, `POST` or `PUT`. The second
argument should be the documented REST path, sans the leading `/api`, e.g.
`/settings` to `GET` the current settings. All remaining arguments will be
passed as options to `curl`. This is how you would `POST` changes, for example
using the `--data` command-line option of `curl`.

[`api.sh`](./api.sh) provides online help when called with the `--help` option.

Provided the password of the `admin` user is `s3cr3t`, the following example
would print out the current settings of the local portainer instance running at
port `9000`:

```shell
./api.sh --password s3cr3t GET /settings
```

And the following would create a regular user called `bob`:

```shell
./api.sh --password s3cr3t \
    POST /users --data '{"username": "bob", "password": "cg9Wgky3", "role": 2}'
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