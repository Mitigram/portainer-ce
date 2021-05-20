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
module log locals options

# Name of the user to authenticate with at the Portainer instance
PORTAINER_ADMIN_USERNAME=${PORTAINER_ADMIN_USERNAME:-"admin"}

# Clear-text password for the user. Try avoiding tu use this!
PORTAINER_ADMIN_PASSWORD=${PORTAINER_ADMIN_PASSWORD:-}

# Path to a file containing the password for the user.
PORTAINER_ADMIN_PASSWORD_FILE=${PORTAINER_ADMIN_PASSWORD_FILE:-}

# URL root of the portainer instance to talk to
PORTAINER_ROOTURL=${PORTAINER_ROOTURL:-"http://localhost:${PORTAINER_PORT_NUMBER:-9000}/"}

parseopts \
  --main \
  --synopsis "$MG_CMDNAME will connect to a running portainer and execute an API call" \
  --usage "$MG_CMDNAME [options] [--] verb path [curl options]" \
  --description "This script uses curl to exercise the Portainer API.

It will authenticate and perform the HTTP request with the verb, e.g. GET,
POST to the API REST path, e.g. /settings/public or /status (leading slash is
optional). All remaining options will be blindly passed to curl." \
  --prefix PORTAINER \
  --shift _begin \
  --options \
    p,portainer,url OPTION ROOTURL - "Root URL where portainer is available." \
    user,username OPTION ADMIN_USERNAME - "Name of the user to authenticate with at the portainer API." \
    passwd,password OPTION ADMIN_PASSWORD - "Cleartext password for the user, you should probably not use this." \
    passwd-file,password-file OPTION ADMIN_PASSWORD_FILE - "Path to a file containing the admin user password, usually a Docker secret or similar." \
    h,help FLAG @HELP - "Print this help and exit" \
  -- "$@"

# shellcheck disable=SC2154  # Var is set by parseopts
shift "$_begin"

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

    if [ -n "$api" ]; then
      shift 2
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