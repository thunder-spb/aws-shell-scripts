#!/bin/bash


set_debug() {
  DEBUG=1
  set -x
}

if [[ ! -z ${V} || ! -z ${DEBUG} ]]; then
  set_debug
fi

AWS_REGIONS_ALL="us-east-1 us-east-2 us-west-1 us-west-2 eu-central-1 eu-west-1 eu-west-2 ap-northeast-1 ap-northeast-2 ap-southeast-1 ap-southeast-2 ap-south-1 ca-central-1 cn-north-1 cn-northwest-1 eu-north-1 me-south-1 sa-east-1 il-central-1"

# Define color codes
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

BOLD='\033[1m'
NORMAL='\033[0m'

# Define icons
CHECK_MARK="\xE2\x9C\x94"
CROSS_MARK="\xE2\x9D\x8C"
INFO="\xF0\x9F\x93\xA6"
ARROW_UP="\xE2\x87\xB8"

function log_error() {
  echo -e "${RED}${CROSS_MARK} ${BOLD}ERROR${NORMAL}${RED} [$(date +'%Y-%m-%dT%H:%M:%S%z')]:${NC} $*"
}

function log_fatal() {
  echo -e "${RED}${CROSS_MARK} ${BOLD}FATAL${NORMAL}${RED} [$(date +'%Y-%m-%dT%H:%M:%S%z')]:${NC} $*"
  exit 1
}

function log_ok() {
  echo -e "${GREEN}${CHECK_MARK} ${BOLD}OK${NORMAL}${GREEN} [$(date +'%Y-%m-%dT%H:%M:%S%z')]:${NC} $*"
}

function log_warn() {
  echo -e "${YELLOW}${ARROW_UP} ${BOLD}WARN${NORMAL}${YELLOW} [$(date +'%Y-%m-%dT%H:%M:%S%z')]:${NC} $*"
}

function log_info() {
  echo -e "${BLUE}${INFO} ${BOLD}INFO${NORMAL}${BLUE} [$(date +'%Y-%m-%dT%H:%M:%S%z')]:${NC} $*"
}

## Deprecated functions
error() {
  log_warn "Deprecated ${BOLD}'error'${NC} function called"
  log_fatal "$1"
}

info() {
  log_info "$1"
  log_warn "Deprecated ${BOLD}'info'${NC} function called"
}
###

AWS_CONFIG_FILE=${AWS_CONFIG_FILE:-$HOME/.aws/config}

IS_SOURCED=0
if [ -n "$ZSH_VERSION" ]; then
  case $ZSH_EVAL_CONTEXT in *:file) IS_SOURCED=1;; esac
elif [ -n "$KSH_VERSION" ]; then
  [ "$(cd -- "$(dirname -- "$0")" && pwd -P)/$(basename -- "$0")" != "$(cd -- "$(dirname -- "${.sh.file}")" && pwd -P)/$(basename -- "${.sh.file}")" ] && IS_SOURCED=1
elif [ -n "$BASH_VERSION" ]; then
  (return 0 2>/dev/null) && IS_SOURCED=1
else # All other shells: examine $0 for known shell binary filenames.
     # Detects `sh` and `dash`; add additional shell filenames as needed.
  case ${0##*/} in sh|-sh|dash|-dash) IS_SOURCED=1;; esac
fi

if [[ ${IS_SOURCED} == "0" ]]; then
  error "You should not run this script directly!"
fi

IS_FZF=false
if [[ -t 1 && "$(type fzf &>/dev/null; echo $?)" -eq 0 ]]; then
  IS_FZF=true
fi

# This function is a wrapper around the `fzf` command with predefined options to customize its appearance and behavior.
# It displays a fuzzy finder with a reverse layout, border, and custom color for labels.
# The preview window is positioned on the right side with a line border.
# This function takes additional arguments to further configure `fzf`.
__fzf_base_fzf() {
  fzf --height 50% --tmux 90%,70% \
    --layout reverse --min-height 20+ --border \
    --header-border horizontal \
    --border-label-pos 2 \
    --color 'label:white' \
    --no-multi \
    --preview-window 'right,80%' --preview-border line "$@"
}

## Commmon functions

check_token_expiration() {
  aws sts get-caller-identity --profile ${AWS_PROFILE} &> /dev/null
  return $?
}

check_sso_login () {
  check_token_expiration
  # $? is the exit code of the last statement
  if [ "$?" == 0 ]; then
      # auth is valid
      log_ok "Your sso token is valid, continuing"
  else
    if [ -t 1 ] ; then
      log_info "Found that this is an interactive terminal, will run the sso login"
      # auth needs refresh
      aws sso login --profile ${AWS_PROFILE} --region ${AWS_REGION}
      if [ "$?" != 0 ]; then
        log_fatal "You didnt login, exiting!"
      fi
    else
      # is cron
      log_fatal "Not in a tty, gracefully exiting due to no active SSO login. Check that your logged in via SSO, or have perms via IAM already setup";
    fi
  fi
}

check_aws_region() {
  if [[ -z ${AWS_REGION} ]]; then
    if ${IS_FZF}; then
      choose_aws_region_interactive
    else
      log_fatal "AWS Region to use not defined!"
    fi
  elif ! echo "${AWS_REGIONS_ALL}" | grep -q "${AWS_REGION}"; then
    log_fatal "Invalid AWS Region: ${AWS_REGION}"
  fi
}

aws_region_list() {
  echo "${AWS_REGIONS_ALL}"
}

# Interactively choose an AWS region using fzf.
# Retrieves and lists all available AWS regions, and then uses fzf to prompt the user to select one of the options.
# If the user does not select an option, the function will exit with a non-zero status code.
choose_aws_region_interactive() {
  local choice
  choice="$(echo ${AWS_REGIONS_ALL} | tr " " "\n" | __fzf_base_fzf \
    --height 90% \
    --border-label " 📔 AWS Region " \
    --tiebreak begin
  )"
  if [[ -z "${choice}" ]]; then
    log_fatal "You did not choose any of the options"
  else
    AWS_REGION="${choice}"
  fi
}

check_aws_profile() {
  if [[ -z ${AWS_PROFILE} ]]; then
    if ${IS_FZF}; then
      choose_profile_interactive
    else
      log_fatal "AWS Profile to use not defined!"
    fi
  fi
}

choose_profile_interactive() {
  type aws-profiles &>/dev/null || { log_fatal "aws-profiles helper script is not available."; }
  local choice
  choice="$(FZF_DEFAULT_COMMAND="aws-profiles" \
    __fzf_base_fzf --height 90% --ansi \
        --border-label " 📔 Profile names " \
        --header "SHIFT-UP/DOWN: scroll up/down" \
        --header-first \
        --tiebreak begin \
        --bind "shift-left:preview-half-page-up,shift-right:preview-half-page-down" \
        --preview-window right,60%,wrap \
        --preview-border rounded \
        --preview-label " 📜 Profile configuration " \
        --preview-label-pos 0 \
        --preview "perl -00 -ne 'print if /\[profile {}\]/' ${AWS_CONFIG_FILE}" || true)"
  if [[ -z "${choice}" ]]; then
    log_fatal "You did not choose any of the options"
  else
    AWS_PROFILE="${choice}"
  fi
}

check_aws_sso_session() {
  if [[ -z ${AWS_SSO_SESSION_NAME} ]]; then
    if ${IS_FZF}; then
      choose_sso_session_interactive
    else
      log_fatal "AWS Profile to use not defined!"
    fi
  fi
}

choose_sso_session_interactive() {
  type aws-sessions &>/dev/null || { log_fatal "aws-sessions helper script is not available."; }
  local choice
  choice="$(FZF_DEFAULT_COMMAND="aws-sessions" \
    fzf --ansi --preview "perl -00 -ne 'print if /\[sso-session {}\]/' ${AWS_CONFIG_FILE}" || true)"
  if [[ -z "${choice}" ]]; then
    log_fatal "You did not choose any of the options"
  else
    AWS_SSO_SESSION_NAME="${choice}"
  fi
}

get_section_names() {
  _TYPE=${1:-profile}
  AWS_CONFIG_FILE=${AWS_CONFIG_FILE:-$HOME/.aws/config}

  [[ -r "${AWS_CONFIG_FILE}" ]] || exit 1
  sed -n -e 's/^\['${_TYPE}'[[:space:]]\(.*\)\]$/\1/p' ${AWS_CONFIG_FILE}
}

startsWith() {
  { case $1 in "$2"*) true;; *) false;; esac; }
}


choose_eks_cluster_interactive() {
  local clusters=$(aws eks list-clusters --profile ${AWS_PROFILE} --region ${AWS_REGION} | jq -r '.clusters[]')
  if [ -z "${clusters}" ]; then log_fatal "No clusters found for ${AWS_PROFILE} in region ${AWS_REGION}"; fi
  local choice
  if [[ "$(echo "${clusters}" | wc -l)" -gt 1 ]]; then
    choice="$(echo "$clusters" | fzf --ansi --no-preview --header "clusters" --header-first || true)"
  else
    choice=$clusters
  fi
  if [[ -z "${choice}" ]]; then
    log_fatal "You did not choose any of the options"
    exit 1
  else
    AWS_EKS_CLUSTER_NAME="${choice}"
  fi
}


# function iniget() {
#   if [[ $# -lt 2 || ! -f $1 ]]; then
#     echo "usage: iniget <file> [--list|<section> [key]]"
#     return 1
#   fi
#   local inifile=$1

#   if [ "$2" == "--list" ]; then
#     for section in $(cat $inifile | grep "\[" | sed -e "s#\[profile ##g" | sed -e "s#\]##g"); do
#       echo $section
#     done
#     return 0
#   fi

#   local section=$2
#   local key
#   [ $# -eq 3 ] && key=$3

#   # https://stackoverflow.com/questions/49399984/parsing-ini-file-in-bash
#   # This awk line turns ini sections => [section-name]key=value
#   local lines=$(awk '/\[/{prefix=$0; next} $1{print prefix $0}' $inifile)
#   for line in $lines; do
#     if [[ "$line" = \["profile "$section\]* ]]; then
#       local keyval=$(echo $line | sed -e "s/^\[profile $section\]//")
#       if [[ -z "$key" ]]; then
#         echo $keyval
#       else
#         if [[ "$keyval" = $key=* ]]; then
#           echo $(echo $keyval | sed -e "s/^$key=//")
#         fi
#       fi
#     fi
#   done
# }
