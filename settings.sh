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
module log controls

# shellcheck disable=2034 # Usage string is used by log module on errors
MG_USAGE="
  $MG_CMDNAME will connect to a running portainer and change its settings,
  and create teams and users.
Usage:
  $MG_CMDNAME [-option arg]...
  where all dash-led single/double options are as follows.
    -s | --settings
      Path to settings file in JSON format. This needs to contain all
      possible keys and their values. Defaults to settings.json in same
      directory as this script.
    -p | --portainer | --url
      Root URL where portainer is available. Defaults to http://localhost:9000/
    -t | --teams | --teams-file
      Path to a file containing team names, one per line (empty lines and lines
      starting with a # ignored)
    -u | --users | --users-file
      Path to a file containing a list of users to create. Apart from comments
      and blank lines, lines should contain colon separated fields:
      username:password:role:teams. When password is x, one will be generated.
      role is the role of the user in Portainer: 1: admin, 2: regular user.
      teams is a colon separated list of teams specifications: team/role, where
      the role defaults to 2 (regular member), otherwise 1: leader.
    --user | --username
      Name of the user to authenticate with at the portainer API.
    --passwd | --password
      Cleartext password for the user, you should probably not use this.
    --passwd-file | --password-file
      Path to a file containing the user password, usually a Docker secret or
      similar.
    --remove
      Comma separated list of file paths to remove once initialisation has
      been performed.
    -v | --verbose
      Verbosity level. From error down to debug.
    -h | --help
      Print this help and exit
Description:
  This script is designed to be run from the main Docker entrypoint script
  called portainer.sh. You should probably not call it manually."

# Name of the user to authenticate with at the Portainer instance
PORTAINER_ADMIN_USERNAME=${PORTAINER_ADMIN_USERNAME:-"admin"}

# Clear-text password for the user. Try avoiding tu use this!
PORTAINER_ADMIN_PASSWORD=${PORTAINER_ADMIN_PASSWORD:-}

# Path to a file containing the password for the user.
PORTAINER_ADMIN_PASSWORD_FILE=${PORTAINER_ADMIN_PASSWORD_FILE:-}

# Path to settings file. This should contain a JSON object that can be used to
# send to the /settings API endpoint.
PORTAINER_SETTINGS=${PORTAINER_SETTINGS:-${PORTAINER_ROOTDIR%/}/settings.json}

# URL root of the portainer instance to talk to
PORTAINER_ROOTURL=${PORTAINER_ROOTURL:-"http://localhost:${PORTAINER_PORT:-9000}/"}

# Comma separated list of teams to setup. This can be used when setting up LDAP
# and arranging for group membership to transfer into team membership
# autmatically.
PORTAINER_TEAMS=${PORTAINER_TEAMS:-""}

# Path to a user specification file. Empty lines and lines starting with a
# hash-mark will be ignored. Otherwise, colon separated fields:
# username:password:role:teams, where teams is a colon separated list of teams.
# When password is an x, a password will be generated.
PORTAINER_USERS=${PORTAINER_USERS:-}

# Comma separated list of files to remove upon initialisation.
ZAP_FILES=

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

    -s | --settings)
      PORTAINER_SETTINGS=$2; shift 2;;
    --settings=*)
      PORTAINER_SETTINGS="${1#*=}"; shift 1;;

    -p | --portainer | --url)
      PORTAINER_ROOTURL=$2; shift 2;;
    --portainer=* | --url=*)
      PORTAINER_ROOTURL="${1#*=}"; shift 1;;

    -t | --teams-file | --teams)
      PORTAINER_TEAMS=$2; shift 2;;
    --teams-file=* | --teams=*)
      PORTAINER_TEAMS="${1#*=}"; shift 1;;

    -u | --users-file | --users)
      PORTAINER_USERS=$2; shift 2;;
    --users-file=* | --users=*)
      PORTAINER_USERS="${1#*=}"; shift 1;;

    --remove)
      ZAP_FILES=$2; shift 2;;
    --remove=*)
      ZAP_FILES="${1#*=}"; shift 1;;

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

if ! command -v jq >&2 >/dev/null; then
  die "This script requires an installation of jq"
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

# Wait for portainer to be present
log_info "Waiting for portainer to respond at $PORTAINER_ROOTURL"
backoff_loop --sleep 1 --max 10 -- curl -fsL "${PORTAINER_ROOTURL%/}/api/status" > /dev/null

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

# Generate a random password as long as $1 (defaults to 30 chars)
pwdgen() {
  strings < /dev/urandom | grep -o '[[:alnum:]]' | head -n "${1:-30}" | tr -d '\n'; echo
}

team_create() {
  id=$(portainer_api "GET" /teams | jq -cr ".[] | select(.Name == \"$1\") | .Id")
  if [ -z "$id" ]; then
    log_debug "Creating team $1"
    id=$(portainer_api "POST" /teams --data "{\"name\": \"$1\"}" | jq -cr '.Id')
    log_info "Created team $1 with identifier $id"
  fi
  printf %d\\n "$id"
}

# shellcheck disable=SC2119 # Running with no arguments will trigger a login only
portainer_api; # Login

if [ -z "$PORTAINER_SETTINGS" ]; then
  log_info "Getting current settings..."
  portainer_api "GET" /settings | jq
else
  log_notice "Setting up portainer at $PORTAINER_ROOTURL with settings from $PORTAINER_SETTINGS"
  # Settings might leak passwords in the response, so discard the response
  # unless we run in debugging mode.
  if at_verbosity "debug"; then
    portainer_api "PUT" /settings --data-binary "@${PORTAINER_SETTINGS}"
  else
    portainer_api "PUT" /settings --data-binary "@${PORTAINER_SETTINGS}" >/dev/null
  fi
fi

if [ -n "$PORTAINER_TEAMS" ]; then
  sed -E 's/^[[:space:]]*#.*$//g' "$PORTAINER_TEAMS" | while IFS= read -r team; do
    if [ -n "$team" ]; then
      team_create "$team" > /dev/null
    fi
  done
fi

if [ -n "$PORTAINER_USERS" ]; then
  sed -E 's/^[[:space:]]*#.*$//g' "$PORTAINER_USERS" | while IFS= read -r line; do
    if [ -n "$line" ]; then
      username=$(printf %s\\n "$line" | cut -d ":" -f 1)
      password=$(printf %s\\n "$line" | cut -d ":" -f 2)
      role=$(printf %s\\n "$line" | cut -d ":" -f 3); # 1: admin, 2: regular user
      teams=$(printf %s\\n "$line" | cut -d ":" -f 4)

      if portainer_api GET /users | jq -cr '.[].Username' | grep -q "$username"; then
        log_debug "User $username already exists at $PORTAINER_ROOTURL"
      else
        if [ "$password" = "x" ]; then
          password=$(pwdgen 24)
          log_info "Generated password $password for user $username"
        fi
        log_debug "Creating user $username"
        id=$(portainer_api POST /users \
                --data "{\"username\": \"$username\", \"password\": \"$password\", \"role\": $role}" |
              jq -cr '.Id')
        log_info "Created user $username with identifier $id"
      fi

      printf %s\\n "$teams" | tr  ',' '\n' | while IFS= read -r teamspec; do
        team=$(printf %s\\n "$teamspec" | cut -d "/" -f 1)
        role=$(printf %s\\n "$teamspec" | cut -d "/" -f 2); # 1: leader, 2: member
        [ "$role" = "$team" ] && role=2; # Default role is member
        tid=$(team_create "$team")
        portainer_api POST /team_memberships \
            --data "{\"userId\": $id, \"teamID\": $tid, \"role\": $role}" > /dev/null
      done
    fi
  done
fi

printf %s\\n "$ZAP_FILES" | tr  ',' '\n' | while IFS= read -r fpath; do
  if [ -f "$fpath" ]; then
    log_info "Removing temporary file $fpath"
    rm -f "$fpath"
  fi
done