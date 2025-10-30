#!/usr/bin/env bash
###########################
# xxMegaKeep - MEGA Account Keeper
# Version: 2.0
# Description: Prevents MEGA accounts from expiring by performing periodic file operations
###########################

set -euo pipefail  # Exit on error, undefined variables, and pipe failures

###########################
# Script Constants
###########################
readonly SCRIPT_VERSION="2.0"
readonly SCRIPT_NAME="xxMegaKeep"
readonly DEFAULT_ACCOUNTS_FILE="./.accounts"
readonly TEMP_FILE_NAME="xxMegaKeep.txt"
readonly REMOTE_FILE_PATH="/Root/xxMegaKeep.txt"
readonly MAX_RETRIES=3
readonly RETRY_DELAY=5

###########################
# Configuration
###########################
# Load environment variables from .env file if it exists
load_env_file() {
    local env_file=".env"
    if [[ -f "$env_file" ]]; then
        while IFS='=' read -r key value; do
            # Skip comments and empty lines
            [[ "$key" =~ ^#.*$ ]] || [[ -z "$key" ]] && continue
            # Remove leading/trailing whitespace
            key=$(echo "$key" | xargs)
            value=$(echo "$value" | xargs)
            # Export variable
            export "$key=$value"
        done < "$env_file"
    fi
}

load_env_file
readonly ACCOUNTS_FILE="${ACCOUNTS_FILE:-$DEFAULT_ACCOUNTS_FILE}"

###########################
# Color Definitions
###########################
readonly COLOR_RED=$'\e[1;31m'
readonly COLOR_YELLOW=$'\e[1;33m'
readonly COLOR_BLUE=$'\e[1;34m'
readonly COLOR_WHITE=$'\e[1;37m'
readonly COLOR_GREEN=$'\e[1;32m'
readonly COLOR_RESET=$'\e[0m'

###########################
# Logging Functions
###########################
log_message() {
    local message="$1"
    local level="${2:-INFO}"
    local timestamp
    local color
    
    timestamp=$(date +"%Y-%m-%d %H:%M:%S %Z")
    
    case "${level^^}" in
        INFO)
            color="$COLOR_WHITE"
            ;;
        WARN|WARNING)
            color="$COLOR_YELLOW"
            ;;
        ERROR|ERR)
            color="$COLOR_RED"
            ;;
        SUCCESS)
            color="$COLOR_GREEN"
            ;;
        *)
            color="$COLOR_BLUE"
            level="UNKNOWN"
            ;;
    esac
    
    # Write to stderr so it's not captured by command substitution
    printf "%b[%s][%s v%s][%s]: %s%b\n" "$color" "$level" "$SCRIPT_NAME" "$SCRIPT_VERSION" "$timestamp" "$message" "$COLOR_RESET" >&2
}

log_info() {
    log_message "$1" "INFO"
}

log_warn() {
    log_message "$1" "WARN"
}

log_error() {
    log_message "$1" "ERROR"
}

log_success() {
    log_message "$1" "SUCCESS"
}

###########################
# Error Handling
###########################
cleanup_on_exit() {
    local exit_code=$?
    
    # Clean up any temporary files
    if [[ -f "$TEMP_FILE_NAME" ]]; then
        rm -f "$TEMP_FILE_NAME"
    fi
    
    if [[ $exit_code -ne 0 ]]; then
        log_error "Script exited with error code: $exit_code"
    fi
}

trap cleanup_on_exit EXIT

###########################
# Validation Functions
###########################
validate_command_exists() {
    local command="$1"
    
    if ! command -v "$command" &>/dev/null; then
        log_error "Required command '${command}' not found. Please install it first."
        exit 1
    fi
}

validate_file_exists() {
    local file="$1"
    
    if [[ ! -f "$file" ]]; then
        log_error "Required file '${file}' not found."
        exit 1
    fi
}

validate_account_credentials() {
    local account="$1"
    local password="$2"
    
    if [[ ${#account} -lt 3 ]]; then
        log_warn "Account name '${account}' is too short (minimum 3 characters). Skipping."
        return 1
    fi
    
    if [[ ${#password} -lt 3 ]]; then
        log_warn "Password for '${account}' is too short (minimum 3 characters). Skipping."
        return 1
    fi
    
    # Basic email format validation
    if [[ ! "$account" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
        log_warn "Account '${account}' doesn't appear to be a valid email format. Proceeding anyway."
    fi
    
    return 0
}

###########################
# MEGA Operations
###########################
mega_execute_with_retry() {
    local max_attempts="$1"
    local operation_desc="$2"
    shift 2
    local command=("$@")
    local attempt=1
    
    while [[ $attempt -le $max_attempts ]]; do
        if "${command[@]}" &>/dev/null; then
            return 0
        fi
        
        if [[ $attempt -lt $max_attempts ]]; then
            log_warn "${operation_desc} - Attempt $attempt/$max_attempts failed. Retrying in ${RETRY_DELAY}s..."
            sleep "$RETRY_DELAY"
        fi
        
        attempt=$((attempt + 1))
    done
    
    return 1
}

mega_test_login() {
    local account="$1"
    local password="$2"
    
    mega_execute_with_retry 2 "Login check for ${account}" megatools ls --username "$account" --password "$password" /Root/
}

mega_get_storage_info() {
    local account="$1"
    local password="$2"
    local info_type="$3"
    
    case "$info_type" in
        total)
            megatools df --total --gb --username "$account" --password "$password" 2>/dev/null | xargs
            ;;
        used)
            megatools df --used --gb --username "$account" --password "$password" 2>/dev/null | xargs
            ;;
        free)
            megatools df --free --gb --username "$account" --password "$password" 2>/dev/null | xargs
            ;;
        *)
            echo "0"
            ;;
    esac
}

mega_upload_file() {
    local account="$1"
    local password="$2"
    local local_file="$3"
    local remote_path="$4"
    
    # Check if file exists remotely and remove it (redirect stdout to avoid capturing it)
    if megatools test --username "$account" --password "$password" -f "$remote_path" &>/dev/null; then
        megatools rm --username "$account" --password "$password" --no-ask-password "$remote_path" &>/dev/null || true
    fi
    
    # Upload the file
    mega_execute_with_retry "$MAX_RETRIES" "Upload to ${account}" megatools put \
        --username "$account" \
        --password "$password" \
        --disable-previews \
        --no-progress \
        --path "$remote_path" \
        "$local_file"
}

###########################
# Account Processing
###########################
create_timestamp_file() {
    local account="$1"
    local stats="$2"
    local output_file="$3"
    local timestamp
    
    timestamp=$(date +"%A, %B %d, %Y at %T %Z")
    
    cat > "$output_file" << EOF
===xxMegaKeep Activity Log===
Timestamp: ${timestamp}
Account: ${account}
Storage Stats: ${stats}
Status: Active
EOF
}

process_single_account() {
    local account="$1"
    local password="$2"
    local temp_file="$TEMP_FILE_NAME"
    
    log_info "Processing: ${account}"
    
    # Test login
    if ! mega_test_login "$account" "$password"; then
        log_error "Login failed: ${account}"
        return 1
    fi
    
    log_success "Login successful: ${account}"
    
    # Get storage information
    local total_space used_space free_space
    total_space=$(mega_get_storage_info "$account" "$password" "total")
    used_space=$(mega_get_storage_info "$account" "$password" "used")
    free_space=$(mega_get_storage_info "$account" "$password" "free")
    
    local stats="Total ${total_space} GiB | Used ${used_space} GiB | Free ${free_space} GiB"
    
    # Create timestamp file
    create_timestamp_file "$account" "$stats" "$temp_file"
    
    # Upload file
    if ! mega_upload_file "$account" "$password" "$temp_file" "$REMOTE_FILE_PATH"; then
        log_error "Upload failed: ${account} | Storage: ${stats}"
        rm -f "$temp_file"
        return 1
    fi
    
    log_success "Completed: ${account} | Storage: ${stats}"
    rm -f "$temp_file"
    
    # Return storage stats for accumulation (explicitly to stdout)
    echo "$total_space $used_space $free_space" >&1
    return 0
}

load_accounts() {
    local accounts_file="$1"
    local -n accounts_ref=$2
    local line_number=0
    local total_lines=0
    local skipped_lines=0
    
    # Check if file is readable
    if [[ ! -r "$accounts_file" ]]; then
        log_error "Cannot read accounts file '${accounts_file}'"
        exit 1
    fi
    
    while IFS=' ' read -r account password || [[ -n "$account" ]]; do
        line_number=$((line_number + 1))
        total_lines=$((total_lines + 1))
        
        # Skip empty lines and comments
        if [[ -z "$account" ]] || [[ "$account" =~ ^#.*$ ]]; then
            skipped_lines=$((skipped_lines + 1))
            continue
        fi
        
        # Handle missing password
        if [[ -z "$password" ]]; then
            log_warn "Line $line_number: Missing password for account '${account}'. Skipping."
            skipped_lines=$((skipped_lines + 1))
            continue
        fi
        
        # Validate credentials
        if ! validate_account_credentials "$account" "$password"; then
            skipped_lines=$((skipped_lines + 1))
            continue
        fi
        
        accounts_ref+=("$account:$password")
    done < "$accounts_file"
    
    if [[ ${#accounts_ref[@]} -eq 0 ]]; then
        log_error "No valid accounts found in '${accounts_file}'"
        log_error "Total lines: $total_lines, Skipped/Invalid: $skipped_lines, Valid: 0"
        log_error "Please check the file format. Expected: 'email@example.com password' (one per line)"
        exit 1
    fi
}

process_all_accounts() {
    local accounts_file="$1"
    local -a accounts=()
    local -a failed_accounts=()
    local successful_count=0
    local total_accounts
    local total_space=0 used_space=0 free_space=0
    
    # Load accounts from file
    load_accounts "$accounts_file" accounts
    total_accounts=${#accounts[@]}
    
    log_info "Loaded ${total_accounts} account(s) from '${accounts_file}'"
    echo "" >&2
    
    # Process each account
    local current_account=0
    for account_entry in "${accounts[@]}"; do
        IFS=':' read -r account password <<< "$account_entry"
        current_account=$((current_account + 1))
        
        echo "----------------------------------------" >&2
        log_info "Account ${current_account}/${total_accounts}: ${account}"
        
        # Process account and capture stdout (storage stats) while stderr (logs) go to terminal
        # The { } group allows us to separate stdout and stderr handling
        storage_stats=$(
            process_single_account "$account" "$password"
        ) || true
        
        if [[ -n "$storage_stats" ]]; then
            # Accumulate storage statistics
            read -r total used free <<< "$storage_stats"
            # Only add to totals if values are numeric
            if [[ "$total" =~ ^[0-9.]+$ ]] && [[ "$used" =~ ^[0-9.]+$ ]] && [[ "$free" =~ ^[0-9.]+$ ]]; then
                total_space=$(echo "$total_space + $total" | bc -l)
                used_space=$(echo "$used_space + $used" | bc -l)
                free_space=$(echo "$free_space + $free" | bc -l)
                successful_count=$((successful_count + 1))
            else
                # Got output but invalid storage numbers
                failed_accounts+=("$account")
            fi
        else
            failed_accounts+=("$account")
        fi
        
        # Add spacing between account processing
        echo "" >&2
    done
    
    # Display summary
    if [[ ${#failed_accounts[@]} -gt 0 ]]; then
        display_summary "$successful_count" "$total_accounts" "$total_space" "$used_space" "$free_space" "${failed_accounts[@]}"
    else
        display_summary "$successful_count" "$total_accounts" "$total_space" "$used_space" "$free_space"
    fi
}

display_summary() {
    local successful="$1"
    local total="$2"
    local total_space="${3:-0}"
    local used_space="${4:-0}"
    local free_space="${5:-0}"
    shift 5
    local failed_accounts=("$@")
    
    echo "========================================" >&2
    log_info "Processing Complete"
    echo "========================================" >&2
    
    # Format storage stats (keep it simple, colors are added by log functions)
    local stats_summary="Total ${total_space} GiB | Used ${used_space} GiB | Free ${free_space} GiB"
    
    if [[ $successful -eq $total ]]; then
        log_success "All ${total} accounts processed successfully | Storage: ${stats_summary}"
    else
        local failed_count=$((total - successful))
        log_warn "Processed ${successful}/${total} accounts (${failed_count} failed) | Storage: ${stats_summary}"
        
        if [[ ${#failed_accounts[@]} -gt 0 ]]; then
            log_warn "Failed accounts: ${failed_accounts[*]}"
        fi
    fi
}

###########################
# Pre-flight Checks
###########################
preflight_checks() {
    log_info "Performing pre-flight checks..."
    
    # Check for required commands
    validate_command_exists "megatools"
    validate_command_exists "bc"
    validate_command_exists "date"
    
    # Check for accounts file
    validate_file_exists "$ACCOUNTS_FILE"
    
    log_success "Pre-flight checks passed"
    echo "" >&2
}

###########################
# Main Execution
###########################
main() {
    local start_time end_time runtime
    
    echo "========================================" >&2
    log_info "Starting ${SCRIPT_NAME} v${SCRIPT_VERSION}"
    echo "========================================" >&2
    echo "" >&2
    
    start_time=$(date +%s.%N)
    
    # Run pre-flight checks
    preflight_checks
    
    # Process all accounts
    process_all_accounts "$ACCOUNTS_FILE"
    
    # Calculate runtime
    end_time=$(date +%s.%N)
    runtime=$(echo "$end_time - $start_time" | bc -l)
    runtime=$(printf "%.2f" "$runtime")
    
    echo "" >&2
    echo "========================================" >&2
    log_success "Completed in ${runtime} seconds"
    echo "========================================" >&2
}

# Execute main function
main
