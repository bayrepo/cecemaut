Сводка утилит для создания сертификатов и управление ими в инфраструктуре центра сертификации

В данной статье представлены краткое описание и примеры использования нескольких полезных утилит, которые помогают автоматизировать процесс создания сертификатов и управления ими в инфраструктуре центра сертификации.

## Утилита `prepare.sh`
### Описание:
Скрипт автоматизирует процесс создания инфраструктуры центра сертификации (ЦС), включая создание директорий, генерацию ключей и сертификатов, а также настройку конфигурационных файлов для корневого и промежуточного ЦА.

### Примеры использования:
1. Запуск скрипта с правами суперпользователя:
    ```sh
    sudo bash prepare.sh
    ```

## Утилита `make_server_cert.sh`
### Описание:
Генерирует серверные сертификаты для указанных доменов или IP-адресов. Скрипт создает приватный ключ, запрос на подпись сертификата (CSR) и сам сертификат.

### Примеры использования:
1. Генерация серверного сертификата для домена `example1.com` и IP-адреса `192.168.3.145`:
    ```sh
    bash make_server_cert.sh -t 395 example1.com 192.168.3.145
    ```

## Утилита `make_client_cert.sh`
### Описание:
Скрипт для создания клиентских сертификатов для указанного сервера и клиента. Генерирует приватный ключ, запрос на сертификат (CSR), подписывает его и выводит информацию о сгенерированном сертификате.

### Примеры использования:
1. Генерация клиентского сертификата для домена `example1.com` и имени пользователя `user1@test.com`, действующего 365 дней:
    ```sh
    bash make_client_cert.sh -s example1.com -c user1@test.com -d 365
    ```

## Утилита `make_server_revoke.sh`
### Описание:
Позволяет отозвать серверный сертификат для указанного домена или IP-адреса.

### Примеры использования:
1. Отозвать серверный сертификат для домена `brepo.ru`:
    ```sh
    bash make_server_revoke.sh -n 1 -s brepo.ru
    ```

## Утилита `make_client_revoke.sh`
### Описание:
Позволяет отозвать клиентский сертификат для указанного сервера и клиента.

### Примеры использования:
1. Отозвать клиентский сертификат для домена `example1.com` и имени пользователя `user2@test.com`:
    ```sh
    bash make_client_revoke.sh -n 1 -s example1.com -c user2@test.com
    ```

## Утилита `make_app_keys.sh`
### Описание:
Скрипт генерирует беспарольный приватный и публичный ключ с помощью `openssl` и сохраняет их в указанной директории. Это удобно для создания ключей, которые будут использоваться приложениями без необходимости вводить пароль при каждом использовании.

### Примеры использования:
1. Генерация ключей в директории `/etc/ssl/app_keys`:
    ```sh
    bash make_app_keys.sh /etc/ssl/app_keys
    ```
    После выполнения ключи будут доступны как:
    - `/etc/ssl/app_keys/caapp.private.key.pem`
    - `/etc/ssl/app_keys/caapp.public.key.pem`

## Еще примеры
1. Подготовка инфраструктуры ЦС и генерация серверного и клиентского сертификатов:
    ```sh
    bash prepare.sh
    bash make_server_cert.sh example1.com 192.168.5.145
    bash make_client_cert.sh -s example1.com -c user1@test.com -d 365
    ```

2. Отозвать серверный и клиентский сертификаты (все версии):
    ```sh
    bash make_server_revoke.sh brepo.ru
    bash make_client_revoke.sh -s example1.com -c user2@test.com
    ```

Эти утилиты и примеры помогут вам автоматизировать процесс создания сертификатов и управления ими в инфраструктуре центра сертификации.

## Примеры настройки nginx

Как обеспечить доступ к сайту с помощью сертификатов:


Примкр настройки домена, например с репозиторием пакетов `/etc/nginx/conf.d/example1.com.conf`:

```
server {
    listen 8081 ssl;
    server_name example1.com www.example1.com;

    root /var/www/example1.com/html;
    index index.html;

    location / {
        try_files $uri $uri/ =404;
    }

    access_log /var/log/nginx/example1.com.access.log;
    error_log /var/log/nginx/example1.com.error.log debug;

    ssl_certificate         /database/ca/intermediate/certs/example1.com.cert.pem;
    ssl_certificate_key     /database/ca/intermediate/private/example1.com.key.pem;
    ssl_client_certificate  /database/ca/intermediate/certs/ca-chain.cert.pem;
    ssl_crl /database/ca/intermediate/crl/ca-full.crl.pem;
    ssl_verify_client       on;

    keepalive_timeout 70;
    fastcgi_param SSL_VERIFIED $ssl_client_verify;
    fastcgi_param SSL_CLIENT_SERIAL $ssl_client_serial;
    fastcgi_param SSL_CLIENT_CERT $ssl_client_cert;
    fastcgi_param SSL_DN $ssl_client_s_dn;
}
```


Вызов на строне клиента:

```
curl -k --cert /database/ca/client_certs/example1.com/user2@test.com.cert.pem --key /database/ca/client_certs/example1.com/private/user2@test.com_private.key.pem https://example1.com:8081
```


Или настройка DNF репозитория для доступа к закрытому репозиторию:

```[test]
name = test
enabled = 1
sslverify = 0
gpgcheck = 1
baseurl = https://example1.com:8081
sslclientkey=/database/ca/client_certs/example1.com/private/user2@test.com_private.key.pem
sslclientcert=/database/ca/client_certs/example1.com/user2@test.com.cert.pem
sslcacert=/database/ca/intermediate/certs/ca-chain.cert.pem
```
