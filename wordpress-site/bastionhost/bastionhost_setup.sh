#!/bin/bash

# Enable strict error handling
set -euo pipefail

# Ensure the script is being run as root
if [ "$(id -u)" -ne 0 ]; then
    echo "This script must be run as root." >&2
    exit 1
fi

# Log file location
LOG_FILE="/var/log/bastionhost_setup.log"

# Redirect all output to the log file
exec &> >(tee -a "$LOG_FILE")

# Function to log messages
log_message() {
    local message=$1
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $message" | tee -a $LOG_FILE
}

# Function to handle errors
error_exit() {
    local message=$1
    log_message "ERROR: $message"
    exit 1
}

# Retrieve database credentials from AWS SSM Parameter Store
log_message "Retrieving database credentials from AWS SSM Parameter Store"
result=$(aws ssm get-parameters --names "/mysql/db_host" "/mysql/wp_user" "/mysql/wp_user_password" --with-decryption --output json) || error_exit "Failed to fetch database credentials from AWS SSM Parameter Store!"

# Extract values and export as environment variables
log_message "Extracting database credentials and exporting as environment variables"
export DB_HOST=$(echo $result | jq -r '.Parameters[] | select(.Name=="/mysql/db_host") | .Value')
export WP_USER=$(echo $result | jq -r '.Parameters[] | select(.Name=="/mysql/wp_user") | .Value')
export WP_USER_PASSWORD=$(echo $result | jq -r '.Parameters[] | select(.Name=="/mysql/wp_user_password") | .Value')
log_message "Database credentials extracted successfully"

# Check MySQL database connection
log_message "Checking MySQL database connection"
mysql -h $DB_HOST -u $WP_USER -p$WP_USER_PASSWORD -e "SELECT 1" || error_exit "Failed to connect to MySQL database!"
log_message "MySQL database connection successful"
