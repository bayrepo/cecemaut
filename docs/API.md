# API Документация для CertCenter (POST-запросы, поддержка JSON)

Базовый адрес: `http://127.0.0.1:4567`

---   

## 1. Получение токена  

```
curl -X POST http://127.0.0.1:4567/api/v1/login \
  -H "Content-Type: application/json" \
  -d '{"login":"admin","password":"admin"}'
```

> **Ответ**  
> ```
> { "error": null, "content": { "token": "<JWT>" } }
> ```
> Сохраняйте значение `token` для последующих запросов.

---  

## 2. Список серверных сертификатов  

```
curl -X POST http://127.0.0.1:4567/api/v1/servers \
  -H "Content-Type: application/json" \
  -d '{"token":"<JWT>"}'
```

---  

## 3. Список клиентских сертификатов  

```
curl -X POST http://127.0.0.1:4567/api/v1/clients \
  -H "Content-Type: application/json" \
  -d '{"token":"<JWT>"}'
```

---  

## 4. Детальная информация о сертификате  

```
curl -X POST http://127.0.0.1:4567/api/v1/certinfo/123 \
  -H "Content-Type: application/json" \
  -d '{"token":"<JWT>"}'
```

---  

## 5. Детальная информация о корневом сертификате центра сертификации 

```
curl -X POST http://127.0.0.1:4567/api/v1/root \
  -H "Content-Type: application/json" \
  -d '{"token":"<JWT>"}'
```

---  

## 6. Отзыв сертификата  

```
curl -X POST http://127.0.0.1:4567/api/v1/revoke/123 \
  -H "Content-Type: application/json" \
  -d '{"token":"<JWT>"}'
```

---  

## 7. Добавление клиентского сертификата  

```
curl -X POST http://127.0.0.1:4567/api/v1/addclient \
  -H "Content-Type: application/json" \
  -d '{"token":"<JWT>","server_domain":"example.com","client":"client1"}'
```

---  

## 8. Добавление серверного сертификата  

```
curl -X POST http://127.0.0.1:4567/api/v1/addserver \
  -H "Content-Type: application/json" \
  -d '{"token":"<JWT>","domains":"example.com,example.org","validity_days":365}'
```

---  

## 9. Список пользователей (admin)  

```
curl -X POST http://127.0.0.1:4567/api/v1/ulist \
  -H "Content-Type: application/json" \
  -d '{"token":"<JWT>"}'
```

---  

## 10. Удаление пользователя  

```
curl -X POST http://127.0.0.1:4567/api/v1/deleteuser/42 \
  -H "Content-Type: application/json" \
  -d '{"token":"<JWT>"}'
```

---  

## 11. Создание пользователя  

```
curl -X POST http://127.0.0.1:4567/api/v1/adduser \
  -H "Content-Type: application/json" \
  -d '{"token":"<JWT>","login":"jane","password":"secret","email":"jane@example.com","role":1}'
```

---  

## 12. Редактирование пользователя  

```
curl -X POST http://127.0.0.1:4567/api/v1/edituser/42 \
  -H "Content-Type: application/json" \
  -d '{"token":"<JWT>","login":"jane","password":"newpass","role":2}'
```

---  

## 13. Установка и подготовка структуры центра сертификации

```
curl -X POST http://127.0.0.1:4567/api/v1/install \
  -H "Content-Type: application/json" \
  -d '{"cert-path":"/tmp","org-name":"neworg","common-name":"name","cert-password":"pass","country-name": "RU", "validity-days":"3650"}'
```

---  

## 14. Обработка ошибок  

Если сервер возвращает статус **400**, то это ошибка синтаксиса JSON:  

```
{ "error": "Invalid JSON", "content": null }
```

Если токен недействителен или истёк, будет:  

```
{ "error": "Токен устарел", "content": null }
```

При других ошибках сервер выдаёт `{ "error": "...", "content": "..." }` в формате JSON.
