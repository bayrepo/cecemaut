#!/bin/bash
#
# Скрипт для создания клиентских сертификатов для указанного сервера и клиента.
# Генерирует приватный ключ, запрос на сертификат (CSR), подписывает его и выводит информацию о сгенерированном сертификате.
#

source config.sh

CURRENT_DIR=$(pwd)

# Determine language based on locale
if [[ "$LANG" =~ ^ru ]]; then
    USE_RU=true
else
    USE_RU=false
fi

msg() {
    if $USE_RU; then
        printf '%s\n' "$1"
    else
        printf '%s\n' "$2"
    fi
}

# Проверка наличия и валидации параметров командной строки
while getopts "s:c:d:h" opt; do
    case $opt in
    s) server=$OPTARG ;;
    c) client=$OPTARG ;;
    d) days=$OPTARG ;;
    h)
        msg "Использование: $0 -s <доменное имя сервера> -c <строка имени клиента> -d <число дней>" "Usage: $0 -s <server domain> -c <client name string> -d <number of days>"
        exit 0
        ;;
    \?)
        msg "Неверный аргумент или пустой параметр" "Invalid argument or empty parameter" >&2
        msg "Использование: $0 -s <доменное имя сервера> -c <строка имени клиента> -d <число дней>" "Usage: $0 -s <server domain> -c <client name string> -d <number of days>" >&2
        exit 1
        ;;
    esac
done

# Если параметры -d и -c не заданы или пусты, вывести сообщение об ошибке и справку
if [[ -z "$server" || -z "$client" ]]; then
    msg "Неверные аргументы или пустые параметры" "Invalid arguments or empty parameters" >&2
    msg "Использование: $0 -s <доменное имя сервера> -c <строка имени клиента> -d <число дней>" "Usage: $0 -s <server domain> -c <client name string> -d <number of days>" >&2
    exit 1
fi

# Если параметр -d не задан, принять число дней равным 30
if [ -z "$days" ]; then
    days=30
fi

if [ ! -e "$PATH_TO_CA/server_certs/$server" ]; then
    msg "Данного ресурса не существует $server" "Resource $server does not exist" >&2
    exit 1
fi

pushd $PATH_TO_CA || {
    msg "Ошибка: Не удалось перейти в каталог $PATH_TO_CA" "Error: Could not change directory to $PATH_TO_CA" >&2
    cd "$CURRENT_DIR" || exit
    exit 1
}

IMM_CA="$PATH_TO_CA/$server"

mkdir -p client_certs

pushd client_certs || {
    msg "Ошибка: Не удалось перейти в каталог client_certs" "Error: Could not change directory to client_certs" >&2
    cd "$CURRENT_DIR" || exit
    exit 1
}

SEQ="1"

if [ ! -e "$server/${client}_csr_req.cnf" ]; then

    mkdir -p "$server" "$server/private"

    chmod 0700 "$server/private"

    echo -n "2" >"$server/${client}_seq.seq"

    cat <<EOF >"$server/${client}_csr_req.cnf"
[req]
default_bits       = 2048
default_md         = sha256
prompt             = no
distinguished_name = dn
req_extensions     = req_ext

[dn]
CN = $server
O = $client:1

[req_ext]
subjectAltName = @alt_names

[alt_names]
email.1 = $client
EOF

    # Создание запроса на сертификат (CSR) для указанного сервера и клиента
    openssl req -new -sha256 -nodes -keyout "$CLI_CA/$server/private/${client}_private.key.pem" -out "$CLI_CA/$server/${client}.csr.pem.$SEQ" -config "$CLI_CA/$server/${client}_csr_req.cnf" || {
        msg "Error: Failed to create CSR for server certificate" "Error: Failed to create CSR for server certificate" >&2
        cd "$CURRENT_DIR" || exit
        exit 1
    }

    chmod 0400 "$CLI_CA/$server/private/${client}_private.key.pem"
else
    # Чтение файла "$server/${client}_seq.seq" и его значение сохраняется в переменной SEQ, а в файл без переноса строки записывается новое значение SEQ+1
    SEQ=$(cat "$server/${client}_seq.seq")
    echo $((SEQ + 1)) >"$server/${client}_seq.seq"

    # Парсинг файла "$server/${client}_csr_req.cnf" и замена значения ключа O на $client:$SEQ
    sed -i "s/^O = .*/O = $client:$SEQ/" "$server/${client}_csr_req.cnf"

    openssl req -new -sha256 -key "$CLI_CA/$server/private/${client}_private.key.pem" -out "$CLI_CA/$server/${client}.csr.pem.$SEQ" -config "$CLI_CA/$server/${client}_csr_req.cnf" || {
        msg "Error: Failed to create CSR for server certificate" "Error: Failed to create CSR for server certificate" >&2
        cd "$CURRENT_DIR" || exit
        exit 1
    }
fi

popd || {
    msg "Ошибка: Не удалось вернуться из каталога client_certs" "Error: Could not popd from client_certs" >&2
    cd "$CURRENT_DIR" || exit
    exit 1
}

pushd "$IMM_CA" || {
    msg "Ошибка: Не удалось перейти в каталог $IMM_CA" "Error: Could not change directory to $IMM_CA" >&2
    cd "$CURRENT_DIR" || exit
    exit 1
}

# Подпись CSR сертификатом CA
openssl ca -batch -config "immissuer.conf" -extensions client_cert -days "$days" -notext -md sha256 -in "$CLI_CA/$server/${client}.csr.pem.$SEQ" -out "$CLI_CA/$server/${client}.cert.pem.$SEQ" -passin "pass:$SERT_PASS" || {
    msg "Ошибка: Не удалось подписать сертификат сервера" "Error: Failed to sign the server certificate" >&2
    cd "$CURRENT_DIR" || exit
    exit 1
}
chmod 644 "$CLI_CA/$server/${client}.cert.pem.$SEQ"

# Вывод информации о сгенерированном сертификате
openssl x509 -noout -text -in "$CLI_CA/$server/${client}.cert.pem.$SEQ" || {
    msg "Ошибка: Не удалось отобразить информацию о сертификате сервера" "Error: Failed to display the server certificate information" >&2
    cd "$CURRENT_DIR" || exit
    exit 1
}

if $USE_RU; then
    cat <<EOF
Сгенерированный набор ключей для установки на машину клиента для доступа:

-   [OUTPUTDATA] приватный ключ: \`$CLI_CA/$server/private/${client}_private.key.pem\`;
-   [OUTPUTDATA_CERT] сертификат сервера: \`$CLI_CA/$server/${client}.cert.pem.$SEQ\`;
-   [OUTPUTDATA] цепочка CA: \`$IMM_CA/certs/ca-chain.cert.pem\`.
EOF
else
    cat <<EOF
Generated key set for client machine:

-   [OUTPUTDATA] private key: \`$CLI_CA/$server/private/${client}_private.key.pem\`;
-   [OUTPUTDATA_CERT] server certificate: \`$CLI_CA/$server/${client}.cert.pem.$SEQ\`;
-   [OUTPUTDATA] CA chain: \`$IMM_CA/certs/ca-chain.cert.pem\`.
EOF
fi

popd || {
    msg "Ошибка: Не удалось вернуться из каталога $IMM_CA" "Error: Could not popd from $IMM_CA" >&2
    cd "$CURRENT_DIR" || exit
    exit 1
}

popd || {
    msg "Ошибка: Не удалось вернуться из каталога $PATH_TO_CA" "Error: Could not popd from $PATH_TO_CA" >&2
    cd "$CURRENT_DIR" || exit
    exit 1
}
