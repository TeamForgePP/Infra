# storage-infra

Инфраструктурный репозиторий для **Server A**.  
Поднимает **ТОЛЬКО**:
- PostgreSQL
- MinIO (S3-совместимое хранилище)

Никакого backend, frontend, Redis и миграций БД здесь нет.

Репозиторий нужен, чтобы:
- развернуть storage-сервисы на отдельном сервере
- дать к ним доступ приложению на другом сервере
- управлять всем через `.env` и `make`

---

## Архитектура

Server A (storage)
- PostgreSQL — доступ по TCP (порт из `.env`)
- MinIO
  - public — анонимный GET
  - private — доступ только через backend / presigned URL

Server B (app)
- backend / frontend
  - подключение к Postgres по IP:PORT
  - подключение к MinIO по S3 endpoint

---

## Структура репозитория

```
storage-infra/
├── docker-compose.yml
├── .env.example
├── Makefile
├── minio/
│   └── init/
│       └── init.sh
└── data/
    ├── postgres/
    └── minio/
```

---

## Быстрый старт

```bash
make env
# отредактировать .env
make up
```

Проверка:
```bash
make ps
```

---

## Доступ к сервисам

### PostgreSQL
```
host = STORAGE_SERVER_IP
port = POSTGRES_PUBLIC_PORT
db   = POSTGRES_DB
user = POSTGRES_USER
pass = POSTGRES_PASSWORD
```

### MinIO (S3)
```
endpoint = http://STORAGE_SERVER_IP:9000
access_key = MINIO_ROOT_USER
secret_key = MINIO_ROOT_PASSWORD
```

Бакеты:
- public  — публичные файлы (GET без авторизации)
- private — приватные файлы (presigned / backend)

---

## Принципы

- никаких SQL-инициализаций БД
- никаких миграций
- только инфраструктура
- схема БД и логика — в backend-репозитории

---

Назначение репозитория:
**один раз поднять storage и дальше просто подключаться к нему из кода.**
