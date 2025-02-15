#!/bin/bash
set -euo pipefail
LOG_FILE="/var/log/system_validation.log"
exec > >(tee -a "$LOG_FILE") 2>&1

## Define Variables
XANO_CONFIG="/XANO/appdata"

echo "### Docker Services ###"

mkdir $XANO_CONFIG/immich
cd $XANO_CONFIG/immich

wget -O docker-compose.yml https://github.com/immich-app/immich/releases/latest/download/docker-compose.yml

wget -O .env https://github.com/immich-app/immich/releases/latest/download/example.env