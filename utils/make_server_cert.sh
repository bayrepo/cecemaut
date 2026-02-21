#!/bin/bash

# Этот скрипт предназначен для генерации серверных сертификатов для указанных доменов или IP-адресов.
# Он создает приватный ключ, запрос на подпись сертификата (CSR) и сам сертификат,
# используя конфигурационные файлы и инфраструктуру центра сертификации (CA).
# Скрипт также выводит информацию о сгенерированных ключах и сертификатах.

source ./config.sh

# Определяем, установлена ли русская локаль
if [[ "${LANG,,}" == ru* ]] || [[ "${LC_MESSAGES,,}" == ru* ]]; then
    LANG_RU=1
else
    LANG_RU=0
fi

# Handle -h option for help message
if [ "$1" == "-h" ]; then
    if [ "$LANG_RU" -eq 1 ]; then
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
        if [ "$LANG_RU" -eq 1 ]; then
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

mkdir -p server_certs

pushd server_certs || exit

# Проверка, предоставлен ли первый параметр и не пуст ли он
if [ -z "$1" ]; then
    if [ "$LANG_RU" -eq 1 ]; then
        echo "Нет входных данных"
    else
        echo "No input provided"
    fi
    exit 0
fi

# Разделение входной строки в массив с использованием запятых или пробелов как разделителей
IFS=', ' read -r -a items <<<"$1"

# Проверка, есть ли хотя бы один элемент в списке
if [ "${#items[@]}" -eq 0 ]; then
    if [ "$LANG_RU" -eq 1 ]; then
        echo "Входные данные пусты"
    else
        echo "No elements found in the input"
    fi
    popd || exit
    popd || exit
    exit 0
fi

SEQ="1"

# Извлечение первого элемента списка
fst_elem="${items[0]}"

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

    pushd "$IMM_CA" || {
        if [ "$LANG_RU" -eq 1 ]; then
            echo "Ошибка: не удалось перейти в каталог $IMM_CA"
        else
            echo "Error: Could not change directory to $IMM_CA"
        fi
        exit 1
    }

    openssl genrsa -out "private/$fst_elem.key.pem" -passout "pass:$SERT_PASS" 2048
    chmod 400 "private/$fst_elem.key.pem"
else
    SEQ=$(cat "$fst_elem/${fst_elem}_seq.seq")
    echo $((SEQ + 1)) >"$fst_elem/${fst_elem}_seq.seq"

    sed -i "s/^O = .*/O = ${ORG_NAME}:${SEQ}/" "${fst_elem}/csr_req.cnf"

    pushd "$IMM_CA" || {
        if [ "$LANG_RU" -eq 1 ]; then
            echo "Ошибка: не удалось перейти в каталог $IMM_CA"
        else
            echo "Error: Could not change directory to $IMM_CA"
        fi
        exit 1
    }

fi

# Генерация запроса на подпись сертификата (CSR)
openssl req -new -sha256 -key "private/$fst_elem.key.pem" -out "csr/$fst_elem.csr.pem" -config "../server_certs/$fst_elem/csr_req.cnf"

# Подписание CSR и создание сертификата
openssl ca -batch -config "immissuer.conf" -extensions server_cert -days "$CERT_DAYS" -notext -md sha256 -in "csr/$fst_elem.csr.pem" -out "certs/$fst_elem.cert.pem.$SEQ" -passin "pass:$SERT_PASS"
chmod 444 "certs/$fst_elem.cert.pem.$SEQ"

# Вывод информации о сертификате
openssl x509 -noout -text -in "certs/$fst_elem.cert.pem.$SEQ"

# Информирование пользователя о сгенерированных ключах и сертификатах
if [ "$LANG_RU" -eq 1 ]; then
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
