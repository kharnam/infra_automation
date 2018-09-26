#!/usr/bin/env bash

# ------------------------------------------------------------------------------------
# General runtime setup

export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8

# Exit on error. Append "|| true" if you expect an error.
set -o errexit
# Exit on error inside any functions or subshells.
set -o errtrace
# Do not allow use of undefined vars. Use ${VAR:-} to use an undefined VAR
set -o nounset
# Catch the error in case mysqldump fails (but gzip succeeds) in `mysqldump |gzip`
set -o pipefail
# Turn on traces, useful while debugging but commented out by default
# set -o xtrace
# Produce a trace of every command executed run
# set -o verbose

# Setup working directory
TMPDIR="/tmp/$$"
[[ ! -f ${TMPDIR} ]] && mkdir -p ${TMPDIR} || $( echo "Cannot create TMPDIR ${TMPDIR}" >&2; exit 1 )

# Set magic variables for current file, directory, os, etc.
__dir="$(cd "$(dirname "${BASH_SOURCE[${__tmp_source_idx:-0}]}")" && pwd)"
__file="${__dir}/$(basename "${BASH_SOURCE[${__tmp_source_idx:-0}]}")"
__base="$(basename "${__file}" .sh)"

function sysinfo(){
    level=$1
    echo | tee -a ${LOG_FILE} 2>&1
    info "=====>>  SYSTEM INFORMATION  <<====="
    case "$1" in
        1)
            info "OS Details --> $(uname -a)"
            ;;
        2)
            info "OS Details --> $(uname -a)"
            info "Execution directory --> ${__dir}"
            info "Executed script file path --> ${__file}"
            info "Executed script file name --> ${__base}"
            ;;
        *)
            critical "Wrong system info level!!!"
    esac
}

# ------------------------------------------------------------------------------------
# Logging facility setup

# Define the environment variables (and their defaults) that this script depends on
LOG_LEVEL="${LOG_LEVEL:-7}" # 7 = debug -> 0 = emergency
NO_COLOR="${NO_COLOR:-}"    # true = disable color. otherwise autodetected

# Setup log directory
LOG_DIR="/tmp/logs/"
LOG_FILE="/tmp/logs/infra_automation.log"

[[ ! -f ${LOG_FILE} ]] && mkdir -p ${LOG_DIR} && $( touch ${LOG_FILE} || $( echo "Cannot write to ${LOG_FILE}" >&2; exit 1 ) )

# Option to play with different streams switchovers
# exec 3>&1 1>>${LOG_FILE} 2>&1

function log () {
    local log_level="${1}"
    shift

    # shellcheck disable=SC2034
    local color_debug="\x1b[35m"
    # shellcheck disable=SC2034
    local color_info="\x1b[32m"
    # shellcheck disable=SC2034
    local color_notice="\x1b[34m"
    # shellcheck disable=SC2034
    local color_warning="\x1b[33m"
    # shellcheck disable=SC2034
    local color_error="\x1b[31m"
    # shellcheck disable=SC2034
    local color_critical="\x1b[1;31m"
    # shellcheck disable=SC2034
    local color_alert="\x1b[1;33;41m"
    # shellcheck disable=SC2034
    local color_emergency="\x1b[1;4;5;33;41m"

    local colorvar="color_${log_level}"

    local color="${!colorvar:-${color_error}}"
    local color_reset="\x1b[0m"

    if [[ "${NO_COLOR:-}" = "true" ]] || ( [[ "${TERM:-}" != "xterm"* ]] && [[ "${TERM:-}" != "screen"* ]] ) || [[ ! -t 2 ]]; then
    if [[ "${NO_COLOR:-}" != "false" ]]; then
      # Don't use colors on pipes or non-recognized terminals
      color=""; color_reset=""
    fi
    fi

    # all remaining arguments are to be printed
    local log_line=""

    while IFS=$'\n' read -r log_line; do
    echo -e "$(date -u +"%Y-%m-%d %H:%M:%S UTC") ${color}$(printf "[%9s]" "${log_level}")${color_reset} ${log_line}" | tee -a ${LOG_FILE} 2>&1
    done <<< "${@:-}"
}

function emergency () {                                  log emergency "${@}"; exit 1; }
function alert ()     { [[ "${LOG_LEVEL:-0}" -ge 1 ]] && log alert "${@}"; true; }
function critical ()  { [[ "${LOG_LEVEL:-0}" -ge 2 ]] && log critical "${@}"; true; }
function error ()     { [[ "${LOG_LEVEL:-0}" -ge 3 ]] && log error "${@}"; true; }
function warning ()   { [[ "${LOG_LEVEL:-0}" -ge 4 ]] && log warning "${@}"; true; }
function notice ()    { [[ "${LOG_LEVEL:-0}" -ge 5 ]] && log notice "${@}"; true; }
function info ()      { [[ "${LOG_LEVEL:-0}" -ge 6 ]] && log info "${@}"; true; }
function debug ()     { [[ "${LOG_LEVEL:-0}" -ge 7 ]] && log debug "${@}"; true; }

# requires `set -o errtrace`
err_report() {
    local error_code
    error_code=${?}
    error "Error in ${__file} in ${1}"
    exit ${error_code}
}

# ------------------------------------------------------------------------------------
# Signal trapping and backtracing

# trap ctrl-c and call ctrl_c()
trap ctrl_c INT
function ctrl_c() {
    echo "** Trapped CTRL-C"
}
# trap script EXIT and call cleanup_before_exit()
# trap cleanup EXIT


# ====================================================================================
# Core functionality
# ====================================================================================

# ------------------------------------------------------------------------------------
# System functions

function yesno {
    while true; do
        read -p "Continue? [Yes/No]: " yn
        case $yn in
            [Yy]* ) break;;
            [Nn]* ) exit;;
            * ) echo "Please answer [Y]es or [N]o.";;
        esac
    done
}

function fail {
  echo $1 >&2
  exit 1
}

function retry {
  local n=1
  local max=3
  local delay=10
  while true; do
    "$@" && break || {
      if [[ $n -lt $max ]]; then
        ((n++))
        critical "Failed to restart NGINX! Attempt $n/$max:"
        sleep $delay;
      else
        emergency "NGINX restart failed after $n attempts."
      fi
    }
  done
}


# ------------------------------------------------------------------------------------
# Packer section

PACKER_BASE_DIR="${HOME}/dev/sandbox/infra_automation/packer"
TERRAFORM_BASE_DIR="${HOME}/dev/sandbox/infra_automation/terraform/gcp_tf_test_deploy"
GCP_CRED_FILE="${HOME}/.gcp/adept-cascade-216916-a0765ecc09b2.json"
PROJECT_ID="adept-cascade-216916"
IMAGE_NAME="sergey-test-$(date +%s)"

function packer_validate(){
    notice "Running Packer validation..."
    PACKER_LOG=1 \
    $PACKER_BASE_DIR/packer validate \
    -var "region=us-east1" \
    -var "source_image=centos-7-v20180911" \
    -var "image_name=$IMAGE_NAME" \
    -var "machine_type=f1-micro" \
    -var "zone=us-east1-b" \
    -var "service_account_json=$GCP_CRED_FILE" \
    -var "project_id=$PROJECT_ID" \
    $PACKER_BASE_DIR/templates/pckr_tmpl_gcp_centos_nginx.json  \
    | tee -a ${LOG_FILE} 2>&1 > /dev/null || emergency "Failed to validate Packer file!"
    notice "Packer validation passed successfully."
}

function packer_build() {
    notice "Running Packer build..."
    PACKER_LOG=1 \
    $PACKER_BASE_DIR/packer build \
    -var "region=us-east1" \
    -var "source_image=centos-7-v20180911" \
    -var "image_name=$IMAGE_NAME" \
    -var "machine_type=f1-micro" \
    -var "zone=us-east1-b" \
    -var "service_account_json=$GCP_CRED_FILE" \
    -var "project_id=$PROJECT_ID" \
    $PACKER_BASE_DIR/templates/pckr_tmpl_gcp_centos_nginx.json  \
    | tee -a ${LOG_FILE} 2>&1 > /dev/null || emergency "Failed to build with Packer!"
    notice "Packer build passed successfully."
}

function terraform_init() {
    info "Starting Terraform initialization..."
    cd $TERRAFORM_BASE_DIR
    terraform init -var "image_name=$IMAGE_NAME" | tee -a ${LOG_FILE} 2>&1 > /dev/null || emergency "Failed to initialize Terraform!"
    notice "Terraform initialization passed successfully."
}

function terraform_plan() {
    info "Starting Terraform planning..."
    cd $TERRAFORM_BASE_DIR
    terraform plan -var "image_name=$IMAGE_NAME" | tee -a ${LOG_FILE} 2>&1 > /dev/null || emergency "Failed to plan Terraform!"
    notice "Terraform planning passed successfully."
}

function terraform_apply() {
    info "Starting Terraform application..."
    cd $TERRAFORM_BASE_DIR
    terraform apply -var "image_name=$IMAGE_NAME" -auto-approve | tee -a ${LOG_FILE} 2>&1 > /dev/null || emergency "Failed to apply Terraform!"
    notice "Terraform application passed successfully."
}

# ------------------------------------------------------------------------------------
# Teardown section

function cleanup(){
	echo | tee -a ${LOG_FILE} 2>&1
    info "=====>>  Starting clean up procedure...  <<====="
}


# ------------------------------------------------------------------------------------
# Main function

function main(){
    echo | tee -a ${LOG_FILE}
    info "=====   Starting script < ${__base} > execution...   ====="
    sysinfo 2

    packer_validate
    yesno
    packer_build
    yesno
    terraform_init
    yesno
    terraform_plan
    yesno
    terraform_apply

    # system cleanup
    # cleanup

    echo | tee -a ${LOG_FILE}
    info "=====   Congrats! It looks we've done successfully ;)   ====="
    echo -e "\n\n\n" | tee -a ${LOG_FILE}
}
main