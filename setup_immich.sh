#!/bin/bash
set -euo pipefail

# Set log file in user-accessible directory
LOG_FILE="$HOME/logs/system_validation.log"
sudo mkdir -p "$(dirname "$LOG_FILE")"
exec > >(tee -a "$LOG_FILE") 2>&1

## Define Variables
XANO_BASE="/XANO"
XANO_CONFIG="$XANO_BASE/appdata/immich"


# Set the user who ran sudo
USER_NAME=${SUDO_USER:-$(whoami)}

## Create XANO and AppData Directories
echo "### Creating /XANO/appdata Directories ###"
sudo mkdir -p "$XANO_CONFIG"
sudo chown -R $USER_NAME:$USER_NAME "$XANO_BASE"
sudo chmod -R 755 "$XANO_BASE"

## Prompt for Database Password
echo "### Configure Database Password ###"
while true; do
    read -rsp "Enter a strong database password (avoid special characters): " DB_PASSWORD
    echo
    read -rsp "Confirm password: " DB_PASSWORD_CONFIRM
    echo
    if [[ "$DB_PASSWORD" == "$DB_PASSWORD_CONFIRM" ]]; then
        break
    else
        echo "Passwords do not match. Please try again."
    fi
done

## Setting up Immich Configuration
echo "### Setting up Immich Configuration ###"
cd "$XANO_CONFIG"

## Download Docker Compose File
sudo wget -O docker-compose.yml https://github.com/cityplug/xano/blob/main/docker-compose.yml

## Create .env File
echo "### Creating .env File ###"
sudo tee .env > /dev/null << EOF
# You can find documentation for all the supported env variables at https://immich.app/docs/install/environment-variables

# The location where your uploaded files are stored
UPLOAD_LOCATION=/XANO/appdata/immich/library
# The location where your database files are stored
DB_DATA_LOCATION=/XANO/appdata/immich/postgres

# Set timezone
TZ=Europe/London

# The Immich version to use. You can pin this to a specific version like "v1.71.0"
IMMICH_VERSION=release

# Connection secret for postgres
# Please use only alphanumeric characters (A-Z, a-z, 0-9), without special characters or spaces
DB_PASSWORD=$DB_PASSWORD

# The values below this line do not need to be changed
###################################################################################
DB_USERNAME=postgres
DB_DATABASE_NAME=immich
EOF

## Set Proper Permissions
echo "### Setting Permissions for .env File ###"
sudo chmod 600 .env
sudo chown $USER_NAME:$USER_NAME .env

## Configure UFW for Immich
echo "### Configuring UFW for Immich ###"
sudo ufw allow 2283/tcp  # Immich Server
sudo ufw allow 2284/tcp  # Immich Web Interface
sudo ufw allow 5432/tcp  # PostgreSQL Database (if needed)
sudo ufw allow 6379/tcp  # Redis (if needed)
echo "### UFW Rules Applied ###"

## Start Immich Services
echo "### Starting Immich Services ###"
cd "$XANO_CONFIG"
docker compose up -d && docker ps
docker-compose logs -f

echo "### Immich Services Started ###"

## Done
echo "### Immich Setup Complete ###"