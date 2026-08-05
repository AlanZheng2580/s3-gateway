#!/bin/sh
set -eu

# Provision the MinIO backend that represents the future WEKA S3 service.
# This script is idempotent and safe to run repeatedly.

: "${MINIO_ENDPOINT:=http://minio:9000}"
: "${MINIO_ROOT_USER:=weka-admin-superkey}"
: "${MINIO_ROOT_PASSWORD:=weka-admin-supersecret}"
: "${MINIO_VGW_ADMIN_USER:=versitygw-minio-admin}"
: "${MINIO_VGW_ADMIN_PASSWORD:=versitygw-minio-admin-secret}"

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

echo "Ensuring dedicated MinIO admin user for VersityGW backend access..."
if mc admin user info mock-weka "${MINIO_VGW_ADMIN_USER}" >/dev/null 2>&1; then
  echo "MinIO user ${MINIO_VGW_ADMIN_USER} already exists."
else
  mc admin user add mock-weka "${MINIO_VGW_ADMIN_USER}" "${MINIO_VGW_ADMIN_PASSWORD}"
fi

# consoleAdmin is intentionally high-privilege. This avoids giving VersityGW the
# MinIO root credential while preserving enough backend authority for bucket,
# object, ACL/policy metadata, and future admin-style development testing.
mc admin policy attach mock-weka consoleAdmin --user "${MINIO_VGW_ADMIN_USER}"

echo "Applying 10MiB hard quotas to user buckets..."
mc quota set mock-weka/bucket-user-a --size 10MiB
mc quota set mock-weka/bucket-user-b --size 10MiB

echo "Quota summary:"
mc quota info mock-weka/bucket-user-a || true
mc quota info mock-weka/bucket-user-b || true

echo "MinIO provisioning complete."
