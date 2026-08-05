#!/bin/sh
set -eu

# Apply VersityGW JSON bucket policies through the gateway S3 endpoint.
# VersityGW does not support AWS IAM user policies; bucket policies are the
# JSON policy mechanism enforced for non-root users.

: "${VGW_S3_ENDPOINT:=http://versitygw:7070}"
: "${AWS_DEFAULT_REGION:=us-east-1}"

aws_vgw() {
  aws --endpoint-url "${VGW_S3_ENDPOINT}" "$@"
}

echo "Waiting for VersityGW S3 API at ${VGW_S3_ENDPOINT}..."
until aws_vgw s3api head-bucket --bucket bucket-user-a >/dev/null 2>&1; do
  sleep 2
done
until aws_vgw s3api head-bucket --bucket bucket-user-b >/dev/null 2>&1; do
  sleep 2
done

echo "Applying strict bucket policies..."
aws_vgw s3api put-bucket-policy \
  --bucket bucket-user-a \
  --policy file:///policies/bucket-user-a-policy.json

aws_vgw s3api put-bucket-policy \
  --bucket bucket-user-b \
  --policy file:///policies/bucket-user-b-policy.json

echo "Policy provisioning complete."

