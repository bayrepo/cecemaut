#!/bin/bash

source config.sh

CURRENT_DIR=$(pwd)

CERT_REV=""

# Language detection
if [[ "$LANG" == ru_* || "$LANG" == *ru* ]]; then
    IS_RU=1
else
    IS_RU=0
fi

msg() {
    local ru=$1
    local en=$2
    if [[ $IS_RU -eq 1 ]]; then
        echo "$ru"
    else
        echo "$en"
    fi
}

# Проверка наличия и валидации параметров командной строки
while getopts "s:c:n:h" opt; do
    case $opt in
    s) server=$OPTARG ;;
    c) client=$OPTARG ;;
    n) CERT_REV=$OPTARG ;;
    h)
        msg "Использование: $0 -s <доменное имя сервера> -c <строка имени клиента> -n <номер версии>" "Usage: $0 -s <server domain> -c <client name> -n <version number>"
        exit 0
        ;;
    \?)
        msg "Неверный аргумент или пустой параметр" "Invalid argument or empty parameter" >&2
        msg "Использование: $0 -s <доменное имя сервера> -c <строка имени клиента> -n <номер версии>" "Usage: $0 -s <server domain> -c <client name> -n <version number>" >&2
        exit 1
        ;;
    esac
done

# Если параметры -d и -c не заданы или пусты, вывести сообщение об ошибке и справку
if [[ -z "$server" || -z "$client" ]]; then
    msg "Неверные аргументы или пустые параметры" "Invalid arguments or empty parameters" >&2
    msg "Использование: $0 -s <доменное имя сервера> -c <строка имени клиента> -n <номер версии>" "Usage: $0 -s <server domain> -c <client name> -n <version number>" >&2
    exit 1
fi

if [ ! -e "$PATH_TO_CA/server_certs/$server" ]; then
    msg "Данного ресурса не существует $server" "Resource does not exist: $server" >&2
    exit 1
fi

if [ ! -e "$CLI_CA/$server/${client}_csr_req.cnf" ]; then
    msg "Данного клиента не существует $client" "Client does not exist: $client" >&2
    exit 1
fi

IMM_CA="$PATH_TO_CA/$server"

pushd "$IMM_CA" || {
    msg "Ошибка: не удалось перейти в каталог $IMM_CA" "Error: Could not change directory to $IMM_CA" >&2
    cd "$CURRENT_DIR" || exit 1
}

if [ -z "$CERT_REV" ]; then
    files=("$CLI_CA/$server/${client}.cert.pem".*)
else
    files=("$CLI_CA/$server/${client}.cert.pem.$CERT_REV")
fi

for file in "${files[@]}"; do
    if [ -e "$file" ]; then
        if ! openssl ca -config "immissuer.conf" -revoke "$file" -passin "pass:$SERT_PASS"; then
            msg "Ошибка при выполнении команды openssl ca -revoke" "Error executing openssl ca -revoke" >&2
            cd "$CURRENT_DIR" || exit 1
        fi
    fi
done

if ! openssl ca -config "immissuer.conf" -gencrl -out crl/intermediate.crl.pem -passin "pass:$SERT_PASS"; then
    msg "Ошибка при выполнении команды openssl ca -gencrl" "Error executing openssl ca -gencrl" >&2
    cd "$CURRENT_DIR" || exit 1
fi

if ! openssl crl -in crl/intermediate.crl.pem -noout -text; then
    msg "Ошибка при выполнении команды openssl crl" "Error executing openssl crl" >&2
    cd "$CURRENT_DIR" || exit 1
fi

cat $ROOT_CA/crl/ca.crl.pem $IMM_CA/crl/intermediate.crl.pem >$IMM_CA/crl/ca-full.crl.pem

popd || {
    msg "Ошибка: не удалось выйти из каталога $IMM_CA" "Error: Could not popd from $IMM_CA" >&2
    cd "$CURRENT_DIR" || exit 1
}
