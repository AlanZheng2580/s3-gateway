#!/bin/sh
set -eu

COMPOSE="${COMPOSE:-docker compose}"
VGW_ENDPOINT="http://versitygw:7070"
VGW_ADMIN_ENDPOINT="http://versitygw:7071"

VGW_ADMIN_ACCESS_KEY="${VGW_ADMIN_ACCESS_KEY:-versitygw-admin-key}"
VGW_ADMIN_SECRET_KEY="${VGW_ADMIN_SECRET_KEY:-versitygw-admin-secret}"
VGW_ROOT_ACCESS_KEY="${VGW_ROOT_ACCESS_KEY:-weka-admin-superkey}"
VGW_ROOT_SECRET_KEY="${VGW_ROOT_SECRET_KEY:-weka-admin-supersecret}"
USER_A_ACCESS_KEY="user-a-key"
USER_A_SECRET_KEY="user-a-secret"
USER_B_ACCESS_KEY="user-b-key"
USER_B_SECRET_KEY="user-b-secret"

AWS_WORKDIR=".tmp/aws"
MULTIPART_OBJECT_SIZE_BYTES="6291456"

log_section() {
  echo
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "▶ ${1}"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

log_step() {
  echo "▶ ${1}"
}

log_pass() {
  echo "✓ ${1}"
}

log_deny() {
  echo "⛔ ${1}"
}

log_error() {
  echo "✗ ${1}" >&2
}

run_compose() {
  # shellcheck disable=SC2086
  ${COMPOSE} "$@"
}

aws_as() {
  access_key="$1"
  secret_key="$2"
  shift 2

  run_compose run --rm -T \
    -e "AWS_ACCESS_KEY_ID=${access_key}" \
    -e "AWS_SECRET_ACCESS_KEY=${secret_key}" \
    awscli --endpoint-url "${VGW_ENDPOINT}" "$@"
}

vgw_admin_as() {
  access_key="$1"
  secret_key="$2"
  shift 2

  run_compose run --rm -T \
    --entrypoint versitygw \
    versitygw-user-provisioner admin \
    -a "${access_key}" \
    -s "${secret_key}" \
    -er "${VGW_ADMIN_ENDPOINT}" \
    "$@"
}

expect_success() {
  name="$1"
  shift
  log_pass "PASS expected: ${name}"
  "$@"
}

expect_denied() {
  name="$1"
  shift
  log_deny "DENY expected: ${name}"
  if "$@" >/tmp/mock-weka-deny.out 2>/tmp/mock-weka-deny.err; then
    log_error "ERROR: command unexpectedly succeeded: ${name}"
    cat /tmp/mock-weka-deny.out >&2 || true
    return 1
  fi
  cat /tmp/mock-weka-deny.err
}

delete_all_test_object_versions() {
  bucket="$1"
  key="$2"

  for version_type in Versions DeleteMarkers; do
    version_ids="$(aws_as "${VGW_ROOT_ACCESS_KEY}" "${VGW_ROOT_SECRET_KEY}" \
      s3api list-object-versions \
      --bucket "${bucket}" \
      --prefix "${key}" \
      --query "${version_type}[?Key=='${key}'].VersionId" \
      --output text)"

    printf '%s\n' "${version_ids}" | tr '\t' '\n' | while IFS= read -r version_id; do
      if [ -n "${version_id}" ] && [ "${version_id}" != "None" ]; then
        aws_as "${VGW_ROOT_ACCESS_KEY}" "${VGW_ROOT_SECRET_KEY}" \
          s3api delete-object \
          --bucket "${bucket}" \
          --key "${key}" \
          --version-id "${version_id}" >/dev/null
      fi
    done
  done
}

multipart_upload_user_a() {
  upload_id=""

  # Keep the test idempotent under the default 10MiB quota. Suspended
  # versioning can retain old versions and delete markers, so remove every
  # version of this exact test key before creating new multipart parts.
  delete_all_test_object_versions bucket-user-a multipart/user-a-6MiB.bin

  upload_id="$(aws_as "${USER_A_ACCESS_KEY}" "${USER_A_SECRET_KEY}" \
    s3api create-multipart-upload \
    --bucket bucket-user-a \
    --key multipart/user-a-6MiB.bin \
    --query UploadId \
    --output text)"

  if [ -z "${upload_id}" ] || [ "${upload_id}" = "None" ]; then
    log_error "Failed to create multipart upload."
    return 1
  fi

  etag_1=""
  etag_2=""

  if ! etag_1="$(aws_as "${USER_A_ACCESS_KEY}" "${USER_A_SECRET_KEY}" \
    s3api upload-part \
    --bucket bucket-user-a \
    --key multipart/user-a-6MiB.bin \
    --part-number 1 \
    --body multipart-part-1-5MiB.bin \
    --upload-id "${upload_id}" \
    --query ETag \
    --output text)"; then
    aws_as "${USER_A_ACCESS_KEY}" "${USER_A_SECRET_KEY}" \
      s3api abort-multipart-upload \
      --bucket bucket-user-a \
      --key multipart/user-a-6MiB.bin \
      --upload-id "${upload_id}" || true
    return 1
  fi

  if ! etag_2="$(aws_as "${USER_A_ACCESS_KEY}" "${USER_A_SECRET_KEY}" \
    s3api upload-part \
    --bucket bucket-user-a \
    --key multipart/user-a-6MiB.bin \
    --part-number 2 \
    --body multipart-part-2-1MiB.bin \
    --upload-id "${upload_id}" \
    --query ETag \
    --output text)"; then
    aws_as "${USER_A_ACCESS_KEY}" "${USER_A_SECRET_KEY}" \
      s3api abort-multipart-upload \
      --bucket bucket-user-a \
      --key multipart/user-a-6MiB.bin \
      --upload-id "${upload_id}" || true
    return 1
  fi

  printf '{"Parts":[{"ETag":%s,"PartNumber":1},{"ETag":%s,"PartNumber":2}]}\n' \
    "${etag_1}" \
    "${etag_2}" > "${AWS_WORKDIR}/multipart-complete-user-a.json"

  if ! aws_as "${USER_A_ACCESS_KEY}" "${USER_A_SECRET_KEY}" \
    s3api complete-multipart-upload \
    --bucket bucket-user-a \
    --key multipart/user-a-6MiB.bin \
    --upload-id "${upload_id}" \
    --multipart-upload file://multipart-complete-user-a.json; then
    aws_as "${USER_A_ACCESS_KEY}" "${USER_A_SECRET_KEY}" \
      s3api abort-multipart-upload \
      --bucket bucket-user-a \
      --key multipart/user-a-6MiB.bin \
      --upload-id "${upload_id}" || true
    return 1
  fi

  actual_size="$(aws_as "${USER_A_ACCESS_KEY}" "${USER_A_SECRET_KEY}" \
    s3api head-object \
    --bucket bucket-user-a \
    --key multipart/user-a-6MiB.bin \
    --query ContentLength \
    --output text)"

  if [ "${actual_size}" != "${MULTIPART_OBJECT_SIZE_BYTES}" ]; then
    log_error "Multipart object size mismatch: expected ${MULTIPART_OBJECT_SIZE_BYTES}, got ${actual_size}."
    return 1
  fi
}

log_section "Starting and provisioning local S3 lab..."
run_compose up -d minio
run_compose run --rm -T minio-provisioner
run_compose up -d versitygw
run_compose run --rm -T versitygw-user-provisioner
run_compose run --rm -T versitygw-policy-provisioner

log_section "Verifying provisioned VersityGW admin..."
expect_success "Provisioned VersityGW admin can list gateway users" \
  vgw_admin_as "${VGW_ADMIN_ACCESS_KEY}" "${VGW_ADMIN_SECRET_KEY}" \
    list-users

mkdir -p "${AWS_WORKDIR}"
printf 'hello from user A\n' > "${AWS_WORKDIR}/user-a-small.txt"
printf 'hello from user B\n' > "${AWS_WORKDIR}/user-b-small.txt"

if [ ! -f "${AWS_WORKDIR}/oversize-11MiB.bin" ]; then
  log_step "Creating local 11MiB quota test object..."
  dd if=/dev/zero of="${AWS_WORKDIR}/oversize-11MiB.bin" bs=1M count=11
fi

if [ ! -f "${AWS_WORKDIR}/multipart-part-1-5MiB.bin" ]; then
  log_step "Creating local 5MiB multipart test part..."
  dd if=/dev/zero of="${AWS_WORKDIR}/multipart-part-1-5MiB.bin" bs=1M count=5
fi

if [ ! -f "${AWS_WORKDIR}/multipart-part-2-1MiB.bin" ]; then
  log_step "Creating local 1MiB multipart test part..."
  dd if=/dev/zero of="${AWS_WORKDIR}/multipart-part-2-1MiB.bin" bs=1M count=1
fi

log_section "Verifying User_A isolation..."
expect_success "User_A can upload to bucket-user-a" \
  aws_as "${USER_A_ACCESS_KEY}" "${USER_A_SECRET_KEY}" \
    s3api put-object --bucket bucket-user-a --key smoke/user-a.txt --body user-a-small.txt

expect_success "User_A can list bucket-user-a" \
  aws_as "${USER_A_ACCESS_KEY}" "${USER_A_SECRET_KEY}" \
    s3api list-objects-v2 --bucket bucket-user-a

expect_success "User_A can upload a multi-object delete test object to bucket-user-a" \
  aws_as "${USER_A_ACCESS_KEY}" "${USER_A_SECRET_KEY}" \
    s3api put-object --bucket bucket-user-a --key smoke/user-a-multi-delete.txt --body user-a-small.txt

expect_success "User_A can use multi-object delete in bucket-user-a" \
  aws_as "${USER_A_ACCESS_KEY}" "${USER_A_SECRET_KEY}" \
    s3api delete-objects --bucket bucket-user-a \
      --delete '{"Objects":[{"Key":"smoke/user-a-multi-delete.txt"}],"Quiet":true}'

expect_success "User_A can complete a multipart upload to bucket-user-a" \
  multipart_upload_user_a

expect_denied "User_A cannot list bucket-user-b" \
  aws_as "${USER_A_ACCESS_KEY}" "${USER_A_SECRET_KEY}" \
    s3api list-objects-v2 --bucket bucket-user-b

expect_denied "User_A cannot upload to bucket-user-b" \
  aws_as "${USER_A_ACCESS_KEY}" "${USER_A_SECRET_KEY}" \
    s3api put-object --bucket bucket-user-b --key smoke/user-a-cross.txt --body user-a-small.txt

expect_denied "User_A cannot initiate multipart upload to bucket-user-b" \
  aws_as "${USER_A_ACCESS_KEY}" "${USER_A_SECRET_KEY}" \
    s3api create-multipart-upload --bucket bucket-user-b --key multipart/user-a-cross.bin

log_section "Verifying User_B isolation..."
expect_success "User_B can upload to bucket-user-b" \
  aws_as "${USER_B_ACCESS_KEY}" "${USER_B_SECRET_KEY}" \
    s3api put-object --bucket bucket-user-b --key smoke/user-b.txt --body user-b-small.txt

expect_success "User_B can list bucket-user-b" \
  aws_as "${USER_B_ACCESS_KEY}" "${USER_B_SECRET_KEY}" \
    s3api list-objects-v2 --bucket bucket-user-b

expect_success "User_B can upload a multi-object delete test object to bucket-user-b" \
  aws_as "${USER_B_ACCESS_KEY}" "${USER_B_SECRET_KEY}" \
    s3api put-object --bucket bucket-user-b --key smoke/user-b-multi-delete.txt --body user-b-small.txt

expect_success "User_B can use multi-object delete in bucket-user-b" \
  aws_as "${USER_B_ACCESS_KEY}" "${USER_B_SECRET_KEY}" \
    s3api delete-objects --bucket bucket-user-b \
      --delete '{"Objects":[{"Key":"smoke/user-b-multi-delete.txt"}],"Quiet":true}'

expect_denied "User_B cannot list bucket-user-a" \
  aws_as "${USER_B_ACCESS_KEY}" "${USER_B_SECRET_KEY}" \
    s3api list-objects-v2 --bucket bucket-user-a

expect_denied "User_B cannot upload to bucket-user-a" \
  aws_as "${USER_B_ACCESS_KEY}" "${USER_B_SECRET_KEY}" \
    s3api put-object --bucket bucket-user-a --key smoke/user-b-cross.txt --body user-b-small.txt

expect_denied "User_A cannot use multi-object delete in bucket-user-b" \
  aws_as "${USER_A_ACCESS_KEY}" "${USER_A_SECRET_KEY}" \
    s3api delete-objects --bucket bucket-user-b \
      --delete '{"Objects":[{"Key":"smoke/user-b.txt"}],"Quiet":true}'

expect_denied "User_B cannot use multi-object delete in bucket-user-a" \
  aws_as "${USER_B_ACCESS_KEY}" "${USER_B_SECRET_KEY}" \
    s3api delete-objects --bucket bucket-user-a \
      --delete '{"Objects":[{"Key":"smoke/user-a.txt"}],"Quiet":true}'

expect_success "User_A cross-bucket delete did not remove User_B's object" \
  aws_as "${USER_B_ACCESS_KEY}" "${USER_B_SECRET_KEY}" \
    s3api head-object --bucket bucket-user-b --key smoke/user-b.txt

expect_success "User_B cross-bucket delete did not remove User_A's object" \
  aws_as "${USER_A_ACCESS_KEY}" "${USER_A_SECRET_KEY}" \
    s3api head-object --bucket bucket-user-a --key smoke/user-a.txt

log_section "Verifying MinIO backend quota through VersityGW..."
expect_denied "User_A cannot upload an 11MiB object to 10MiB bucket-user-a" \
  aws_as "${USER_A_ACCESS_KEY}" "${USER_A_SECRET_KEY}" \
    s3api put-object --bucket bucket-user-a --key quota/oversize.bin --body oversize-11MiB.bin

echo
log_pass "All verification checks completed."
