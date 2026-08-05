# Mock WEKA S3 Lab: MinIO + VersityGW

This repository runs a local S3 development lab:

- MinIO acts as the mock WEKA S3 backend.
- VersityGW acts as the S3 gateway/proxy and authenticates mock users.
- Docker Compose orchestrates the stack.

## Pinned image versions

All Docker images are pinned for repeatable local behavior:

| Service | Image |
| --- | --- |
| MinIO | `minio/minio:RELEASE.2025-04-22T22-12-26Z` |
| MinIO Client | `minio/mc:RELEASE.2025-04-16T18-13-26Z` |
| VersityGW | `versity/versitygw:v1.7.0` |
| AWS CLI | `amazon/aws-cli:2.36.16` |

The MinIO version is intentionally pinned before `RELEASE.2025-05-24T17-08-30Z` so the local Console keeps the older administrative UI behavior, including bucket/admin views that were removed or reduced in newer MinIO Console releases.

## Credentials and buckets

MinIO root credential, used only for backend provisioning:

- Access key: `weka-admin-superkey`
- Secret key: `weka-admin-supersecret`

Dedicated MinIO admin credential used by VersityGW to connect to the backend:

- Access key: `versitygw-minio-admin`
- Secret key: `versitygw-minio-admin-secret`

VersityGW root/admin credential, used for the gateway Web UI and admin API:

- Access key: `weka-admin-superkey`
- Secret key: `weka-admin-supersecret`

Gateway users:

| User | Access key | Secret key | Allowed bucket |
| --- | --- | --- | --- |
| User_A | `user-a-key` | `user-a-secret` | `bucket-user-a` |
| User_B | `user-b-key` | `user-b-secret` | `bucket-user-b` |

Buckets:

- `bucket-user-a`
- `bucket-user-b`
- `vgw-meta` for VersityGW S3-proxy metadata, including bucket policy metadata

`bucket-user-a` and `bucket-user-b` are configured with a 10MiB MinIO bucket quota for easy failure testing.

VersityGW does not use the MinIO root credential for backend access. The MinIO provisioner creates `versitygw-minio-admin`, attaches MinIO's built-in `consoleAdmin` policy to it, and the VersityGW S3 backend is configured with that dedicated credential.

## Important VersityGW policy note

VersityGW does not support AWS-style IAM user policies. The official behavior is that user policies are not used; access isolation is configured using bucket policies or bucket ACLs. This lab enforces isolation with VersityGW JSON bucket policies:

- [policies/bucket-user-a-policy.json](policies/bucket-user-a-policy.json)
- [policies/bucket-user-b-policy.json](policies/bucket-user-b-policy.json)

The policies explicitly allow each user only on their assigned bucket and explicitly deny the opposite user.

## Start the environment

Prerequisite: Docker with the Compose v2 plugin (`docker compose`).

```sh
docker compose up -d
```

Useful endpoints:

- VersityGW S3 endpoint: `http://localhost:7070`
- VersityGW admin endpoint: `http://localhost:7071`
- VersityGW Web UI: `http://localhost:8080`
- MinIO S3 endpoint: `http://localhost:9000`
- MinIO console: `http://localhost:9001`

## Run verification

```sh
./test-flow.sh
```

The script:

1. Starts MinIO and VersityGW.
2. Re-runs all provisioning steps idempotently.
3. Confirms User_A can read/write only `bucket-user-a`.
4. Confirms User_B can read/write only `bucket-user-b`.
5. Confirms an 11MiB upload to a 10MiB bucket is rejected.

## Manual S3 examples

User_A upload through VersityGW:

```sh
printf 'hello\n' | docker compose run --rm -T \
  -e AWS_ACCESS_KEY_ID=user-a-key \
  -e AWS_SECRET_ACCESS_KEY=user-a-secret \
  awscli --endpoint-url http://versitygw:7070 \
  s3 cp - s3://bucket-user-a/manual/hello.txt
```

User_B list through VersityGW:

```sh
docker compose run --rm -T \
  -e AWS_ACCESS_KEY_ID=user-b-key \
  -e AWS_SECRET_ACCESS_KEY=user-b-secret \
  awscli --endpoint-url http://versitygw:7070 \
  s3api list-objects-v2 --bucket bucket-user-b
```

## Reset local data

This removes the local containers and named volumes for a clean start:

```sh
docker compose down -v
```
