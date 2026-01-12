SHELL := /bin/bash

COMPOSE := docker compose
ENV_FILE := .env

ifneq (,$(wildcard .env))
include .env
export
endif

POSTGRES_PORT ?= 55432

.PHONY: help check-env env up down restart ps logs postgres-logs minio-logs nginx-logs \
        init reinit pull clean ufw ufw-status tls-issue tls-renew nginx-reload

help:
	@echo ""
	@echo "Targets:"
	@echo "  make env                 -> создать .env из .env.example (если нет)"
	@echo "  make up                  -> поднять Postgres + MinIO + Nginx (+ init бакетов)"
	@echo "  make down                -> остановить"
	@echo "  make restart             -> перезапуск"
	@echo "  make ps                  -> статус контейнеров"
	@echo "  make logs                -> логи всех сервисов"
	@echo "  make postgres-logs        -> логи postgres"
	@echo "  make minio-logs           -> логи minio"
	@echo "  make nginx-logs           -> логи nginx"
	@echo "  make init                -> выполнить minio-init (создать бакеты/права)"
	@echo "  make reinit              -> пересоздать minio-init и прогнать заново"
	@echo "  make tls-issue           -> выпустить сертификат Let's Encrypt для $$S3_DOMAIN"
	@echo "  make tls-renew           -> обновить сертификаты"
	@echo "  make ufw APP_IP=x.x.x.x  -> открыть доступ: 80/443 всем, Postgres только для APP_IP"
	@echo "  make ufw-status          -> показать ufw status"
	@echo "  make pull                -> обновить образы"
	@echo "  make clean FORCE=1       -> ОПАСНО: удалить volumes (данные postgres/minio/certs)"
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
		echo "Создал .env из .env.example. Открой и заполни пароли/домены."; \
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

nginx-logs: check-env
	$(COMPOSE) logs -f --tail=200 nginx

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
	rm -rf ./data ./certbot

ufw:
	@if [ -z "$(APP_IP)" ]; then \
		echo "Нужно указать APP_IP. Пример: make ufw APP_IP=1.2.3.4"; \
		exit 1; \
	fi
	sudo ufw allow OpenSSH
	sudo ufw allow 80/tcp
	sudo ufw allow 443/tcp
	sudo ufw allow from "$(APP_IP)" to any port "$(POSTGRES_PORT)" proto tcp
	@echo "MinIO порты (9000/9001) наружу НЕ открываем — доступ только через nginx."
	sudo ufw --force enable
	sudo ufw status verbose

ufw-status:
	sudo ufw status verbose

tls-issue: check-env
	@echo "Выпускаю сертификаты для $${S3_DOMAIN} и $${MINIO_DOMAIN}..."
	$(COMPOSE) up -d nginx
	$(COMPOSE) run --rm --entrypoint certbot certbot certonly \
	  --webroot -w /var/www/certbot \
	  -d "$${S3_DOMAIN}" \
	  -d "$${MINIO_DOMAIN}" \
	  --email "$${LETSENCRYPT_EMAIL}" \
	  --agree-tos --no-eff-email
	$(MAKE) nginx-reload

tls-renew: check-env
	$(COMPOSE) run --rm --entrypoint certbot certbot renew
	$(MAKE) nginx-reload

nginx-reload:
	@docker exec storage-nginx nginx -s reload || true
