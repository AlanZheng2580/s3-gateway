#!/bin/sh
set -eu

# Register mock users in VersityGW's internal IAM database.
# VersityGW uses access-key IDs as user IDs; there are no separate usernames.

: "${VGW_ADMIN_ENDPOINT:=http://versitygw:7071}"
: "${VGW_ROOT_ACCESS_KEY:=weka-admin-superkey}"
: "${VGW_ROOT_SECRET_KEY:=weka-admin-supersecret}"

log_step() {
  echo "▶ ${1}"
}

log_info() {
  echo "• ${1}"
}

log_done() {
  echo "✓ ${1}"
}

admin() {
  versitygw admin \
    -a "${VGW_ROOT_ACCESS_KEY}" \
    -s "${VGW_ROOT_SECRET_KEY}" \
    -er "${VGW_ADMIN_ENDPOINT}" \
    "$@"
}

log_step "Waiting for VersityGW admin API at ${VGW_ADMIN_ENDPOINT}..."
until admin list-users >/tmp/versitygw-users.txt 2>/tmp/versitygw-admin-wait.err; do
  sleep 2
done

ensure_user() {
  access_key="$1"
  secret_key="$2"
  user_id="$3"
  group_id="$4"

  if admin list-users | grep -q "${access_key}"; then
    log_info "VersityGW user ${access_key} already exists."
    return 0
  fi

  log_step "Creating VersityGW user ${access_key}..."
  admin create-user \
    -a "${access_key}" \
    -s "${secret_key}" \
    -r user \
    -ui "${user_id}" \
    -gi "${group_id}"
}

ensure_user "user-a-key" "user-a-secret" 1001 1001
ensure_user "user-b-key" "user-b-secret" 1002 1002

log_step "Configured VersityGW users:"
admin list-users
log_done "VersityGW user provisioning complete."
