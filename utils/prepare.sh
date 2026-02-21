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
DIRECTORIES=("root" "intermediate")

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
commonName                      = $ORG_NAME

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

# Создание конфигурационного файла для промежуточного ЦА
cat >intermediate/immissuer.conf <<EOL
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
commonName                      = $ORG_NAME

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
pushd "$IMM_CA" || { msg "Error: Failed to change directory to $IMM_CA" "Ошибка: Не удалось перейти в каталог $IMM_CA"; }

# Генерация RSA ключа для промежуточного ЦА с шифрованием AES-256
openssl genrsa -aes256 -out private/intermediate.key.pem -passout "pass:$SERT_PASS" 4096 || { msg "Error: Failed to generate RSA key for intermediate CA" "Ошибка: Не удалось создать RSA‑ключ для промежуточного ЦА"; }

# Установка прав доступа для ключа промежуточного ЦА
chmod 400 private/intermediate.key.pem

# Создание CSR для промежуточного ЦА
openssl req -config immissuer.conf -new -sha256 -key private/intermediate.key.pem -out csr/intermediate.csr.pem -passin "pass:$SERT_PASS" || { msg "Error: Failed to create CSR for intermediate CA" "Ошибка: Не удалось создать запрос на сертификат для промежуточного ЦА"; }

# Вернуться в исходную директорию или выйти с ошибкой, если это не удалось
popd || { msg "Can't return to old directory" "Невозможно вернуться к старому каталогу"; }

# Перейти в директорию корневого ЦА или выйти с ошибкой, если это не удалось
pushd "$ROOT_CA" || { msg "Error: Failed to change directory to $ROOT_CA" "Ошибка: Не удалось перейти в каталог $ROOT_CA"; }

# Подпись сертификата промежуточного ЦА корневым ЦА
openssl ca -batch -config sertissuer.conf -extensions v3_inter -days 3550 -notext -md sha256 -in $IMM_CA/csr/intermediate.csr.pem -out $IMM_CA/certs/intermediate.cert.pem -passin "pass:$SERT_PASS" || { msg "Error: Failed to sign intermediate CA certificate" "Ошибка: Не удалось подписать сертификат промежуточного ЦА корневым ЦА"; }

# Установка прав доступа для сертификата промежуточного ЦА
chmod 444 $IMM_CA/certs/intermediate.cert.pem

openssl ca -config "sertissuer.conf" -gencrl -out crl/ca.crl.pem -passin "pass:$SERT_PASS"

# Вернуться в исходную директорию или выйти с ошибкой, если это не удалось
popd || { msg "Can't return to old directory" "Невозможно вернуться к старому каталогу"; }

# Перейти в директорию промежуточного ЦА или выйти с ошибкой, если это не удалось
pushd "$IMM_CA" || { msg "Error: Failed to change directory to $IMM_CA" "Ошибка: Не удалось перейти в каталог $IMM_CA"; }

openssl ca -config "immissuer.conf" -gencrl -out crl/intermediate.crl.pem -passin "pass:$SERT_PASS"

cat $ROOT_CA/crl/ca.crl.pem $IMM_CA/crl/intermediate.crl.pem >$IMM_CA/crl/ca-full.crl.pem

# Вернуться в исходную директорию или выйти с ошибкой, если это не удалось
popd || { msg "Can't return to old directory" "Невозможно вернуться к старому каталогу"; }

# Создание цепочки сертификатов
cat "$IMM_CA/certs/intermediate.cert.pem" "$ROOT_CA/certs/ca.cert.pem" >"$IMM_CA/certs/ca-chain.cert.pem" || { msg "Error: Failed to create CA chain certificate" "Ошибка: Не удалось создать цепочку сертификатов ЦА"; }

# Проверка сертификата промежуточного ЦА с использованием корневого центра сертификации
openssl verify -CAfile $ROOT_CA/certs/ca.cert.pem $IMM_CA/certs/intermediate.cert.pem || { msg "Error: Failed to verify intermediate CA certificate" "Ошибка: Не удалось проверить сертификат промежуточного ЦА"; }

exit 0
