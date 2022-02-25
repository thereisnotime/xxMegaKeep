#!/usr/bin/env bash
#shellcheck disable=SC2034,SC2046,SC2002,SC2181,SC2155
###########################
# TODO: Add proper syslog logging;
# TODO: Add proper error handling;
# TODO: Add parallelism mechanism;
# TODO: Add throttling options;
# TODO: Add options for config files;
# TODO: Find problem with multiple loops;
# TODO: Add mechanism for notification hooks (webhooks/Telegram/etc);
###########################
_SCRIPT_VERSION="1.3"
_SCRIPT_NAME="xxMegaKeep"


###########################
# Configuration
###########################
if [ -f .env ]; then export $(cat .env | sed 's/#.*//g' | xargs); fi
ACCOUNTS_FILE=${ACCOUNTS_FILE:-'./.accounts'}


###########################
# Error Handling
###########################
set -E -o functrace
trap 'failure "${BASH_LINENO[*]}" "$LINENO" "${FUNCNAME[*]:-script}" "$?" "$BASH_COMMAND"' ERR


###########################
# Helpers
###########################
_BRed='\e[1;31m'    # Red
_BYellow='\e[1;33m' # Yellow
_BBlue='\e[1;34m'   # Blue
_BWhite='\e[1;37m'  # White
_NC="\e[m"          # Color Reset

function log() {
    local _message="$1"
    local _level="$2"
    local _nl="\n"
    _timestamp=$(date +%d.%m.%Y-%H:%M:%S-%Z)
    case $(echo "$_level" | tr '[:upper:]' '[:lower:]') in
    "info" | "information")
        echo -ne "${_BWhite}[INFO][${_SCRIPT_NAME} ${_SCRIPT_VERSION}][${_timestamp}]: ${_message}${_NC}${_nl}"
        ;;
    "warn" | "warning")
        echo -ne "${_BYellow}[WARN][${_SCRIPT_NAME} ${_SCRIPT_VERSION}][${_timestamp}]: ${_message}${_NC}${_nl}"
        ;;
    "err" | "error")
        echo -ne "${_BRed}[ERR][${_SCRIPT_NAME} ${_SCRIPT_VERSION}][${_timestamp}]: ${_message}${_NC}${_nl}"
        ;;
    *)
        echo -ne "${_BBlue}[UNKNOWN][${_SCRIPT_NAME} ${_SCRIPT_VERSION}][${_timestamp}]: ${_message}${_NC}${_nl}"
        ;;
    esac
}
function failure() {
    local _lineno="$2"
    local _fn="$3"
    local _exitstatus="$4"
    local _msg="$5"
    local _lineno_fns="${1% 0}"
    if [[ "$_lineno_fns" != "0" ]]; then _lineno="${_lineno} ${_lineno_fns}"; fi
    log "Error in ${BASH_SOURCE[1]}:${_fn}[${_lineno}] Failed with status ${_exitstatus}: ${_msg}" "ERROR"
}

###########################
# Function
###########################
function check_if_command_exists() {
    local _command="$1"
    if ! command -v "$_command" >/dev/null 2>&1; then
        log "Command '${_command}' not found. Aborting." "ERROR"
        exit 1
    fi
}
function pre_checks() {
    check_if_command_exists "megatools"
}
function keep_accounts() {
    local _accounts_file="$1"
    local _local_location="./xxMegaKeep.txt"
    local _remote_location="/Root/xxMegaKeep.txt"
    local _failed_accounts=""
    local _total_space=0
    local _total_used=0
    local _total_free=0
    declare -A _accounts
    declare -i count=0
    declare -i total_count=0

    while read -r label number; do
        # Verify inputs
        if [[ ${#label} -lt 3 ]]; then
            log "Account name '${label}' is too short. Skipping." "WARN"
            continue
        fi
        if [[ ${#number} -lt 3 ]]; then
            log "Password of '${label}' is too short. Skipping." "WARN"
            continue
        fi
        _accounts[$count,0]="$label"; _accounts[$count,1]="$number"
        count=$(( count + 1 ))
        total_count=$(( total_count + 1 ))
    done < "$_accounts_file"

    log "Loaded ${_BBlue}${count}${_BWhite} accounts from '${_BBlue}${_accounts_file}${_BWhite}'" "INFO"

    for ((i=0;i<${#_accounts[@]}/2;i++)); do
        local _account=${_accounts[$i,0]}
        local _password=${_accounts[$i,1]}
        if (/usr/bin/megatools ls --username "$_account" --password "$_password" /Root/ &>/dev/null); then
            log "Logging in ${_BBlue}${_account}${_BWhite} successful" "INFO"
            local _date="$(date +%A) $(date +%d.%m.%Y) $(date +%T) $(date +%z)"
            local _total="$(/usr/bin/megatools df --total --gb --username "$_account" --password "$_password")"
            local _used="$(/usr/bin/megatools df --gb --used --username "$_account" --password "$_password")"
            local _free="$(/usr/bin/megatools df --gb --free --username "$_account" --password "$_password")"
            local _stats="Total $_total GiB | Used $_used GiB | Free $_free GiB"
            _total_space=$(( _total_space + _total ))
            _total_used=$(( _total_used + _used ))
            _total_free=$(( _total_free + _free ))
            _stats=$(echo "$_stats" | sed 'H;1h;$!d;x;y/\n/ /')
            # Create timestamp file for uploading
            cat << EOF > "$_local_location"
===xxMegaKeep
Ran on: ${_date}
# Account: ${_account} 
Stats: ${_stats}
EOF
            # Check if file exists on remote and remove it
            if (megatools test --username "$_account" --password "$_password" -f "$_remote_location" > /dev/null); then
                /usr/bin/megatools rm --username "$_account" --password "$_password" --no-ask-password "$_remote_location" > /dev/null
            fi
            # Upload file to remote
            if ( ! /usr/bin/megatools put --username "$_account" --password "$_password" --disable-previews --no-progress --path "$_remote_location" "$_local_location" &>/dev/null); then
                log "Failed uploading to ${_BBlue}${_account}${_BRed} | Disk: ${_stats}" "ERROR"
                _failed_accounts="${_failed_accounts} ${_account}"
                count=$(( count - 1 ))
            else
                log "Success with ${_BBlue}$_account${_BWhite} | Disk: ${_stats}" "INFO"
            fi
            rm -rf "$_local_location"
            
        else
            log "Failed login with ${_BBlue}${_account}${_BRed}" "ERROR"
            _failed_accounts="${_failed_accounts} ${_account}"
            count=$(( count - 1 ))
        fi
    done
    local _stats_sum="Total ${_BBlue}$_total_space${_BWhite} GiB | Used ${_BBlue}$_total_used${_BWhite} GiB | Free ${_BBlue}$_total_free${_BWhite} GiB"
    if [[ "$count" -lt "$total_count" ]]; then
        log "Finished ${_BBlue}${count}/${total_count}${_BWhite} accounts (except:${_BRed}$_failed_accounts${_BWhite}) | Disk: $_stats_sum" "INFO"
    else
        log "Finished ${_BBlue}${total_count}${_BWhite} accounts | Disk $_stats_sum" "INFO"
    fi
    return 0
}

###########################
# Main
###########################
start=$(date +%s)
pre_checks
keep_accounts "$ACCOUNTS_FILE"

###########################
# Clean Exit
###########################
end=$(date +%s.%N)
runtime=$( echo "$end - $start" | bc -l )
log "Done in $runtime seconds. Performing clean exit" "INFO"
exit 0
