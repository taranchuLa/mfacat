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
    echo "  -h, --help               Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 --profile myprofile --token 123456 --serial_number arn:aws:iam::123456789012:mfa/user"
    echo "  $0 --profile myprofile --op \"AWS | MyAccount\" --serial_number arn:aws:iam::123456789012:mfa/user"
    echo "  $0 --access-key-id AKIA... --secret-access-key ... --token 123456 --serial_number arn:aws:iam::123456789012:mfa/user"
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
            TOKEN="$2"
            shift 2
            ;;
        -s|--serial_number)
            SERIAL_NUMBER="$2"
            shift 2
            ;;
        --op)
            OP_ITEM="$2"
            shift 2
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

if [[ -z "$PROFILE" ]]; then
    echo "Error: --profile is required"
    show_usage
    exit 1
fi

# Check if either --token or --op is specified
if [[ -z "$TOKEN" && -z "$OP_ITEM" ]]; then
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

# Validate token format (6 digits only)
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

# Check if we have cached credentials
if read_toml "$CONFIG_FILE" "$PROFILE"; then
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