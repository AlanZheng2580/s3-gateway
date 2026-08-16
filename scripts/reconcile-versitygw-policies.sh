#!/bin/sh
set -eu

: "${VGW_S3_ENDPOINT:=http://versitygw:7070}"
: "${POLICY_DIR:=/config/policies}"

for policy_file in "${POLICY_DIR}"/*-policy.json; do
  if [ ! -f "${policy_file}" ]; then
    echo "No policy files found in ${POLICY_DIR}." >&2
    exit 1
  fi

  bucket="$(basename "${policy_file}" -policy.json)"
  echo "Applying policy for ${bucket}."
  aws --endpoint-url "${VGW_S3_ENDPOINT}" \
    s3api put-bucket-policy \
    --bucket "${bucket}" \
    --policy "file://${policy_file}"
done

