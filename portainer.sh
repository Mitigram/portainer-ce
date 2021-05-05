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
  variables.
Usage:
  $MG_CMDNAME [-option arg]...
  where all dash-led single/double options are as follows.
    -s | --settings
        Path to settings file in JSON format. This needs to contain all
        possible keys and their values. Defaults to settings.json in same
        directory as this script.
    -v | --verbose
        Verbosity level. From error down to debug.
    -h | --help
        Print this help and exit
Description:
  Will replace all environment variables which name starts with PORTAINER_
  and the rest is constructed as the JSON path, all in uppercase, with the .
  replaced by a _ in the settings."

PORTAINER_ADMIN_PASSWORD=${PORTAINER_ADMIN_PASSWORD:-}
PORTAINER_ADMIN_PASSWORD_FILE=${PORTAINER_ADMIN_PASSWORD_FILE:-}

PORTAINER_SETTINGS=${PORTAINER_SETTINGS:-${PORTAINER_ROOTDIR%/}/settings.json}

# Maximum number of numbered environment variables supported
PORTAINER_MAX=${PORTAINER_MAX:-10}

PORTAINER_PREFIX=${PORTAINER_PREFIX:-"PORTAINER_"}

while [ $# -gt 0 ]; do
  case "$1" in
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

# Sort out passwords. Arrange for the variable PORTAINER_PASSWORD to always
# contain the password for the administrator in cleartext, whenever possible.
if [ -n "$PORTAINER_ADMIN_PASSWORD_FILE" ] && [ -r "$PORTAINER_ADMIN_PASSWORD_FILE" ]; then
  PORTAINER_PASSWORD=$(cat "$PORTAINER_ADMIN_PASSWORD_FILE")
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
    PORTAINER_PASSWORD=$PORTAINER_ADMIN_PASSWORD
    PORTAINER_ADMIN_PASSWORD=$(htpasswd -nbB admin "$PORTAINER_PASSWORD" | cut -d ":" -f 2)
  fi
fi

log_debug "Converting existing settings to gron"
tmp_fname=$(mktemp)
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

gron -u "$tmp_fname"
rm -rf "$tmp_fname"