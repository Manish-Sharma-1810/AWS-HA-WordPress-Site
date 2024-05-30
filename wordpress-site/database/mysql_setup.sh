#!/bin/bash

# Enable strict error handling
set -euo pipefail

# Ensure the script is being run as root
if [ "$(id -u)" -ne 0 ]; then
    echo "This script must be run as root." >&2
    exit 1
fi

# Log file location
LOG_FILE="/var/log/mysql_setup.log"

# Redirect all output to the log file
exec &> >(tee -a "$LOG_FILE")


# Function to generate a strong password of specified length
generate_password() {
  local length=$1
  tr -dc 'A-Za-z0-9!@#$%^&*()-_=+{}[]|:;,.<>?/~' < /dev/urandom | head -c ${length}
  echo
}

# Set default values for environment variables
DEFAULT_PASSWORD_LENGTH=16
DEFAULT_MYSQL_ADMIN_USER="admin"
DEFAULT_MYSQL_WP_USER="wp_user"
DEFAULT_MYSQL_WP_DATABASE="wordpress_db"
DEFAULT_MYSQL_CONFIG_FILE="/etc/mysql/mysql.conf.d/mysqld.cnf"

# Override default values if environment variables are provided
PASSWORD_LENGTH=${PASSWORD_LENGTH:-$DEFAULT_PASSWORD_LENGTH}
MYSQL_ROOT_PASSWORD=$(generate_password $PASSWORD_LENGTH)
MYSQL_ADMIN_USER=${MYSQL_ADMIN_USER:-$DEFAULT_MYSQL_ADMIN_USER}
MYSQL_ADMIN_USER_PASSWORD=$(generate_password $PASSWORD_LENGTH)
MYSQL_WP_USER=${MYSQL_WP_USER:-$DEFAULT_MYSQL_WP_USER}
MYSQL_WP_USER_PASSWORD=$(generate_password $PASSWORD_LENGTH)
MYSQL_WP_DATABASE=${MYSQL_WP_DATABASE:-$DEFAULT_MYSQL_WP_DATABASE}
MYSQL_CONFIG_FILE=${MYSQL_CONFIG_FILE:-$DEFAULT_MYSQL_CONFIG_FILE}
DB_HOST=${DB_HOST}

# Function to output messages
function log() {
    echo "[$(date +'%Y-%m-%dT%H:%M:%S%z')]: $@"
}

# Update and install MySQL if not already installed
if ! dpkg -l | grep -q mysql-server; then
    log "Updating package list and installing MySQL server."
    apt-get update
    apt-get install -y mysql-server
else
    log "MySQL server is already installed."
fi

# Start MySQL service
log "Starting and enabling MySQL service."
systemctl start mysql
systemctl enable mysql

# Secure MySQL installation
log "Securing MySQL installation."
mysql <<EOF
ALTER USER 'root'@'localhost' IDENTIFIED WITH 'mysql_native_password' BY '${MYSQL_ROOT_PASSWORD}';
DELETE FROM mysql.user WHERE User='';
DROP DATABASE IF EXISTS test;
DELETE FROM mysql.db WHERE Db='test' OR Db='test_%';
FLUSH PRIVILEGES;
EOF

# Create a new MySQL database (wordpress_db) for WordPress
log "Creating a new MySQL database for WordPress."
mysql -u root -p"${MYSQL_ROOT_PASSWORD}" <<EOF
CREATE DATABASE IF NOT EXISTS ${MYSQL_WP_DATABASE} CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
USE ${MYSQL_WP_DATABASE};
CREATE TABLE IF NOT EXISTS wp_users (
    id INT AUTO_INCREMENT PRIMARY KEY,
    username VARCHAR(50) NOT NULL,
    password VARCHAR(255) NOT NULL,
    email VARCHAR(100) NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
EOF

# Create a new MySQL user (admin) for localhost and grant all privileges
log "Creating a new MySQL admin user for localhost and granting privileges."
mysql -u root -p"${MYSQL_ROOT_PASSWORD}" <<EOF
CREATE USER '${MYSQL_ADMIN_USER}'@'localhost' IDENTIFIED BY '${MYSQL_ADMIN_USER_PASSWORD}';
GRANT ALL PRIVILEGES ON *.* TO '${MYSQL_ADMIN_USER}'@'localhost' WITH GRANT OPTION;
FLUSH PRIVILEGES;
EOF

# Create a new MySQL user (wp_user) for remote access and grant Grant the necessary permissions on the wordpress_db
log "Creating a new MySQL user for remote access for wordpress site and granting necessary privileges on the wordpress_db."
mysql -u root -p"${MYSQL_ROOT_PASSWORD}" <<EOF
CREATE USER '${MYSQL_WP_USER}'@'10.0.%' IDENTIFIED BY '${MYSQL_WP_USER_PASSWORD}';
GRANT SELECT, INSERT, UPDATE, DELETE, CREATE, ALTER, INDEX, LOCK TABLES ON ${MYSQL_WP_DATABASE}.* TO '${MYSQL_WP_USER}'@'10.0.%';
FLUSH PRIVILEGES;
EOF

# Update MySQL configuration to allow remote connections
log "Updating MySQL configuration to allow remote connections."
sed -i "s/^bind-address\s*=.*$/bind-address = 0.0.0.0/" "${MYSQL_CONFIG_FILE}"
systemctl restart mysql

# Allow MySQL through UFW firewall
log "Allowing MySQL through the UFW firewall."
ufw allow 3306/tcp

# Define AWS SSM parameter path
SSM_MYSQL_PARAM_PATH="/mysql"
SSM_WORDPRESS_PARAM_PATH="/wordpress"

# Store all the credentials in the AWS parameter store
log "Storing all the MySQL credentials in the AWS parameter store."
aws ssm put-parameter --name "${SSM_MYSQL_PARAM_PATH}/root_password" --value "${MYSQL_ROOT_PASSWORD}" --type SecureString --overwrite
aws ssm put-parameter --name "${SSM_MYSQL_PARAM_PATH}/admin_user" --value "${MYSQL_ADMIN_USER}" --type String --overwrite
aws ssm put-parameter --name "${SSM_MYSQL_PARAM_PATH}/admin_user_password" --value "${MYSQL_ADMIN_USER_PASSWORD}" --type SecureString --overwrite
aws ssm put-parameter --name "${SSM_MYSQL_PARAM_PATH}/wp_user" --value "${MYSQL_WP_USER}" --type String --overwrite
aws ssm put-parameter --name "${SSM_MYSQL_PARAM_PATH}/wp_user_password" --value "${MYSQL_WP_USER_PASSWORD}" --type SecureString --overwrite
aws ssm put-parameter --name "${SSM_MYSQL_PARAM_PATH}/wp_database" --value "${MYSQL_WP_DATABASE}" --type String --overwrite
aws ssm put-parameter --name "${SSM_MYSQL_PARAM_PATH}/db_host" --value "${DB_HOST}" --type String --overwrite

# Get keys and salts from wordpress-api
log "Getting keys and salts from wordpress-api."
response=$(curl -s https://api.wordpress.org/secret-key/1.1/salt/)

# Process each line to extract the key and value, then store them in AWS SSM Parameter Store
log "Storing keys and salts in the AWS SSM Parameter Store."
while IFS= read -r line; do
    key=$(echo "$line" | awk -F "'" '{print $2}')
    value=$(echo "$line" | awk -F "'" '{print $4}')
    parameter_name="${SSM_WORDPRESS_PARAM_PATH}/$key"
    aws ssm put-parameter --name "$parameter_name" --value "$value" --type SecureString --overwrite
done <<< "$response"

log "MySQL setup is complete."
log "MySQL admin user: ${MYSQL_ADMIN_USER}"
log "MySQL wordpress user: ${MYSQL_WP_USER}"
log "MySQL wordpress database: ${MYSQL_WP_DATABASE}"
log "MySQL db_host: ${DB_HOST}"
log "MySQL configuration file: ${MYSQL_CONFIG_FILE}"
