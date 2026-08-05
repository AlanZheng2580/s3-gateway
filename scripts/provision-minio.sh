#!/bin/sh
set -eu

# Provision the MinIO backend that represents the future WEKA S3 service.
# This script is idempotent and safe to run repeatedly.

: "${MINIO_ENDPOINT:=http://minio:9000}"
: "${MINIO_ROOT_USER:=weka-admin-superkey}"
: "${MINIO_ROOT_PASSWORD:=eka-admin-supersecret}"

echo "Waiting for MinIO at ${MINIO_ENDPOINT}..."
until mc alias set mock-weka "${MINIO_ENDPOINT}" "${MINIO_ROOT_USER}" "${MINIO_ROOT_PASSWORD}" >/dev/null 2>&1; do
  sleep 2
done

echo "Creating backend buckets..."
mc mb --ignore-existing mock-weka/bucket-user-a
mc mb --ignore-existing mock-weka/bucket-user-b

# VersityGW's S3 proxy backend stores gateway metadata such as bucket ACLs and
# bucket policies in a dedicated metadata bucket.
mc mb --ignore-existing mock-weka/vgw-meta

echo "Applying 10MiB hard quotas to user buckets..."
mc quota set mock-weka/bucket-user-a --size 10MiB
mc quota set mock-weka/bucket-user-b --size 10MiB

echo "Quota summary:"
mc quota info mock-weka/bucket-user-a || true
mc quota info mock-weka/bucket-user-b || true

echo "MinIO provisioning complete."

