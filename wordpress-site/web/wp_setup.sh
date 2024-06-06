#!/bin/bash

# Enable strict error handling
set -euo pipefail

# Ensure the script is being run as root
if [ "$(id -u)" -ne 0 ]; then
    echo "This script must be run as root." >&2
    exit 1
fi

# Log file location
LOG_FILE="/var/log/wp_setup.log"

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

# Function to get parameter value by name
function get_parameter_value() {
  local parameters_list=$1
  local parameter_name=$2
  local parameter_value
  parameter_value=$(echo "$parameters_list" | jq -r --arg key "$parameter_name" '.[] | select(.Name == $key) | .Value') || error_exit "Failed to get value of the $parameter_name"!
  echo "$parameter_value"
}

# Fetch db parameters from the AWS SSM Parameter Store
fetch_db_parameters() {
    local param_path=$1
    local result
    result=$(aws ssm get-parameters --names "${param_path}/wp_database" "${param_path}/wp_user" "${param_path}/wp_user_password" "${param_path}/db_host" --with-decryption --query 'Parameters[*].{Name:Name,Value:Value}' --output json) || error_exit "Failed to fetch db parameters from $param_path"!
    echo "$result"
}

# Fetch wordpress parameters from the SSM Parameter Store
fetch_wordpress_parameters() {
    local param_path=$1
    local result
    # Fetch parameters from SSM by path
    result=$(aws ssm get-parameters-by-path --path "$param_path" --with-decryption --query 'Parameters[*].{Name:Name,Value:Value}' --output json) || error_exit "Failed to fetch wordpress parameters from $param_path"!
    echo "$result"
}

# Define the base paths in SSM Parameter Store
SSM_MYSQL_PARAM_PATH="/mysql"
SSM_WORDPRESS_PARAM_PATH="/wordpress"

# Update wp-config.php file
log_message "Updating wp-config.php file"

# Fetch MySQL and WordPress parameters
log_message "Fetching MySQL and WordPress parameters from the AWS SSM Parameter Store"
MYSQL_PARAMETERS=$(fetch_db_parameters "$SSM_MYSQL_PARAM_PATH")
WORDPRESS_PARAMETERS=$(fetch_wordpress_parameters "$SSM_WORDPRESS_PARAM_PATH")

# Retrieve MySQL parameters from SSM Parameter Store
log_message "Retrieving MySQL parameters from SSM Parameter Store"
DB_NAME=$(get_parameter_value "$MYSQL_PARAMETERS" "${SSM_MYSQL_PARAM_PATH}/wp_database")
DB_USER=$(get_parameter_value "$MYSQL_PARAMETERS" "${SSM_MYSQL_PARAM_PATH}/wp_user")
DB_PASSWORD=$(get_parameter_value "$MYSQL_PARAMETERS" "${SSM_MYSQL_PARAM_PATH}/wp_user_password")
DB_HOST=$(get_parameter_value "$MYSQL_PARAMETERS" "${SSM_MYSQL_PARAM_PATH}/db_host")

# Retrieve WordPress parameters from SSM Parameter Store
log_message "Retrieving WordPress parameters from SSM Parameter Store"
AUTH_KEY=$(get_parameter_value "$WORDPRESS_PARAMETERS" "${SSM_WORDPRESS_PARAM_PATH}/AUTH_KEY")
SECURE_AUTH_KEY=$(get_parameter_value "$WORDPRESS_PARAMETERS" "${SSM_WORDPRESS_PARAM_PATH}/SECURE_AUTH_KEY")
LOGGED_IN_KEY=$(get_parameter_value "$WORDPRESS_PARAMETERS" "${SSM_WORDPRESS_PARAM_PATH}/LOGGED_IN_KEY")
NONCE_KEY=$(get_parameter_value "$WORDPRESS_PARAMETERS" "${SSM_WORDPRESS_PARAM_PATH}/NONCE_KEY")
AUTH_SALT=$(get_parameter_value "$WORDPRESS_PARAMETERS" "${SSM_WORDPRESS_PARAM_PATH}/AUTH_SALT")
SECURE_AUTH_SALT=$(get_parameter_value "$WORDPRESS_PARAMETERS" "${SSM_WORDPRESS_PARAM_PATH}/SECURE_AUTH_SALT")
LOGGED_IN_SALT=$(get_parameter_value "$WORDPRESS_PARAMETERS" "${SSM_WORDPRESS_PARAM_PATH}/LOGGED_IN_SALT")
NONCE_SALT=$(get_parameter_value "$WORDPRESS_PARAMETERS" "${SSM_WORDPRESS_PARAM_PATH}/NONCE_SALT")
log_message "Fetched parameters successfully from AWS SSM Parameter Store"

# Update wp-config.php with the retrieved values
WP_CONFIG_PATH="/var/www/html/wordpress/wp-config.php"

log_message "Updating wp-config.php file with retrieved values"
sed -i "s/define( 'DB_NAME', '.*' );/define( 'DB_NAME', '$DB_NAME' );/g" "$WP_CONFIG_PATH"
sed -i "s/define( 'DB_USER', '.*' );/define( 'DB_USER', '$DB_USER' );/g" "$WP_CONFIG_PATH"
sed -i "s/define( 'DB_PASSWORD', '.*' );/define( 'DB_PASSWORD', '$DB_PASSWORD' );/g" "$WP_CONFIG_PATH"
sed -i "s/define( 'DB_HOST', '.*' );/define( 'DB_HOST', '$DB_HOST' );/g" "$WP_CONFIG_PATH"
sed -i "s/define( 'DB_CHARSET', '.*' );/define( 'DB_CHARSET', 'utf8mb4' );/g" "$WP_CONFIG_PATH"
sed -i "s/define( 'DB_COLLATE', '.*' );/define( 'DB_COLLATE', 'utf8mb4_unicode_ci' );/g" "$WP_CONFIG_PATH"
sed -i "s/define( 'AUTH_KEY', *'put your unique phrase here' );/define( 'AUTH_KEY', '$AUTH_KEY' );/g" "$WP_CONFIG_PATH"
sed -i "s/define( 'SECURE_AUTH_KEY', *'put your unique phrase here' );/define( 'SECURE_AUTH_KEY', '$SECURE_AUTH_KEY' );/g" "$WP_CONFIG_PATH"
sed -i "s/define( 'LOGGED_IN_KEY', *'put your unique phrase here' );/define( 'LOGGED_IN_KEY', '$LOGGED_IN_KEY' );/g" "$WP_CONFIG_PATH"
sed -i "s/define( 'NONCE_KEY', *'put your unique phrase here' );/define( 'NONCE_KEY', '$NONCE_KEY' );/g" "$WP_CONFIG_PATH"
sed -i "s/define( 'AUTH_SALT', *'put your unique phrase here' );/define( 'AUTH_SALT', '$AUTH_SALT' );/g" "$WP_CONFIG_PATH"
sed -i "s/define( 'SECURE_AUTH_SALT', *'put your unique phrase here' );/define( 'SECURE_AUTH_SALT', '$SECURE_AUTH_SALT' );/g" "$WP_CONFIG_PATH"
sed -i "s/define( 'LOGGED_IN_SALT', *'put your unique phrase here' );/define( 'LOGGED_IN_SALT', '$LOGGED_IN_SALT' );/g" "$WP_CONFIG_PATH"
sed -i "s/define( 'NONCE_SALT', *'put your unique phrase here' );/define( 'NONCE_SALT', '$NONCE_SALT' );/g" "$WP_CONFIG_PATH"

if [ $? -eq 0 ]; then
    log_message "wp-config.php has been updated successfully with values from AWS SSM Parameter Store"
else
    error_exit "Failed to update wp-config.php"
fi

log_message "wp-config.php update process completed successfully"