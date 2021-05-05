#!/usr/bin/env sh

set -eu

# Find out where dependent modules are and load them at once before doing
# anything. This is to be able to use their services as soon as possible.

# Build a default colon separated DEW_LIBPATH using the root directory to look
# for modules that we depend on. DEW_LIBPATH can be set from the outside to
# facilitate location. Note that this only works when there is support for
# readlink -f, see https://github.com/ko1nksm/readlinkf for a POSIX alternative.
PORTAINER_ROOTDIR=$( cd -P -- "$(dirname -- "$(command -v -- "$(readlink -f "$0")")")" && pwd -P )
PORTAINER_LIBPATH=${PORTAINER_LIBPATH:-${PORTAINER_ROOTDIR}/lib/mg.sh:/usr/local/share/portainer/lib}

# Look for modules passed as parameters in the DEW_LIBPATH and source them.
# Modules are required so fail as soon as it was not possible to load a module
module() {
  for module in "$@"; do
    OIFS=$IFS
    IFS=:
    for d in $PORTAINER_LIBPATH; do
      if [ -f "${d}/${module}.sh" ]; then
        # shellcheck disable=SC1090
        . "${d}/${module}.sh"
        IFS=$OIFS
        break
      fi
    done
    if [ "$IFS" = ":" ]; then
      echo "Cannot find module $module in $PORTAINER_LIBPATH !" >& 2
      exit 1
    fi
  done
}

# Source in all relevant modules. This is where most of the "stuff" will occur.
module log

# shellcheck disable=2034 # Usage string is used by log module on errors
MG_USAGE="
  $MG_CMDNAME will connect to a running portainer and execute an API call
Usage:
  $MG_CMDNAME [-option arg] verb path [curl options]
  where all dash-led single/double options are as follows.
    -p | --portainer | --url
      Root URL where portainer is available. Defaults to http://localhost:9000/
    --user | --username
      Name of the user to authenticate with at the portainer API.
    --passwd | --password
      Cleartext password for the user, you should probably not use this.
    --passwd-file | --password-file
      Path to a file containing the user password, usually a Docker secret or
      similar.
    -v | --verbose
      Verbosity level. From error down to debug.
    -h | --help
      Print this help and exit
Description:
  This script uses curl to exercise the Portainer API.

  It will authenticate and perform the HTTP request with the verb, e.g. GET,
  POST to the API REST path, e.g. /settings/public or /status (leading slash is
  optional). All remaining options will be blindly passed to curl."

# Name of the user to authenticate with at the Portainer instance
PORTAINER_ADMIN_USERNAME=${PORTAINER_ADMIN_USERNAME:-"admin"}

# Clear-text password for the user. Try avoiding tu use this!
PORTAINER_ADMIN_PASSWORD=${PORTAINER_ADMIN_PASSWORD:-}

# Path to a file containing the password for the user.
PORTAINER_ADMIN_PASSWORD_FILE=${PORTAINER_ADMIN_PASSWORD_FILE:-}

# URL root of the portainer instance to talk to
PORTAINER_ROOTURL=${PORTAINER_ROOTURL:-"http://localhost:${PORTAINER_PORT:-9000}/"}

while [ $# -gt 0 ]; do
  case "$1" in
    --user | --username)
      PORTAINER_ADMIN_USERNAME=$2; shift 2;;
    --user=* | --username=*)
      PORTAINER_ADMIN_USERNAME="${1#*=}"; shift 1;;

    --passwd | --password)
      PORTAINER_ADMIN_PASSWORD=$2; shift 2;;
    --passwd=* | --password=*)
      PORTAINER_ADMIN_PASSWORD="${1#*=}"; shift 1;;

    --passwd-file | --password-file)
      PORTAINER_ADMIN_PASSWORD_FILE=$2; shift 2;;
    --passwd-file=* | --password-file=*)
      PORTAINER_ADMIN_PASSWORD_FILE="${1#*=}"; shift 1;;

    -p | --portainer | --url)
      PORTAINER_ROOTURL=$2; shift 2;;
    --portainer=* | --url=*)
      PORTAINER_ROOTURL="${1#*=}"; shift 1;;

    -v | --verbosity | --verbose)
      MG_VERBOSITY=$2; shift 2;;
    --verbosity=* | --verbose=*)
      # shellcheck disable=2034 # Comes from log module
      MG_VERBOSITY="${1#*=}"; shift 1;;

    -h | --help)
      usage "" 0;;

    --)
      shift; break;;
    -*)
      usage "Unknown option: $1 !";;
    *)
      break;;
  esac
done

if [ -n "$PORTAINER_ADMIN_PASSWORD" ] && [ -n "$PORTAINER_ADMIN_PASSWORD_FILE" ]; then
  die "You cannot specify both a password and a password file"
fi


# Sort out passwords. Arrange for the variable PORTAINER_PASSWORD to always
# contain the password for the administrator in cleartext, whenever possible.
if [ -n "$PORTAINER_ADMIN_PASSWORD_FILE" ] && [ -r "$PORTAINER_ADMIN_PASSWORD_FILE" ]; then
  PORTAINER_PASSWORD=$(cat "$PORTAINER_ADMIN_PASSWORD_FILE")
elif [ -n "$PORTAINER_ADMIN_PASSWORD" ]; then
  PORTAINER_PASSWORD=$PORTAINER_ADMIN_PASSWORD
else
  die "No proper password provided, user either --password-file or (unsafe!) --password"
fi

if [ "$#" -lt "2" ]; then
  die "You must at least provide an HTTP verb and an API path"
fi

JWT=;  # This will be the JWT token to use throughout once logged in

# Perform an HTTP request of type "$1" (defaults to GET) to the api endpoint $2
# (sans the leading /api in the path). All remaining arguments are blindly
# passed as options to curl. This function will automatically login at the
# remote portainer instance if no JWT token has been issued yet.
portainer_api() {
  if [ -z "$JWT" ]; then
    log_notice "Logging in as $PORTAINER_ADMIN_USERNAME at $PORTAINER_ROOTURL"
    JWT=$(curl -sSL \
            --header "Content-Type: application/json" \
            --request POST \
            --data "{\"username\":\"$PORTAINER_ADMIN_USERNAME\", \"password\":\"$PORTAINER_PASSWORD\"}" \
            "${PORTAINER_ROOTURL%/}/api/auth" | jq -cr ".jwt")
    if [ -z "$JWT" ]; then
      die "Could not authenticate at $PORTAINER_ROOTURL with $PORTAINER_ADMIN_USERNAME"
    fi
  fi

  if [ -n "$JWT" ]; then
    request=${1:-"GET"}
    api=${2:-}
    shift 2

    if [ -n "$api" ]; then
      curl -sSL \
        --header "Content-Type: application/json" \
        --header "Authorization: Bearer $JWT" \
        --request "$request" \
        "$@" \
        "${PORTAINER_ROOTURL%/}/api/${api#/}"
    fi
  fi
}

portainer_api "$@"