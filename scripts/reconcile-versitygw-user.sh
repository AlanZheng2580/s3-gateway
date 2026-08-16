#!/bin/sh
set -eu

: "${VGW_ADMIN_ENDPOINT:?VGW_ADMIN_ENDPOINT is required}"
: "${VGW_ADMIN_ACCESS_KEY:?VGW_ADMIN_ACCESS_KEY is required}"
: "${VGW_ADMIN_SECRET_KEY:?VGW_ADMIN_SECRET_KEY is required}"
: "${VGW_USER_ACCESS_KEY:?VGW_USER_ACCESS_KEY is required}"
: "${VGW_USER_STATE:=present}"

admin() {
  versitygw admin \
    -a "${VGW_ADMIN_ACCESS_KEY}" \
    -s "${VGW_ADMIN_SECRET_KEY}" \
    -er "${VGW_ADMIN_ENDPOINT}" \
    "$@"
}

user_exists() {
  admin list-users | awk -v access="${VGW_USER_ACCESS_KEY}" '$1 == access { found = 1 } END { exit !found }'
}

case "${VGW_USER_STATE}" in
  present)
    : "${VGW_USER_SECRET_KEY:?VGW_USER_SECRET_KEY is required when state is present}"
    : "${VGW_USER_ROLE:=user}"
    : "${VGW_USER_ID:=0}"
    : "${VGW_GROUP_ID:=0}"
    : "${VGW_PROJECT_ID:=0}"

    if user_exists; then
      echo "Updating VersityGW user ${VGW_USER_ACCESS_KEY}."
      admin update-user \
        -a "${VGW_USER_ACCESS_KEY}" \
        -s "${VGW_USER_SECRET_KEY}" \
        -r "${VGW_USER_ROLE}" \
        -ui "${VGW_USER_ID}" \
        -gi "${VGW_GROUP_ID}" \
        -pi "${VGW_PROJECT_ID}"
    else
      echo "Creating VersityGW user ${VGW_USER_ACCESS_KEY}."
      admin create-user \
        -a "${VGW_USER_ACCESS_KEY}" \
        -s "${VGW_USER_SECRET_KEY}" \
        -r "${VGW_USER_ROLE}" \
        -ui "${VGW_USER_ID}" \
        -gi "${VGW_GROUP_ID}" \
        -pi "${VGW_PROJECT_ID}"
    fi
    ;;
  absent)
    if user_exists; then
      echo "Deleting VersityGW user ${VGW_USER_ACCESS_KEY}."
      admin delete-user -a "${VGW_USER_ACCESS_KEY}"
    else
      echo "VersityGW user ${VGW_USER_ACCESS_KEY} is already absent."
    fi
    ;;
  *)
    echo "Unsupported VGW_USER_STATE: ${VGW_USER_STATE}" >&2
    exit 1
    ;;
esac

