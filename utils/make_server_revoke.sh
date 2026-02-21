#!/bin/bash

source config.sh

CURRENT_DIR=$(pwd)

CERT_REV=""

# Detect language: Russian if LANG or LC_ALL starts with 'ru'
if [[ "${LANG:-$LC_ALL}" =~ ^ru|^ru_RU ]]; then
    IS_RUSSIAN=1
else
    IS_RUSSIAN=0
fi

# Helper to print messages in the appropriate language
msg() {
    local en="$1"
    local ru="$2"
    if [ "$IS_RUSSIAN" -eq 1 ]; then
        echo "$ru"
    else
        echo "$en"
    fi
}

# Проверка наличия и валидации параметров командной строки
while getopts "s:n:h" opt; do
    case $opt in
    s) server=$OPTARG ;;
    n) CERT_REV=$OPTARG ;;
    h)
        msg "Usage: $0 -s <server domain name> -n <certificate reverse number>" "Использование: $0 -s <доменное имя сервера> -n <реверс-номер сертификата>"
        exit 0
        ;;
    \?)
        msg "Invalid argument or missing parameter" "Неверный аргумент или пустой параметр" >&2
        msg "Usage: $0 -s <server domain name> -n <certificate reverse number>" "Использование: $0 -s <доменное имя сервера> -n <реверс-номер сертификата>" >&2
        exit 1
        ;;
    esac
done

if [ -z "$server" ]; then
    msg "Invalid arguments or missing parameters" "Неверные аргументы или пустые параметры" >&2
    msg "Usage: $0 -s <server domain name> -n <certificate reverse number>" "Использование: $0 -s <доменное имя сервера> -n <реверс-номер сертификата>" >&2
    exit 1
fi

if [ ! -e "$PATH_TO_CA/server_certs/$server" ]; then
    msg "Resource does not exist $server" "Данного ресурса не существует $server" >&2
    exit 1
fi

IMM_CA="$PATH_TO_CA/$server"

pushd "$IMM_CA" || {
    msg "Error: Could not change directory to $IMM_CA" "Ошибка: Не удалось перейти в каталог $IMM_CA" >&2
    cd "$CURRENT_DIR" || exit 1
}

if [ -z "$CERT_REV" ]; then
    files=("certs/$server.cert.pem".*)
else
    files=("certs/$server.cert.pem.$CERT_REV")
fi

for file in "${files[@]}"; do
    if [ -e "$file" ]; then
        if ! openssl ca -config "immissuer.conf" -revoke "$file" -passin "pass:$SERT_PASS"; then
            msg "Error executing openssl ca -revoke ($file)" "Ошибка при выполнении команды openssl ca -revoke ($file)" >&2
            cd "$CURRENT_DIR" || exit 1
        fi
    fi
done

if ! openssl ca -config "immissuer.conf" -gencrl -out crl/intermediate.crl.pem -passin "pass:$SERT_PASS"; then
    msg "Error executing openssl ca -gencrl" "Ошибка при выполнении команды openssl ca -gencrl" >&2
    cd "$CURRENT_DIR" || exit 1
fi

if ! openssl crl -in crl/intermediate.crl.pem -noout -text; then
    msg "Error executing openssl crl" "Ошибка при выполнении команды openssl crl" >&2
    cd "$CURRENT_DIR" || exit 1
fi

cat $ROOT_CA/crl/ca.crl.pem $IMM_CA/crl/intermediate.crl.pem >$IMM_CA/crl/ca-full.crl.pem

popd || {
    msg "Error: Could not popd from $IMM_CA" "Ошибка: Не удалось выполнить popd из $IMM_CA" >&2
    cd "$CURRENT_DIR" || exit 1
}
