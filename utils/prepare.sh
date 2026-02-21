#!/bin/bash

# Этот скрипт автоматизирует процесс создания инфраструктуры центра сертификации (ЦС),
# включая создание директорий, генерацию ключей и сертификатов,
# а также настройку конфигурационных файлов для корневого и промежуточного ЦА.
#
# Скрипт выполняет следующие основные действия:
# 1. Создает необходимые директории для хранения сертификатов, ключей и других файлов ЦС.
# 2. Генерирует RSA ключи для корневого и промежуточного ЦА с шифрованием AES-256.
# 3. Создает самоподписанный корневой сертификат и CSR (Certificate Signing Request)
#    для промежуточного ЦА.
# 4. Подписывает сертификат промежуточного ЦА корневым ЦА.
# 5. Создает цепочку сертификатов, включающую корневой и промежуточный сертификаты.
# 6. Проверяет целостность созданного сертификата промежуточного ЦА с помощью корневого ЦА.
#
# Для использования скрипта рекомендуется запускать его с правами суперпользователя (root),
# так как он создает файлы и директории в защищенных системных папках.

#set -e
#trap 'echo "Error: Script execution failed"; exit 1' ERR

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

# Проверка переменной VAL_DAYS
if [[ -z "$VAL_DAYS" || ! "$VAL_DAYS" =~ ^[0-9]+$ || "$VAL_DAYS" -le 0 ]]; then
    msg "Error: VAL_DAYS must be a positive integer" "Ошибка: Переменная VAL_DAYS должна быть положительным целым числом"
fi

if ! mkdir -m 700 "$PATH_TO_CA"; then
    msg "Error: Failed to create directory $PATH_TO_CA" "Ошибка: Не удалось создать директорию $PATH_TO_CA"
fi

# Перейти в директорию CA или выйти с ошибкой, если это не удалось
cd "$PATH_TO_CA" || { msg "Error: Failed to change directory to $PATH_TO_CA" "Ошибка: Не удалось перейти в каталог $PATH_TO_CA"; }

# Список каталогов, для которых создается структура
DIRECTORIES=("root")

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

# Создание конфигурационного файла для корневого ЦА
cat >root/sertissuer.conf <<EOL
[ca]
default_ca=CA_default

[CA_default]
dir               = $ROOT_CA
certs             = \$dir/certs
crl_dir           = \$dir/crl
database          = \$dir/index.txt
new_certs_dir     = \$dir/newcerts
serial            = \$dir/serial

certificate       = \$dir/certs/ca.cert.pem
private_key       = \$dir/private/ca.key.pem
crlnumber         = \$dir/crlnumber
crl               = \$dir/crl/ca.crl.pem
crl_extensions    = crl_ext
default_crl_days  = 30

default_md        = sha256
name_opt          = ca_default
cert_opt          = ca_default
default_days      = $VAL_DAYS
preserve          = no
policy            = policy_strict

[policy_strict]
countryName             = match
stateOrProvinceName     = optional
organizationName        = match
organizationalUnitName  = optional
commonName              = supplied
emailAddress            = optional

[req]
default_bits        = 4096
default_md          = sha256
default_keyfile     = privkey.pem
distinguished_name  = req_distinguished_name
string_mask         = utf8only
x509_extensions     = v3_ca
prompt              = no

[req_distinguished_name]
countryName                     = $COUNTRY_NAME
organizationName                = $ORG_NAME
commonName                      = $COMM_NAME

[v3_ca]
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid:always,issuer
basicConstraints = critical, CA:true
keyUsage = critical, keyCertSign, cRLSign

[v3_inter]
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid:always,issuer
basicConstraints = critical, CA:true
keyUsage = critical, keyCertSign, cRLSign

[crl_ext]
authorityKeyIdentifier = keyid:always
EOL

# Перейти в директорию корневого ЦА или выйти с ошибкой, если это не удалось
pushd "$ROOT_CA" || { msg "Error: Failed to change directory to $ROOT_CA" "Ошибка: Не удалось перейти в каталог $ROOT_CA"; }

# Генерация RSA ключа для корневого ЦА с шифрованием AES-256
openssl genrsa -aes256 -out private/ca.key.pem -passout "pass:$SERT_PASS" 4096 || { msg "Error: Failed to generate RSA key for root CA" "Ошибка: Не удалось создать RSA‑ключ для корневого ЦА"; }

# Установка прав доступа для ключа корневого ЦА
chmod 400 private/ca.key.pem

# Создание самоподписанного сертификата корневого ЦА
openssl req -config sertissuer.conf -key private/ca.key.pem -new -x509 -days "$VAL_DAYS" -sha256 -extensions v3_ca -out certs/ca.cert.pem -passin "pass:$SERT_PASS" || { msg "Error: Failed to create root CA certificate" "Ошибка: Не удалось создать сертификат корневого ЦА"; }

# Установка прав доступа для сертификата корневого ЦА
chmod 444 certs/ca.cert.pem

# Отображение деталей сертификата корневого ЦА
openssl x509 -noout -text -in certs/ca.cert.pem || { msg "Error: Failed to display root CA certificate details" "Ошибка: Не удалось вывести детали сертификата корневого ЦА"; }

# Вернуться в исходную директорию или выйти с ошибкой, если это не удалось
popd || { msg "Can't return to old directory" "Невозможно вернуться к старому каталогу"; }

exit 0
