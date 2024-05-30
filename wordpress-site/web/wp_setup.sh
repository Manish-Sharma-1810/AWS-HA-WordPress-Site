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
get_parameter_value() {
    local param_path=$1
    local param_name=$2
    echo "$param_path" | jq -r ".[] | select(.Name==\"${param_name}\") | .Value"
}

# Fetch parameters from SSM Parameter Store and handle errors
fetch_parameters() {
    local param_path=$1
    local result
    result=$(aws ssm get-parameters-by-path --path "$param_path" --with-decryption --query 'Parameters[*].{Name:Name,Value:Value}' --output json) || error_exit "Failed to fetch parameters from $param_path"
    echo "$result"
}

# Download the latest WordPress package
log_message "Downloading the latest WordPress package"
wget -c http://wordpress.org/latest.tar.gz || error_exit "Failed to download WordPress package"

# Extract the downloaded package
log_message "Extracting the WordPress package"
tar -xzvf latest.tar.gz || error_exit "Failed to extract WordPress package"

# Remove the tar file
log_message "Removing the WordPress tar.gz file"
rm -r latest.tar.gz || error_exit "Failed to remove the tar.gz file"

# Move WordPress files to the web server directory
log_message "Moving WordPress files to /var/www/html/"
mv wordpress/* /var/www/html/ || error_exit "Failed to move WordPress files to /var/www/html/"

# Set correct permissions and ownership
log_message "Setting permissions and ownership for /var/www/html/"
chown -R www-data:www-data /var/www/html/ || error_exit "Failed to change ownership of /var/www/html/"
chmod -R 755 /var/www/html/ || error_exit "Failed to change permissions of /var/www/html/"

# Copy the sample configuration file to wp-config.php
log_message "Copying wp-config-sample.php to wp-config.php"
cp /var/www/html/wp-config-sample.php /var/www/html/wp-config.php || error_exit "Failed to copy wp-config-sample.php to wp-config.php"

# Define the base paths in SSM Parameter Store
SSM_MYSQL_PARAM_PATH="/mysql"
SSM_WORDPRESS_PARAM_PATH="/wordpress"

# Update wp-config.php file
log_message "Updating wp-config.php file"

# Fetch MySQL and WordPress parameters
log_message "Fetching MySQL and WordPress parameters from the AWS SSM Parameter Store"
MYSQL_PARAMETERS=$(fetch_parameters "$SSM_MYSQL_PARAM_PATH")
WORDPRESS_PARAMETERS=$(fetch_parameters "$SSM_WORDPRESS_PARAM_PATH")

# Retrieve MySQL parameters from SSM Parameter Store
log_message "Retrieving MySQL parameters from SSM Parameter Store"
DB_NAME=$(get_parameter_value "$MYSQL_PARAMETERS" "${SSM_MYSQL_PARAM_PATH}/db_name")
DB_USER=$(get_parameter_value "$MYSQL_PARAMETERS" "${SSM_MYSQL_PARAM_PATH}/db_user")
DB_PASSWORD=$(get_parameter_value "$MYSQL_PARAMETERS" "${SSM_MYSQL_PARAM_PATH}/db_password")
DB_HOST=$(get_parameter_value "$MYSQL_PARAMETERS" "${SSM_MYSQL_PARAM_PATH}/db_host")

# Retrieve WordPress parameters from SSM Parameter Store
log_message "Retrieving WordPress parameters from SSM Parameter Store"
AUTH_KEY=$(get_parameter_value "$WORDPRESS_PARAMETERS" "${SSM_WORDPRESS_PARAM_PATH}/auth_key")
SECURE_AUTH_KEY=$(get_parameter_value "$WORDPRESS_PARAMETERS" "${SSM_WORDPRESS_PARAM_PATH}/secure_auth_key")
LOGGED_IN_KEY=$(get_parameter_value "$WORDPRESS_PARAMETERS" "${SSM_WORDPRESS_PARAM_PATH}/logged_in_key")
NONCE_KEY=$(get_parameter_value "$WORDPRESS_PARAMETERS" "${SSM_WORDPRESS_PARAM_PATH}/nonce_key")
AUTH_SALT=$(get_parameter_value "$WORDPRESS_PARAMETERS" "${SSM_WORDPRESS_PARAM_PATH}/auth_salt")
SECURE_AUTH_SALT=$(get_parameter_value "$WORDPRESS_PARAMETERS" "${SSM_WORDPRESS_PARAM_PATH}/secure_auth_salt")
LOGGED_IN_SALT=$(get_parameter_value "$WORDPRESS_PARAMETERS" "${SSM_WORDPRESS_PARAM_PATH}/logged_in_salt")
NONCE_SALT=$(get_parameter_value "$WORDPRESS_PARAMETERS" "${SSM_WORDPRESS_PARAM_PATH}/nonce_salt")
log_message "Fetched parameters successfully from AWS SSM Parameter Store"

# Update wp-config.php with the retrieved values
WP_CONFIG_PATH="/var/www/html/wp-config.php"

log_message "Updating wp-config.php file with retrieved values"
sed -i "s/define( 'DB_NAME', '.*' );/define( 'DB_NAME', '$DB_NAME' );/g" "$WP_CONFIG_PATH"
sed -i "s/define( 'DB_USER', '.*' );/define( 'DB_USER', '$DB_USER' );/g" "$WP_CONFIG_PATH"
sed -i "s/define( 'DB_PASSWORD', '.*' );/define( 'DB_PASSWORD', '$DB_PASSWORD' );/g" "$WP_CONFIG_PATH"
sed -i "s/define( 'DB_HOST', '.*' );/define( 'DB_HOST', '$DB_HOST' );/g" "$WP_CONFIG_PATH"
sed -i "s/define( 'AUTH_KEY', '.*' );/define( 'AUTH_KEY', '$AUTH_KEY' );/g" "$WP_CONFIG_PATH"
sed -i "s/define( 'SECURE_AUTH_KEY', '.*' );/define( 'SECURE_AUTH_KEY', '$SECURE_AUTH_KEY' );/g" "$WP_CONFIG_PATH"
sed -i "s/define( 'LOGGED_IN_KEY', '.*' );/define( 'LOGGED_IN_KEY', '$LOGGED_IN_KEY' );/g" "$WP_CONFIG_PATH"
sed -i "s/define( 'NONCE_KEY', '.*' );/define( 'NONCE_KEY', '$NONCE_KEY' );/g" "$WP_CONFIG_PATH"
sed -i "s/define( 'AUTH_SALT', '.*' );/define( 'AUTH_SALT', '$AUTH_SALT' );/g" "$WP_CONFIG_PATH"
sed -i "s/define( 'SECURE_AUTH_SALT', '.*' );/define( 'SECURE_AUTH_SALT', '$SECURE_AUTH_SALT' );/g" "$WP_CONFIG_PATH"
sed -i "s/define( 'LOGGED_IN_SALT', '.*' );/define( 'LOGGED_IN_SALT', '$LOGGED_IN_SALT' );/g" "$WP_CONFIG_PATH"
sed -i "s/define( 'NONCE_SALT', '.*' );/define( 'NONCE_SALT', '$NONCE_SALT' );/g" "$WP_CONFIG_PATH"

if [ $? -eq 0 ]; then
    log_message "wp-config.php has been updated successfully with values from AWS SSM Parameter Store"
else
    error_exit "Failed to update wp-config.php"
fi

log_message "wp-config.php update process completed successfully"