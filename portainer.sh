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
  $MG_CMDNAME will initialise a portainer installation from environment
  variables and an option JSON file
Usage:
  $MG_CMDNAME [-option arg] -- [portainer CLI options]
  where all dash-led single/double options are as follows.
    -s | --settings
      Path to settings file in JSON format. This needs to contain all
      possible keys and their values. Defaults to settings.json in same
      directory as this script.
    -p | --port | --port-number
      Port number at which portainer should listen for UI and API calls.
      Defaults to 9000
    -t | --teams
      Comma separated list of teams to create. When the value starts with
      a @ sign, the remaining should be the path to a file containing team
      names, one per line (empty lines and lines starting with a # ignored)
    -u | --users
      Path to a file containing a list of users to create. Apart from comments
      and blank lines, lines should contain colon separated fields:
      username:password:role:teams. When password is x, one will be generated.
      role is the role of the user in Portainer: 1: admin, 2: regular user.
      teams is a colon separated list of teams specifications: team/role, where
      the role defaults to 2 (regular member), otherwise 1: leader.
    --passwd | --password
      Cleartext password, you should probably not use this. When empty a
      password will be generated unless a file is specified.
    --passwd-file | --password-file
      Path to a file containing the admin user password, usually a Docker
      secret or similar.
    --portainer | --binary | --bin
      Name or path to binary for portainer, defaults to: portainer
    -v | --verbose
      Verbosity level. From error down to debug.
    -h | --help
      Print this help and exit
Description:
  Will replace all environment variables which name starts with PORTAINER_
  and the rest is constructed as the JSON path, all in uppercase, with the .
  replaced by a _ in the settings.

  Once settings have been generated, portainer will be started and settings will
  be applied, and teams and users created. Everything after the -- is blindly
  passed to portainer, but you shouldn't pass the option --bind or the options
  to set the password (no check is performed!).
"

# Clear-text password for the user. Try avoiding tu use this!
PORTAINER_ADMIN_PASSWORD=${PORTAINER_ADMIN_PASSWORD:-}

# Path to a file containing the password for the user.
PORTAINER_ADMIN_PASSWORD_FILE=${PORTAINER_ADMIN_PASSWORD_FILE:-}

# Path to settings file. This should contain a JSON object that can be used to
# send to the /settings API endpoint. The value of environment starting with the
# prefix PORTAINER_PREFIX might override the content of this file before sending
# settings to portainer.
PORTAINER_SETTINGS=${PORTAINER_SETTINGS:-${PORTAINER_ROOTDIR%/}/settings.json}

# Maximum number of numbered environment variables supported
PORTAINER_MAX=${PORTAINER_MAX:-10}

# The prefix to add when looking for environment variables that will override
# settings.
PORTAINER_PREFIX=${PORTAINER_PREFIX:-"PORTAINER_"}

# Comma separated list of teams to setup. This can be used when setting up LDAP
# and arranging for group membership to transfer into team membership
# autmatically. When first letter is a @, the remaining will be the path to a
# file. One team per line, empty lines and lines starting with a hash-mark will
# be ignored.
PORTAINER_TEAMS=${PORTAINER_TEAMS:-}

# Port number where portainer should be listening for UI and API calls.
PORTAINER_PORT_NUMBER=${PORTAINER_PORT_NUMBER:-"9000"}

# Path to portainer binary, will be looked from $PATH
PORTAINER_BIN=${PORTAINER_BIN:-"portainer"}

# Path to a user specification file. Empty lines and lines starting with a
# hash-mark will be ignored. Otherwise, colon separated fields:
# username:password:role:teams, where teams is a colon separated list of teams.
# When password is an x, a password will be generated.
PORTAINER_USERS=${PORTAINER_USERS:-}

while [ $# -gt 0 ]; do
  case "$1" in
    -p | --port)
      PORTAINER_PORT_NUMBER=$2; shift 2;;
    --port=*)
      PORTAINER_PORT_NUMBER="${1#*=}"; shift 1;;

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

    -t | --teams)
      PORTAINER_TEAMS=$2; shift 2;;
    --teams=*)
      PORTAINER_TEAMS="${1#*=}"; shift 1;;

    -u | --users)
      PORTAINER_USERS=$2; shift 2;;
    --users=*)
      PORTAINER_USERS="${1#*=}"; shift 1;;

    --portainer | --binary | --bin)
      PORTAINER_BIN=$2; shift 2;;
    --portainer=* | --binary=* | --bin=*)
      PORTAINER_BIN="${1#*=}"; shift 1;;

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

if ! command -v gron >&2 >/dev/null; then
  die "This script requires an installation of gron to manipulate JSON"
fi
if ! command -v "${PORTAINER_BIN}" >&2 >/dev/null; then
  die "No portainer binary accessible at $PORTAINER_BIN!"
fi

# Generate a random password as long as $1 (defaults to 30 chars)
pwdgen() {
  strings < /dev/urandom | grep -o '[[:alnum:]]' | head -n "${1:-30}" | tr -d '\n'; echo
}

# Convert the incoming string to the name of an environment variable. The prefix
# will always be appended, all characters will be converted to uppercase and all
# dots replaced by an _
varname() {
  printf %s_%s\\n "${PORTAINER_PREFIX%_}" "$1" |
    tr '[:lower:]' '[:upper:]' |
    tr '.' '_'
}

gron_statement() {
  if [ -z "$1" ]; then
    printf "json = %s;\\n" "$2"
  else
    printf "json.%s = %s;\\n" "$1" "$2"
  fi
}
# Generate gron-compatible output
# $1 is the environment variable name
# $2 is the gron setting value (without json.)
# $3 is the previous value from gron output, for type decision
# $4 is 1 or 0 (default). When 1 output incoming value when no envvar exists
gron_output() {
  if env | grep -qE "^${1}="; then
    envval=$(eval "echo \"\$$1\"")
    if printf %s\\n "$3" | grep -q '^"'; then
      gron_statement "$2" "\"$envval\""
    else
      gron_statement "$2" "$envval"
    fi
  elif env | grep -qE "^${1}_FILE="; then
    fname=$(eval "echo \"\$${vname}_FILE\"")
    if ! [ -f "$fname" ]; then
      log_error "File $fname pointed at by ${vname}_FILE does not exist!"
    else
      envval=$(cat "$fname")
      if printf %s\\n "$3" | grep -q '^"'; then
        gron_statement "$2" "\"$envval\""
      else
        gron_statement "$2" "$envval"
      fi
    fi
  elif [ "${4:-0}" = "1" ]; then
    gron_statement "$2" "$3"
  fi
}

# Sort out passwords. Arrange for the variable PORTAINER_PASSWORD to contain the
# password for the administrator in cleartext, whenever necessary. This is
# unsafe, so warning are printed out!
if [ -n "$PORTAINER_ADMIN_PASSWORD_FILE" ] && [ -r "$PORTAINER_ADMIN_PASSWORD_FILE" ]; then
  log_debug "Running in safe mode, with admin password accessible from $PORTAINER_ADMIN_PASSWORD_FILE"
elif [ -z "$PORTAINER_ADMIN_PASSWORD" ]; then
  if ! command -v htpasswd >&2 >/dev/null; then
    die "This script requires an installation of htpasswd to encrypt passwords"
  fi
  PORTAINER_PASSWORD=$(pwdgen 24)
  log_notice "Generated admin password, you will see it once and only once: $PORTAINER_PASSWORD"
  PORTAINER_ADMIN_PASSWORD=$(htpasswd -nbB admin "$PORTAINER_PASSWORD" | cut -d ":" -f 2)
else
  if printf %s\\n "$PORTAINER_ADMIN_PASSWORD" | grep -qE '^[$]2[abxy]?[$](?:0[4-9]|[12][0-9]|3[01])[$][./0-9a-zA-Z]{53}$'; then
    die "You have specified a bcrypt password, a good choice for security, BUT a bad choice as API access will not be possible! Consider using --password-file instead!"
  else
    log_warning "Running with cleartext password is a security risk!"
    PORTAINER_PASSWORD=$PORTAINER_ADMIN_PASSWORD
    PORTAINER_ADMIN_PASSWORD=$(htpasswd -nbB admin "$PORTAINER_ADMIN_PASSWORD" | cut -d ":" -f 2)
  fi
fi

tmp_fname=$(mktemp -t "${MG_APPNAME}_gron_XXXXXX")
log_debug "Converting existing settings to gron at $tmp_fname"
gron "$PORTAINER_SETTINGS" | while IFS= read -r line; do
  if [ -n "$line" ]; then
    setter=$(printf %s\\n "$line" | sed -E 's/^json.?(.*)[[:space:]]+=[[:space:]]+([^;]*);$/\1/')
    value=$(printf %s\\n "$line" | sed -E 's/^json.?(.*)[[:space:]]+=[[:space:]]+([^;]*);$/\2/')
    log_trace "Analysing gron: $setter = $value"
    if printf %s\\n "$setter" | grep -qE '\[[0-9]+\]'; then
      start=$(printf %s\\n "$setter" | grep -Eo '\[[0-9]+\]' | grep -Eo '[0-9]+')
      for i in $(seq "$start" "$PORTAINER_MAX"); do
        n_setter=$(printf %s\\n "$setter" | sed -E "s/\[[0-9]+\]/\[${i}\]/")
        b_name=$(printf %s\\n "$setter" | sed -E "s/\[[0-9]+\]/${i}/")
        n_vname=$(varname "$b_name")
        gron_output "$n_vname" "$n_setter" "$value" "$(test "$i" = "$start" && echo 1 || echo 0)"
      done
    else
      vname=$(varname "$setter")
      gron_output "$vname" "$setter" "$value" 1
    fi
  fi
done > "$tmp_fname"

# Generate JSON from the recreated internal gron representation in $tmp_fname
# using the --ungron option. Remove the temporary respresentation once done.
tmp_settings=$(mktemp -t "${MG_APPNAME}_json_XXXXXX")
log_debug "Generating temporary settings file at $tmp_settings"
gron --ungron "$tmp_fname" > "$tmp_settings"
rm -rf "$tmp_fname"

# Start a list of files to remove once done. Removal will be performed by the
# process that finalise the initialisation.
ZAP_FILES=$tmp_settings

# Convert comma-separated list of teams to a file containing the name of the
# teams, one by line.
if [ -n "$PORTAINER_TEAMS" ]; then
  if [ "$(printf %s\\n "$PORTAINER_TEAMS" | cut -c 1)" = "@" ]; then
    PORTAINER_TEAMS=$(printf %s\\n "$PORTAINER_TEAMS" | cut -c 2-)
  else
    tmp_teams=$(mktemp -t "${MG_APPNAME}_teams_XXXXXX")
    printf %s\\n "$PORTAINER_TEAMS" | tr  ',' '\n' > "$tmp_teams"
    PORTAINER_TEAMS=$tmp_teams
    ZAP_FILES="${ZAP_FILES},$tmp_teams"
  fi
fi

# Start a process that will finalise Portainer initialisation in the background.
# The first thing that this process will do is waiting for portainer to be up
# and running.
if [ -n "$PORTAINER_ADMIN_PASSWORD_FILE" ]; then
  "${PORTAINER_ROOTDIR%/}/settings.sh" \
    --portainer="http://localhost:${PORTAINER_PORT_NUMBER}/" \
    --password-file="$PORTAINER_ADMIN_PASSWORD_FILE" \
    --teams-file="$PORTAINER_TEAMS" \
    --users-file="$PORTAINER_USERS" \
    --remove="$ZAP_FILES" \
    --verbose="$MG_VERBOSITY" \
    --settings="$tmp_settings" &
else
  "${PORTAINER_ROOTDIR%/}/settings.sh" \
    --portainer="http://localhost:${PORTAINER_PORT_NUMBER}/" \
    --password="$PORTAINER_PASSWORD" \
    --teams-file="$PORTAINER_TEAMS" \
    --users-file="$PORTAINER_USERS" \
    --remove="$ZAP_FILES" \
    --verbose="$MG_VERBOSITY" \
    --settings="$tmp_settings" &
fi

# Now replace this process with portainer itself, passing all options that were
# after the --
log_info "Running ${PORTAINER_BIN} $* --bind=:${PORTAINER_PORT_NUMBER} (password info omitted) from $(pwd)"
if [ -n "$PORTAINER_ADMIN_PASSWORD_FILE" ]; then
  exec ${PORTAINER_BIN} "$@" \
        --bind=":${PORTAINER_PORT_NUMBER}" \
        --admin-password-file="$PORTAINER_ADMIN_PASSWORD_FILE"
else
  exec ${PORTAINER_BIN} "$@" \
        --bind=":${PORTAINER_PORT_NUMBER}" \
        --admin-password="$PORTAINER_ADMIN_PASSWORD"
fi
