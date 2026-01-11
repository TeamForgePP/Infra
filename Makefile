SHELL := /bin/bash

COMPOSE := docker compose
ENV_FILE := .env

# Порты по умолчанию (можно переопределять при вызове make)
POSTGRES_PORT ?= 55432
MINIO_API_PORT ?= 9000
MINIO_CONSOLE_PORT ?= 9001

.PHONY: help check-env env up down restart ps logs postgres-logs minio-logs init reinit pull clean ufw ufw-status

help:
	@echo ""
	@echo "Targets:"
	@echo "  make env               -> создать .env из .env.example (если нет)"
	@echo "  make up                -> поднять Postgres + MinIO (+ init бакетов)"
	@echo "  make down              -> остановить"
	@echo "  make restart           -> перезапуск"
	@echo "  make ps                -> статус контейнеров"
	@echo "  make logs              -> логи всех сервисов"
	@echo "  make postgres-logs      -> логи postgres"
	@echo "  make minio-logs         -> логи minio"
	@echo "  make init              -> выполнить minio-init (создать бакеты/права)"
	@echo "  make reinit             -> пересоздать minio-init и прогнать заново"
	@echo "  make pull              -> обновить образы"
	@echo "  make clean             -> ОПАСНО: удалить volumes (данные postgres/minio)"
	@echo "  make ufw APP_IP=x.x.x.x -> открыть доступ только для второго сервера"
	@echo "  make ufw-status         -> показать ufw status"
	@echo ""

check-env:
	@if [ ! -f "$(ENV_FILE)" ]; then \
		echo "Нет .env. Сделай: make env"; \
		exit 1; \
	fi

env:
	@if [ -f "$(ENV_FILE)" ]; then \
		echo ".env уже существует — не трогаю"; \
	else \
		cp .env.example .env; \
		echo "Создал .env из .env.example. Открой и заполни пароли."; \
	fi

up: check-env
	$(COMPOSE) up -d

down: check-env
	$(COMPOSE) down

restart: check-env
	$(COMPOSE) down
	$(COMPOSE) up -d

ps: check-env
	$(COMPOSE) ps

logs: check-env
	$(COMPOSE) logs -f --tail=200

postgres-logs: check-env
	$(COMPOSE) logs -f --tail=200 postgres

minio-logs: check-env
	$(COMPOSE) logs -f --tail=200 minio

init: check-env
	$(COMPOSE) up -d minio
	$(COMPOSE) up --no-deps --force-recreate minio-init

reinit: check-env
	$(COMPOSE) rm -f minio-init || true
	$(COMPOSE) up --no-deps --force-recreate minio-init

pull:
	$(COMPOSE) pull

clean: check-env
	@echo "Сейчас будет удаление volumes (данных) — это НЕОБРАТИМО."
	@echo "Если уверен: запусти -> make clean FORCE=1"
	@if [ "$(FORCE)" != "1" ]; then exit 1; fi
	$(COMPOSE) down -v
	rm -rf ./data

# Firewall: открыть доступ к Postgres и MinIO API только для второго сервера
# Использование: make ufw APP_IP=1.2.3.4 POSTGRES_PORT=55432
ufw:
	@if [ -z "$(APP_IP)" ]; then \
		echo "Нужно указать APP_IP. Пример: make ufw APP_IP=1.2.3.4"; \
		exit 1; \
	fi
	sudo ufw allow OpenSSH
	sudo ufw allow from "$(APP_IP)" to any port "$(POSTGRES_PORT)" proto tcp
	sudo ufw allow from "$(APP_IP)" to any port "$(MINIO_API_PORT)" proto tcp
	@echo "MinIO console (9001) я НЕ открываю намеренно."
	sudo ufw --force enable
	sudo ufw status verbose

ufw-status:
	sudo ufw status verbose
