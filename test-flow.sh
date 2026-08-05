#!/bin/sh
set -eu

COMPOSE="${COMPOSE:-docker compose}"
VGW_ENDPOINT="http://versitygw:7070"

USER_A_ACCESS_KEY="user-a-key"
USER_A_SECRET_KEY="user-a-secret"
USER_B_ACCESS_KEY="user-b-key"
USER_B_SECRET_KEY="user-b-secret"

AWS_WORKDIR=".tmp/aws"

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

log_section "Starting and provisioning local S3 lab..."
run_compose up -d minio
run_compose run --rm -T minio-provisioner
run_compose up -d versitygw
run_compose run --rm -T versitygw-user-provisioner
run_compose run --rm -T versitygw-policy-provisioner

mkdir -p "${AWS_WORKDIR}"
printf 'hello from user A\n' > "${AWS_WORKDIR}/user-a-small.txt"
printf 'hello from user B\n' > "${AWS_WORKDIR}/user-b-small.txt"

if [ ! -f "${AWS_WORKDIR}/oversize-11MiB.bin" ]; then
  log_step "Creating local 11MiB quota test object..."
  dd if=/dev/zero of="${AWS_WORKDIR}/oversize-11MiB.bin" bs=1M count=11
fi

log_section "Verifying User_A isolation..."
expect_success "User_A can upload to bucket-user-a" \
  aws_as "${USER_A_ACCESS_KEY}" "${USER_A_SECRET_KEY}" \
    s3api put-object --bucket bucket-user-a --key smoke/user-a.txt --body user-a-small.txt

expect_success "User_A can list bucket-user-a" \
  aws_as "${USER_A_ACCESS_KEY}" "${USER_A_SECRET_KEY}" \
    s3api list-objects-v2 --bucket bucket-user-a

expect_denied "User_A cannot list bucket-user-b" \
  aws_as "${USER_A_ACCESS_KEY}" "${USER_A_SECRET_KEY}" \
    s3api list-objects-v2 --bucket bucket-user-b

expect_denied "User_A cannot upload to bucket-user-b" \
  aws_as "${USER_A_ACCESS_KEY}" "${USER_A_SECRET_KEY}" \
    s3api put-object --bucket bucket-user-b --key smoke/user-a-cross.txt --body user-a-small.txt

log_section "Verifying User_B isolation..."
expect_success "User_B can upload to bucket-user-b" \
  aws_as "${USER_B_ACCESS_KEY}" "${USER_B_SECRET_KEY}" \
    s3api put-object --bucket bucket-user-b --key smoke/user-b.txt --body user-b-small.txt

expect_success "User_B can list bucket-user-b" \
  aws_as "${USER_B_ACCESS_KEY}" "${USER_B_SECRET_KEY}" \
    s3api list-objects-v2 --bucket bucket-user-b

expect_denied "User_B cannot list bucket-user-a" \
  aws_as "${USER_B_ACCESS_KEY}" "${USER_B_SECRET_KEY}" \
    s3api list-objects-v2 --bucket bucket-user-a

expect_denied "User_B cannot upload to bucket-user-a" \
  aws_as "${USER_B_ACCESS_KEY}" "${USER_B_SECRET_KEY}" \
    s3api put-object --bucket bucket-user-a --key smoke/user-b-cross.txt --body user-b-small.txt

log_section "Verifying MinIO backend quota through VersityGW..."
expect_denied "User_A cannot upload an 11MiB object to 10MiB bucket-user-a" \
  aws_as "${USER_A_ACCESS_KEY}" "${USER_A_SECRET_KEY}" \
    s3api put-object --bucket bucket-user-a --key quota/oversize.bin --body oversize-11MiB.bin

echo
log_pass "All verification checks completed."
