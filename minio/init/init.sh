#!/bin/sh
set -eu

mc alias set storage http://minio:9000 "${MINIO_ROOT_USER}" "${MINIO_ROOT_PASSWORD}"

mc mb -p "storage/${MINIO_BUCKET_PUBLIC}" || true
mc mb -p "storage/${MINIO_BUCKET_PRIVATE}" || true

mc anonymous set download "storage/${MINIO_BUCKET_PUBLIC}" || true

echo "MinIO init done."
