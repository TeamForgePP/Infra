#!/bin/sh
set -eu

mc alias set storage http://minio:9000 "${MINIO_ROOT_USER}" "${MINIO_ROOT_PASSWORD}"

mc mb -p "storage/${MINIO_BUCKET_PUBLIC}" || true
mc mb -p "storage/${MINIO_BUCKET_PRIVATE}" || true

# Если тебе нужны “публичные ссылки без авторизации” — оставь эту строку.
# Если НЕ нужно — закомментируй, и всё будет только через presigned.
mc anonymous set download "storage/${MINIO_BUCKET_PUBLIC}" || true

echo "MinIO init done."
