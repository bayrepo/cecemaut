#!/bin/bash

# Описание: Этот скрипт генерирует беспарольный публичный и приватный ключ с помощью openssl.
# Путь к файлу указывается в первом обязательном параметре, если он не указан,
# то показывается help или usage. Если путь не существует, то сообщает об ошибке и завершает работу.

# Определяем язык вывода
if [[ "$LANG" =~ ^ru|RU ]]; then
    USE_RU=1
else
    USE_RU=0
fi

if [ -z "$1" ] || [ ! -e "$1" ]; then
    if [ "$USE_RU" -eq 1 ]; then
        echo "Использование: $0 <путь>"
    else
        echo "Usage: $0 <path>"
    fi
    exit 1
fi

PATH_TO_KEYS=$1

if [ ! -e "$PATH_TO_KEYS" ]; then
    if [ "$USE_RU" -eq 1 ]; then
        echo "Такого пути $PATH_TO_KEYS не существует"
    else
        echo "Path $PATH_TO_KEYS does not exist"
    fi
    exit 1
fi

openssl genpkey -algorithm RSA -out "$PATH_TO_KEYS/caapp.private.key.pem" -pkeyopt rsa_keygen_bits:2048
openssl rsa -in "$PATH_TO_KEYS/caapp.private.key.pem" -pubout -out "$PATH_TO_KEYS/caapp.public.key.pem"

if [ "$USE_RU" -eq 1 ]; then
    echo "Беспарольный публичный $PATH_TO_KEYS/caapp.public.key.pem и приватный $PATH_TO_KEYS/caapp.private.key.pem ключи созданы по пути"
else
    echo "Passwordless public key $PATH_TO_KEYS/caapp.public.key.pem and private key $PATH_TO_KEYS/caapp.private.key.pem created at path"
fi
