SHELL := /bin/bash

COMPOSE := docker compose
ENV_FILE := .env

ifneq (,$(wildcard .env))
include .env
export
endif

POSTGRES_PORT ?= 55432

.PHONY: help check-env env \
        dev dev-down dev-restart dev-ps dev-logs dev-nginx-logs \
        up down restart ps logs postgres-logs minio-logs nginx-logs \
        init reinit pull clean ufw ufw-status \
        tls-issue tls-renew nginx-reload

help:
	@echo ""
	@echo "Targets:"
	@echo "  make env                    -> создать .env из .env.example (если нет)"
	@echo ""
	@echo "DEV (без SSL, только 80):"
	@echo "  make dev                    -> поднять Postgres + MinIO + Nginx(80)"
	@echo "  make dev-down               -> остановить dev"
	@echo "  make dev-restart            -> перезапуск dev"
	@echo "  make dev-logs               -> логи dev"
	@echo ""
	@echo "PROD (SSL, 80->443):"
	@echo "  make tls-issue              -> выпустить сертификаты для $$S3_DOMAIN и $$MINIO_DOMAIN (нужен make dev)"
	@echo "  make up                     -> поднять прод (Nginx 80/443 + SSL)"
	@echo "  make down                   -> остановить прод"
	@echo "  make restart                -> перезапуск прод"
	@echo ""
	@echo "Utils:"
	@echo "  make ufw APP_IP=x.x.x.x     -> открыть 80/443 всем, Postgres только для APP_IP"
	@echo "  make clean FORCE=1          -> ОПАСНО: удалить volumes (данные postgres/minio/certs)"
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

# ---------- DEV ----------
dev: check-env
	$(COMPOSE) up -d postgres minio nginx-dev
	$(MAKE) init

dev-down: check-env
	$(COMPOSE) down

dev-restart: check-env
	$(COMPOSE) down
	$(COMPOSE) up -d postgres minio nginx-dev
	$(MAKE) init

dev-ps: check-env
	$(COMPOSE) ps

dev-logs: check-env
	$(COMPOSE) logs -f --tail=200

dev-nginx-logs: check-env
	$(COMPOSE) logs -f --tail=200 nginx-dev

# ---------- PROD ----------
up: check-env
	@if [ ! -f "./certbot/live/$${S3_DOMAIN}/fullchain.pem" ]; then \
		echo "Нет сертификата ./certbot/live/$${S3_DOMAIN}/fullchain.pem"; \
		echo "Сделай: make dev && make tls-issue && make up"; \
		exit 1; \
	fi
	$(COMPOSE) up -d postgres minio nginx
	$(MAKE) init

down: check-env
	$(COMPOSE) down

restart: check-env
	$(COMPOSE) down
	$(MAKE) up

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

# ---------- INIT ----------
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

# ВАЖНО: certbot может проверить домены ТОЛЬКО по 80 (http).
# Поэтому: сначала make dev (nginx-dev на 80), потом make tls-issue.
tls-issue: check-env
	@echo "Сначала убедись, что работает make dev (nginx-dev слушает 80)."
	@echo "Выпускаю сертификаты для $${S3_DOMAIN} и $${MINIO_DOMAIN}..."
	$(COMPOSE) up -d nginx-dev
	$(COMPOSE) run --rm --entrypoint certbot certbot certonly \
	  --webroot -w /var/www/certbot \
	  -d "$${S3_DOMAIN}" \
	  -d "$${MINIO_DOMAIN}" \
	  --email "$${LETSENCRYPT_EMAIL}" \
	  --agree-tos --no-eff-email --non-interactive
	@echo "Готово. Теперь: make up"

tls-renew: check-env
	$(COMPOSE) run --rm --entrypoint certbot certbot renew
	$(MAKE) nginx-reload

nginx-reload:
	@docker exec storage-nginx nginx -s reload || true
