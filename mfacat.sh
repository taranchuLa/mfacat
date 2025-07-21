#!/bin/bash

# AWS MFA token management tool
# Usage: ./mfacat.sh --profile <profile> --token <token> --serial_number <serial>

set -e

# Default values
PROFILE=""
TOKEN=""
SERIAL_NUMBER=""
OP_ITEM=""
ACCESS_KEY_ID=""
SECRET_ACCESS_KEY=""
CONFIG_FILE="$HOME/.aws/mfacat"
NO_CACHE=false

# Function to show usage
show_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo "Options:"
    echo "  -p, --profile PROFILE     AWS profile to use (required)"
    echo "  --access-key-id KEY       AWS Access Key ID (overrides profile)"
    echo "  --secret-access-key KEY   AWS Secret Access Key (overrides profile)"
    echo "  -t, --token TOKEN         6-digit MFA token (required if --op is not specified)"
    echo "  -s, --serial_number SN    MFA serial number"
    echo "  --op ITEM_NAME           1Password item name to get OTP from"
    echo "  --no-cache               Ignore cached credentials and get new ones"
    echo "  -h, --help               Show this help message"
    echo ""
    echo "Token Management:"
echo "  When --token is specified without a value, the script will:"
echo "  1. Check for valid cached credentials first (if not expired, use them)"
echo "  2. If no valid cached credentials, show macOS dialog to enter MFA token (macOS only)"
echo "  3. Try to read a cached token from ~/.aws/mfacat_tokens (fallback)"
echo "  4. If no cached token exists and running interactively, prompt for input"
echo "  5. If no cached token exists and running in credential_process, exit with error"
echo "  6. Save the entered token to the cache file for future use"
    echo ""
    echo "macOS Dialog:"
echo "  On macOS, a system dialog will appear to enter the MFA token."
echo "  The dialog is only shown when no valid cached credentials exist."
echo "  The token is temporarily stored in the macOS Keychain for the current session."
    echo ""
    echo "Examples:"
    echo "  $0 --profile myprofile --token 123456 --serial_number arn:aws:iam::123456789012:mfa/user"
    echo "  $0 --profile myprofile --op \"AWS | MyAccount\" --serial_number arn:aws:iam::123456789012:mfa/user"
    echo "  $0 --access-key-id AKIA... --secret-access-key ... --token 123456 --serial_number arn:aws:iam::123456789012:mfa/user"
    echo "  $0 --profile myprofile --token 123456 --serial_number arn:aws:iam::123456789012:mfa/user --no-cache"
    echo "  $0 --profile myprofile --token --serial_number arn:aws:iam::123456789012:mfa/user"
}

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to check if jq is installed
check_jq() {
    if ! command_exists jq; then
        echo "Error: jq is required but not installed. Please install jq first."
        echo "  macOS: brew install jq"
        echo "  Ubuntu/Debian: sudo apt-get install jq"
        echo "  CentOS/RHEL: sudo yum install jq"
        exit 1
    fi
}

# Function to check if AWS CLI is installed
check_aws_cli() {
    if ! command_exists aws; then
        echo "Error: AWS CLI is required but not installed. Please install AWS CLI first."
        echo "  https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html"
        exit 1
    fi
}

# Function to get current timestamp in ISO format
get_current_time() {
    date -u +"%Y-%m-%dT%H:%M:%SZ"
}

# Function to check if credentials are expired
is_expired() {
    local expiration="$1"
    local current_time=$(get_current_time)
    
    if [[ "$expiration" > "$current_time" ]]; then
        return 1  # Not expired
    else
        return 0  # Expired
    fi
}

# Function to get 1Password OTP
get_1password_otp() {
    local item_name="$1"
    
    if ! command_exists op; then
        echo "Error: 1Password CLI (op) is required but not installed."
        echo "  https://developer.1password.com/docs/cli/get-started/"
        exit 1
    fi
    
    op item get "$item_name" --otp
}

# Function to read token from file
read_token_from_file() {
    local profile="$1"
    
    if [[ ! -f "$TOKEN_FILE" ]]; then
        return 1
    fi
    
    # Simple TOML parser for token file
    local in_profile=false
    local token=""
    
    while IFS= read -r line; do
        line=$(echo "$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        
        # Check if we're entering the profile section
        if [[ "$line" == "[$profile]" ]]; then
            in_profile=true
            continue
        fi
        
        # Check if we're leaving the profile section
        if [[ "$line" =~ ^\[.*\]$ ]] && [[ "$in_profile" == true ]]; then
            break
        fi
        
        # Parse token within the profile section
        if [[ "$in_profile" == true ]] && [[ "$line" =~ ^[^#]*= ]]; then
            key=$(echo "$line" | cut -d'=' -f1 | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
            value=$(echo "$line" | cut -d'=' -f2- | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | sed 's/^"//;s/"$//')
            
            if [[ "$key" == "token" ]]; then
                token="$value"
            fi
        fi
    done < "$TOKEN_FILE"
    
    if [[ -n "$token" ]]; then
        echo "$token"
        return 0
    else
        return 1
    fi
}

# Function to write token to file
write_token_to_file() {
    local profile="$1"
    local token="$2"
    
    # Create directory if it doesn't exist
    mkdir -p "$(dirname "$TOKEN_FILE")"
    
    # Read existing content
    local temp_file=$(mktemp)
    local profile_found=false
    
    if [[ -f "$TOKEN_FILE" ]]; then
        while IFS= read -r line; do
            if [[ "$line" == "[$profile]" ]]; then
                profile_found=true
                echo "$line" >> "$temp_file"
                echo "token = \"$token\"" >> "$temp_file"
                # Skip existing profile content
                while IFS= read -r next_line; do
                    if [[ "$next_line" =~ ^\[.*\]$ ]]; then
                        echo "$next_line" >> "$temp_file"
                        break
                    fi
                done
            elif [[ "$profile_found" == true ]] && [[ "$line" =~ ^\[.*\]$ ]]; then
                profile_found=false
                echo "$line" >> "$temp_file"
            elif [[ "$profile_found" == false ]]; then
                echo "$line" >> "$temp_file"
            fi
        done < "$TOKEN_FILE"
    fi
    
    # Add profile if not found
    if [[ "$profile_found" == false ]]; then
        if [[ -s "$temp_file" ]]; then
            echo "" >> "$temp_file"
        fi
        echo "[$profile]" >> "$temp_file"
        echo "token = \"$token\"" >> "$temp_file"
    fi
    
    mv "$temp_file" "$TOKEN_FILE"
}

# Function to show macOS authentication dialog and get token
get_token_via_dialog() {
    local profile="$1"
    
    # Always clear the keychain to force dialog display
    if command_exists security; then
        security delete-generic-password -s "mfacat-token-$profile" >/dev/null 2>&1 || true
    fi
    
    # Show macOS dialog to get token
    if command_exists osascript; then
        local dialog_result=$(osascript -e 'display dialog "Enter 6-digit MFA token:" default answer "" with title "MFA Token Required" with icon note' 2>/dev/null)
        
        # Check if user clicked Cancel
        if echo "$dialog_result" | grep -q "button returned:Cancel"; then
            return 1
        fi
        
        local token=$(echo "$dialog_result" | sed -n 's/.*text returned:\([^,]*\).*/\1/p' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | tr -d '\n\r')
        
        if [[ -n "$token" && "$token" =~ ^[0-9]{6}$ ]]; then
            # Save token to Keychain (for this session only)
            if command_exists security; then
                echo "$token" | security add-generic-password -s "mfacat-token-$profile" -a "$USER" -w - 2>/dev/null || true
            fi
            echo "$token"
            return 0
        fi
    fi
    
    return 1
}

# Function to read TOML file
read_toml() {
    local file="$1"
    local profile="$2"
    
    if [[ ! -f "$file" ]]; then
        return 1
    fi
    
    # Simple TOML parser for our specific use case
    local in_profile=false
    local aws_access_key_id=""
    local aws_secret_access_key=""
    local aws_session_token=""
    local expiration=""
    
    while IFS= read -r line; do
        line=$(echo "$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        
        # Check if we're entering the profile section
        if [[ "$line" == "[$profile]" ]]; then
            in_profile=true
            continue
        fi
        
        # Check if we're leaving the profile section
        if [[ "$line" =~ ^\[.*\]$ ]] && [[ "$in_profile" == true ]]; then
            break
        fi
        
        # Parse key-value pairs within the profile section
        if [[ "$in_profile" == true ]] && [[ "$line" =~ ^[^#]*= ]]; then
            key=$(echo "$line" | cut -d'=' -f1 | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
            value=$(echo "$line" | cut -d'=' -f2- | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | sed 's/^"//;s/"$//')
            
            case "$key" in
                "aws_access_key_id")
                    aws_access_key_id="$value"
                    ;;
                "aws_secret_access_key")
                    aws_secret_access_key="$value"
                    ;;
                "aws_session_token")
                    aws_session_token="$value"
                    ;;
                "expiration")
                    expiration="$value"
                    ;;
            esac
        fi
    done < "$file"
    
    # Return values through global variables
    if [[ -n "$aws_access_key_id" && -n "$aws_secret_access_key" && -n "$aws_session_token" && -n "$expiration" ]]; then
        CACHED_ACCESS_KEY_ID="$aws_access_key_id"
        CACHED_SECRET_ACCESS_KEY="$aws_secret_access_key"
        CACHED_SESSION_TOKEN="$aws_session_token"
        CACHED_EXPIRATION="$expiration"
        return 0
    else
        return 1
    fi
}

# Function to write TOML file
write_toml() {
    local file="$1"
    local profile="$2"
    local access_key_id="$3"
    local secret_access_key="$4"
    local session_token="$5"
    local expiration="$6"
    
    # Create directory if it doesn't exist
    mkdir -p "$(dirname "$file")"
    
    # Read existing content
    local temp_file=$(mktemp)
    local profile_found=false
    
    if [[ -f "$file" ]]; then
        while IFS= read -r line; do
            if [[ "$line" == "[$profile]" ]]; then
                profile_found=true
                echo "$line" >> "$temp_file"
                echo "aws_access_key_id = \"$access_key_id\"" >> "$temp_file"
                echo "aws_secret_access_key = \"$secret_access_key\"" >> "$temp_file"
                echo "aws_session_token = \"$session_token\"" >> "$temp_file"
                echo "expiration = \"$expiration\"" >> "$temp_file"
                # Skip existing profile content
                while IFS= read -r next_line; do
                    if [[ "$next_line" =~ ^\[.*\]$ ]]; then
                        echo "$next_line" >> "$temp_file"
                        break
                    fi
                done
            elif [[ "$profile_found" == true ]] && [[ "$line" =~ ^\[.*\]$ ]]; then
                profile_found=false
                echo "$line" >> "$temp_file"
            elif [[ "$profile_found" == false ]]; then
                echo "$line" >> "$temp_file"
            fi
        done < "$file"
    fi
    
    # Add profile if not found
    if [[ "$profile_found" == false ]]; then
        if [[ -s "$temp_file" ]]; then
            echo "" >> "$temp_file"
        fi
        echo "[$profile]" >> "$temp_file"
        echo "aws_access_key_id = \"$access_key_id\"" >> "$temp_file"
        echo "aws_secret_access_key = \"$secret_access_key\"" >> "$temp_file"
        echo "aws_session_token = \"$session_token\"" >> "$temp_file"
        echo "expiration = \"$expiration\"" >> "$temp_file"
    fi
    
    mv "$temp_file" "$file"
}

# Parse command line arguments
TOKEN_SPECIFIED=false
while [[ $# -gt 0 ]]; do
    case $1 in
        -p|--profile)
            PROFILE="$2"
            shift 2
            ;;
        --access-key-id)
            ACCESS_KEY_ID="$2"
            shift 2
            ;;
        --secret-access-key)
            SECRET_ACCESS_KEY="$2"
            shift 2
            ;;
        -t|--token)
            if [[ -n "$2" && "$2" != --* ]]; then
                TOKEN="$2"
                shift 2
            else
                TOKEN=""
                shift 1
            fi
            TOKEN_SPECIFIED=true
            ;;
        -s|--serial_number)
            SERIAL_NUMBER="$2"
            shift 2
            ;;
        --op)
            OP_ITEM="$2"
            shift 2
            ;;
        --no-cache)
            NO_CACHE=true
            shift 1
            ;;
        -h|--help)
            show_usage
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            show_usage
            exit 1
            ;;
    esac
done

# Validate required arguments
if [[ -z "$SERIAL_NUMBER" ]]; then
    echo "Error: --serial_number is required"
    show_usage
    exit 1
fi

# Profile is required only if access key and secret key are not provided
if [[ -z "$ACCESS_KEY_ID" && -z "$SECRET_ACCESS_KEY" && -z "$PROFILE" ]]; then
    echo "Error: --profile is required when --access-key-id and --secret-access-key are not specified"
    show_usage
    exit 1
fi

# If --token was specified but value is empty, check for cached credentials first
if [[ "$TOKEN_SPECIFIED" == true && -z "$TOKEN" ]]; then
    # Check if we have valid cached credentials first
    if [[ "$NO_CACHE" != true ]] && read_toml "$CONFIG_FILE" "$PROFILE"; then
        if ! is_expired "$CACHED_EXPIRATION"; then
            # Use cached credentials without prompting for token
            credentials=$(cat <<EOF
{
  "Version": 1,
  "AccessKeyId": "$CACHED_ACCESS_KEY_ID",
  "SecretAccessKey": "$CACHED_SECRET_ACCESS_KEY",
  "SessionToken": "$CACHED_SESSION_TOKEN",
  "Expiration": "$CACHED_EXPIRATION"
}
EOF
)
            echo "$credentials" | jq '.'
            exit 0
        fi
    fi
    
    # If no valid cached credentials, prompt for token
    dialog_token=$(get_token_via_dialog "$PROFILE")
    if [[ -n "$dialog_token" && "$dialog_token" != "-" ]]; then
        TOKEN="$dialog_token"
    else
        # Fallback to file-based token if dialog fails
        if read_token_from_file "$PROFILE"; then
            TOKEN=$(read_token_from_file "$PROFILE")
        else
            # Check if we're running in credential_process mode (no TTY available)
            if [[ ! -t 0 ]]; then
                echo "Error: No token provided and no cached token found. Please run manually first to cache a token." >&2
                exit 1
            fi
            echo -n "Enter 6-digit MFA token: "
            read -r TOKEN < /dev/tty
            echo ""
            # Save token to file for future use
            write_token_to_file "$PROFILE" "$TOKEN"
        fi
    fi
fi

# Check if either --token or --op is specified
# Note: --token can be specified without a value to trigger dialog/cache check
if [[ "$TOKEN_SPECIFIED" != true && -z "$OP_ITEM" ]]; then
    echo "Error: Either --token or --op is required"
    show_usage
    exit 1
fi

# Check if both --token and --op are specified
if [[ -n "$TOKEN" && -n "$OP_ITEM" ]]; then
    echo "Error: Cannot specify both --token and --op"
    show_usage
    exit 1
fi

# Validate token format (6 digits only) - only if TOKEN has a value
if [[ -n "$TOKEN" ]]; then
    if ! [[ "$TOKEN" =~ ^[0-9]{6}$ ]]; then
        echo "Error: --token must be exactly 6 digits"
        show_usage
        exit 1
    fi
fi

# Validate that both access key and secret key are provided if one is specified
if [[ -n "$ACCESS_KEY_ID" && -z "$SECRET_ACCESS_KEY" ]]; then
    echo "Error: --secret-access-key is required when --access-key-id is specified"
    show_usage
    exit 1
fi

if [[ -z "$ACCESS_KEY_ID" && -n "$SECRET_ACCESS_KEY" ]]; then
    echo "Error: --access-key-id is required when --secret-access-key is specified"
    show_usage
    exit 1
fi

# Check dependencies
check_jq
check_aws_cli

# Check if we have cached credentials (unless --no-cache is specified)
if [[ "$NO_CACHE" != true ]] && read_toml "$CONFIG_FILE" "$PROFILE"; then
    if ! is_expired "$CACHED_EXPIRATION"; then
        # Use cached credentials
        credentials=$(cat <<EOF
{
  "Version": 1,
  "AccessKeyId": "$CACHED_ACCESS_KEY_ID",
  "SecretAccessKey": "$CACHED_SECRET_ACCESS_KEY",
  "SessionToken": "$CACHED_SESSION_TOKEN",
  "Expiration": "$CACHED_EXPIRATION"
}
EOF
)
        echo "$credentials" | jq '.'
        exit 0
    fi
fi

# Get MFA token
if [[ -n "$OP_ITEM" ]]; then
    TOKEN=$(get_1password_otp "$OP_ITEM")
fi

# Build AWS CLI command
aws_cmd="aws sts get-session-token --duration-seconds 3600 --token-code \"$TOKEN\" --serial-number \"$SERIAL_NUMBER\" --output json"

# Add profile or credentials based on what's provided
if [[ -n "$ACCESS_KEY_ID" && -n "$SECRET_ACCESS_KEY" ]]; then
    # Use provided credentials
    aws_cmd="AWS_ACCESS_KEY_ID=\"$ACCESS_KEY_ID\" AWS_SECRET_ACCESS_KEY=\"$SECRET_ACCESS_KEY\" $aws_cmd"
else
    # Use profile
    aws_cmd="$aws_cmd --profile \"$PROFILE\""
fi

# Get session token from AWS
response=$(eval $aws_cmd)

# Extract credentials
access_key_id=$(echo "$response" | jq -r '.Credentials.AccessKeyId')
secret_access_key=$(echo "$response" | jq -r '.Credentials.SecretAccessKey')
session_token=$(echo "$response" | jq -r '.Credentials.SessionToken')
expiration=$(echo "$response" | jq -r '.Credentials.Expiration')

# Cache credentials
write_toml "$CONFIG_FILE" "$PROFILE" "$access_key_id" "$secret_access_key" "$session_token" "$expiration"

# Output credentials in JSON format
credentials=$(cat <<EOF
{
  "Version": 1,
  "AccessKeyId": "$access_key_id",
  "SecretAccessKey": "$secret_access_key",
  "SessionToken": "$session_token",
  "Expiration": "$expiration"
}
EOF
)

echo "$credentials" | jq '.' 