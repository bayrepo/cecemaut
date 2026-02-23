#!/bin/bash

# Этот скрипт предназначен для генерации серверных сертификатов для указанных доменов или IP-адресов.
# Он создает приватный ключ, запрос на подпись сертификата (CSR) и сам сертификат,
# используя конфигурационные файлы и инфраструктуру центра сертификации (CA).
# Скрипт также выводит информацию о сгенерированных ключах и сертификатах.

source ./config.sh

# Detect language and define error function
LANGUAGE="en"
if [[ "$LANG" == ru* || "$LANG" == *ru_* || "$LC_ALL" == ru* || "$LC_ALL" == *ru_* ]]; then
    LANGUAGE="ru"
fi

msg() {
    local en_msg="$1"
    local ru_msg="$2"
    if [[ "$LANGUAGE" == "ru" ]]; then
        echo "$ru_msg"
    else
        echo "$en_msg"
    fi
    exit 1
}

# Handle -h option for help message
if [ "$1" == "-h" ]; then
    if [ "$LANGUAGE" == "ru" ]; then
        echo "Использование: $0 [-h] [-t|--days DAYS] [domain1, domain2, ...]"
        echo "Создает сертификаты сервера для указанных доменов или IP."
        echo
        echo "Опции:"
        echo "  -h    Показать это сообщение"
        echo "  -t|--days DAYS   Установить срок действия сертификата (по умолчанию: 3650 дней)"
    else
        echo "Usage: $0 [-h] [-t|--days DAYS] [domain1, domain2, ...]"
        echo "Generate server certificates for the given domains or IPs."
        echo
        echo "Options:"
        echo "  -h    Display this help message"
        echo "  -t|--days DAYS   Set the number of days the certificate is valid for (default: 3650)"
    fi
    exit 0
fi

# Чтение параметра -t через getopt для установки числа дней действия сертификата
while true; do
    case "$1" in
    -t | --days)
        CERT_DAYS="$2"
        shift 2
        break
        ;;
    -h | --help)
        if [ "$LANGUAGE" == "ru" ]; then
            echo "Использование: $0 [-h] [-t|--days DAYS] [domain1, domain2, ...]"
            echo "Создает сертификаты сервера для указанных доменов или IP."
            echo
            echo "Опции:"
            echo "  -h    Показать это сообщение"
            echo "  -t|--days DAYS   Установить срок действия сертификата (по умолчанию: 3650 дней)"
        else
            echo "Usage: $0 [-h] [-t|--days DAYS] [domain1, domain2, ...]"
            echo "Generate server certificates for the given domains or IPs."
            echo
            echo "Options:"
            echo "  -h    Display this help message"
            echo "  -t|--days DAYS   Set the number of days the certificate is valid for (default: 3650)"
        fi
        exit 0
        ;;
    *) break ;;
    esac
done

# Если параметр не указан, используем значение по умолчанию
CERT_DAYS=${CERT_DAYS:-3650}

pushd $PATH_TO_CA || exit

# Проверка, предоставлен ли первый параметр и не пуст ли он
if [ -z "$1" ]; then
    msg "No input provided" "Нет входных данных"
fi

# Разделение входной строки в массив с использованием запятых или пробелов как разделителей
IFS=', ' read -r -a items <<<"$1"

# Проверка, есть ли хотя бы один элемент в списке
if [ "${#items[@]}" -eq 0 ]; then
    msg "No elements found in the input" "Входные данные пусты"
    popd || exit
fi

SEQ="1"

# Извлечение первого элемента списка
fst_elem="${items[0]}"

IMM_CA="$PATH_TO_CA/$fst_elem"

# Создаем промежуточный CA
if [ ! -d "$IMM_CA" ]; then

    # Список каталогов, для которых создается структура
    DIRECTORIES=("$fst_elem")

    # Создание необходимых директорий и настройка их прав доступа
    for dir in "${DIRECTORIES[@]}"; do
        # Создание поддиректорий в каждой директории из списка
        mkdir -p "$dir/certs" "$dir/crl" "$dir/newcerts" "$dir/private" "$dir/csr"
        chmod 700 "$dir/private"

        # Создание файлов базы CA
        touch "$dir/index.txt"
        echo -n 100000 >"$dir/serial"

        # Настройка файла для CRL (список отозванных сертификатов)
        echo -n 100000 >"$dir/crlnumber"
    done

    cat >$IMM_CA/immissuer.conf <<EOL
[ca]
default_ca=CA_default

[CA_default]
dir               = $IMM_CA
certs             = \$dir/certs
crl_dir           = \$dir/crl
database          = \$dir/index.txt
new_certs_dir     = \$dir/newcerts
serial            = \$dir/serial

certificate       = \$dir/certs/intermediate.cert.pem
private_key       = \$dir/private/intermediate.key.pem
crlnumber         = \$dir/crlnumber
crl               = \$dir/crl/intermediate.crl.pem
crl_extensions    = crl_ext
default_crl_days  = 7

default_md        = sha256
name_opt          = ca_default
cert_opt          = ca_default
default_days      = 825
preserve          = no
policy            = policy_loose

[policy_loose]
countryName             = optional
stateOrProvinceName     = optional
localityName            = optional
organizationName        = optional
organizationalUnitName  = optional
commonName              = supplied
emailAddress            = optional

[req]
default_bits        = 4096
default_md          = sha256
default_keyfile     = privkey.pem
distinguished_name  = req_distinguished_name
string_mask         = utf8only
x509_extensions     = v3_intermediate_ca
prompt              = no

[req_distinguished_name]
countryName                     = $COUNTRY_NAME
organizationName                = $ORG_NAME
commonName                      = $fst_elem

[v3_intermediate_ca]
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid:always,issuer
basicConstraints = critical, CA:true, pathlen:0
keyUsage = critical, keyCertSign, cRLSign

[server_cert]
basicConstraints = CA:false
nsCertType = server
nsComment = "$COMM_NAME TLS server cert"
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid,issuer
keyUsage = critical, digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth

[client_cert]
basicConstraints = CA:false
nsCertType = client
nsComment = "Brepo client cert"
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid,issuer
keyUsage = critical, digitalSignature, keyEncipherment
extendedKeyUsage = clientAuth

[crl_ext]
authorityKeyIdentifier = keyid:always
EOL

    # Перейти в директорию промежуточного ЦА или выйти с ошибкой, если это не удалось
    pushd "$IMM_CA" || msg "Error: Failed to change directory to $IMM_CA" "Ошибка: Не удалось перейти в каталог $IMM_CA"

    # Генерация RSA ключа для промежуточного ЦА с шифрованием AES-256
    openssl genrsa -aes256 -out private/intermediate.key.pem -passout "pass:$SERT_PASS" 4096 || msg "Error: Failed to generate RSA key for intermediate CA" "Ошибка: Не удалось создать RSA‑ключ для промежуточного ЦА"

    # Установка прав доступа для ключа промежуточного ЦА
    chmod 400 private/intermediate.key.pem

    # Создание CSR для промежуточного ЦА
    openssl req -config immissuer.conf -new -sha256 -key private/intermediate.key.pem -out csr/intermediate.csr.pem -passin "pass:$SERT_PASS" || msg "Error: Failed to create CSR for intermediate CA" "Ошибка: Не удалось создать запрос на сертификат для промежуточного ЦА"

    # Вернуться в исходную директорию или выйти с ошибкой, если это не удалось
    popd || msg "Can't return to old directory" "Невозможно вернуться к старому каталогу"

    # Перейти в директорию корневого ЦА или выйти с ошибкой, если это не удалось
    pushd "$ROOT_CA" || msg "Error: Failed to change directory to $ROOT_CA" "Ошибка: Не удалось перейти в каталог $ROOT_CA"

    # Подпись сертификата промежуточного ЦА корневым ЦА
    openssl ca -batch -config sertissuer.conf -extensions v3_inter -days 3550 -notext -md sha256 -in $IMM_CA/csr/intermediate.csr.pem -out $IMM_CA/certs/intermediate.cert.pem -passin "pass:$SERT_PASS" || msg "Error: Failed to sign intermediate CA certificate" "Ошибка: Не удалось подписать сертификат промежуточного ЦА корневым ЦА"

    # Установка прав доступа для сертификата промежуточного ЦА
    chmod 444 "$IMM_CA/certs/intermediate.cert.pem"

    openssl ca -config "sertissuer.conf" -gencrl -out crl/ca.crl.pem -passin "pass:$SERT_PASS"

    # Вернуться в исходную директорию или выйти с ошибкой, если это не удалось
    popd || msg "Can't return to old directory" "Невозможно вернуться к старому каталогу"

    # Перейти в директорию промежуточного ЦА или выйти с ошибкой, если это не удалось
    pushd "$IMM_CA" || msg "Error: Failed to change directory to $IMM_CA" "Ошибка: Не удалось перейти в каталог $IMM_CA"

    openssl ca -config "immissuer.conf" -gencrl -out crl/intermediate.crl.pem -passin "pass:$SERT_PASS"

    cat $ROOT_CA/crl/ca.crl.pem "$IMM_CA/crl/intermediate.crl.pem" >"$IMM_CA/crl/ca-full.crl.pem"

    # Вернуться в исходную директорию или выйти с ошибкой, если это не удалось
    popd || msg "Can't return to old directory" "Невозможно вернуться к старому каталогу"

    # Создание цепочки сертификатов
    cat "$IMM_CA/certs/intermediate.cert.pem" "$ROOT_CA/certs/ca.cert.pem" >"$IMM_CA/certs/ca-chain.cert.pem" || msg "Error: Failed to create CA chain certificate" "Ошибка: Не удалось создать цепочку сертификатов ЦА"

    # Проверка сертификата промежуточного ЦА с использованием корневого центра сертификации
    openssl verify -CAfile "$ROOT_CA/certs/ca.cert.pem" "$IMM_CA/certs/intermediate.cert.pem" || msg "Error: Failed to verify intermediate CA certificate" "Ошибка: Не удалось проверить сертификат промежуточного ЦА"
fi
# Конец создания промежуточного CA

mkdir -p server_certs

pushd server_certs || exit

# Создание директории с именем первого элемента, если она не существует
mkdir -p "$fst_elem" || true

if [ ! -e "$fst_elem/csr_req.cnf" ]; then

    echo -n "2" >"$fst_elem/${fst_elem}_seq.seq"

    # Создание файла csr_api.cnf с необходимым содержимым
    cat <<EOF >"$fst_elem/csr_req.cnf"
[req]
default_bits       = 2048
default_md         = sha256
prompt             = no
distinguished_name = dn
req_extensions     = req_ext

[dn]
CN = $fst_elem
O = ${ORG_NAME}:$SEQ

[req_ext]
subjectAltName = @alt_names

[alt_names]
EOF

    # Добавление записей DNS для доменных имен и записей IP для IP-адресов
    dns_count=1
    ip_count=1

    for item in "${items[@]}"; do
        if [[ "$item" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
            echo "IP.$ip_count = $item" >>"$fst_elem/csr_req.cnf"
            ((ip_count++))
        else
            echo "DNS.$dns_count = $item" >>"$fst_elem/csr_req.cnf"
            ((dns_count++))
        fi
    done

    popd || exit

    pushd "$IMM_CA" || msg "Error: Could not change directory to $IMM_CA" "Ошибка: не удалось перейти в каталог $IMM_CA"

    openssl genrsa -out "private/$fst_elem.key.pem" -passout "pass:$SERT_PASS" 2048
    chmod 400 "private/$fst_elem.key.pem"
else
    SEQ=$(cat "$fst_elem/${fst_elem}_seq.seq")
    echo $((SEQ + 1)) >"$fst_elem/${fst_elem}_seq.seq"

    sed -i "s/^O = .*/O = ${ORG_NAME}:${SEQ}/" "${fst_elem}/csr_req.cnf"

    pushd "$IMM_CA" || msg "Error: Could not change directory to $IMM_CA" "Ошибка: не удалось перейти в каталог $IMM_CA"

fi

# Генерация запроса на подпись сертификата (CSR)
openssl req -new -sha256 -key "private/$fst_elem.key.pem" -out "csr/$fst_elem.csr.pem" -config "../server_certs/$fst_elem/csr_req.cnf"

# Подписание CSR и создание сертификата
openssl ca -batch -config "immissuer.conf" -extensions server_cert -days "$CERT_DAYS" -notext -md sha256 -in "csr/$fst_elem.csr.pem" -out "certs/$fst_elem.cert.pem.$SEQ" -passin "pass:$SERT_PASS"
chmod 444 "certs/$fst_elem.cert.pem.$SEQ"

# Вывод информации о сертификате
openssl x509 -noout -text -in "certs/$fst_elem.cert.pem.$SEQ"

# Информирование пользователя о сгенерированных ключах и сертификатах
if [ "$LANGUAGE" == "ru" ]; then
    cat <<EOF
Сгенерированный набор ключей для установки на сервер:

-   [OUTPUTDATA] приватный ключ: \`$IMM_CA/private/$fst_elem.key.pem\`;
-   [OUTPUTDATA_CERT] сертификат сервера: \`$IMM_CA/certs/$fst_elem.cert.pem.$SEQ\`;
-   [OUTPUTDATA] цепочка CA: \`$IMM_CA/certs/ca-chain.cert.pem\`;
-   [OUTPUTDATA] список отмененных сертификатов: \`$IMM_CA/crl/ca-full.crl.pem\`
EOF
else
    cat <<EOF
Generated key set for server installation:

-   [OUTPUTDATA] private key: \`$IMM_CA/private/$fst_elem.key.pem\`;
-   [OUTPUTDATA_CERT] server certificate: \`$IMM_CA/certs/$fst_elem.cert.pem.$SEQ\`;
-   [OUTPUTDATA] CA chain: \`$IMM_CA/certs/ca-chain.cert.pem\`;
-   [OUTPUTDATA] revoked certificates list: \`$IMM_CA/crl/ca-full.crl.pem\`
EOF
fi

popd || exit

popd || exit
