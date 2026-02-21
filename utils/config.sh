#!/bin/bash

if [ -e custom_config.sh ]; then
    source custom_config.sh
else

    ROOT_DIR="."

    COUNTRY_NAME="RU"
    ORG_NAME="Regenal Organization"
    COMM_NAME="General Name"
    SERT_PASS=""

fi

if [ -z "$SERT_PASS" ]; then
    if [[ "$LANG" =~ ^ru ]]; then
        echo "Установите пароль для корневого сертификата и промежуточного"
    else
        echo "Please set a password for the root certificate and intermediate"
    fi
    exit 1
fi

PATH_TO_CA="$ROOT_DIR/ca"
ROOT_CA="$PATH_TO_CA/root"
CLI_CA="$PATH_TO_CA/client_certs"
