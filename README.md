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

Provisioned VersityGW admin user, also allowed to use the gateway Web UI and admin API:

- Access key: `versitygw-admin-key`
- Secret key: `versitygw-admin-secret`

Gateway users:

| User | Access key | Secret key | Allowed bucket |
| --- | --- | --- | --- |
| User_A | `user-a-key` | `user-a-secret` | `bucket-user-a` |
| User_B | `user-b-key` | `user-b-secret` | `bucket-user-b` |

Buckets:

- `bucket-user-a`
- `bucket-user-b`
- `vgw-meta` for VersityGW S3-proxy metadata, including bucket policy metadata

`bucket-user-a` and `bucket-user-b` default to a 10MiB MinIO bucket quota for fast local failure testing. The quota is configurable with `USER_BUCKET_QUOTA_SIZE`.

VersityGW does not use the MinIO root credential for backend access. The MinIO provisioner creates `versitygw-minio-admin`, attaches MinIO's built-in `consoleAdmin` policy to it, and the VersityGW S3 backend is configured with that dedicated credential.

## Large LLM model upload settings

This lab is configured to exercise the same mechanics required for large LLM model uploads while keeping local tests small.

Current defaults:

| Setting | Default | Why |
| --- | --- | --- |
| `USER_BUCKET_QUOTA_SIZE` | `10MiB` | Keeps `./test-flow.sh` fast and verifies quota denial with an 11MiB object. |
| `USER_BUCKET_VERSIONING` | `suspend` | Avoids retaining old 10s/100s of GiB model versions after overwrites. |
| `MINIO_API_STALE_UPLOADS_EXPIRY` | `24h` | Cleans abandoned multipart upload parts after interrupted large uploads. |
| `MINIO_API_STALE_UPLOADS_CLEANUP_INTERVAL` | `1h` | Runs stale multipart cleanup frequently enough for local/dev. |
| VersityGW `--mp-max-parts` | `10000` | Keeps the S3 multipart part-count ceiling explicit. |
| VersityGW `--keep-alive` | enabled | Better behavior for large multipart transfer sessions. |
| VersityGW `--max-connections` | `1000` | Conservative local gateway protection. |
| VersityGW `--max-requests` | `500` | Conservative local in-flight request protection. |

For real LLM model uploads, override the quota before provisioning. Example:

```sh
USER_BUCKET_QUOTA_SIZE=1TiB docker compose run --rm -T minio-provisioner
```

If you need this value to persist across repeated commands, copy [.env.example](.env.example) to `.env` and edit:

```sh
cp .env.example .env
```

Recommended production-style starting points:

| Expected model size | Suggested bucket quota |
| --- | --- |
| 50GiB | `250GiB` or higher |
| 100-300GiB | `1TiB` or higher |
| 500GiB+ | `2TiB` or higher |

Do not size the quota exactly equal to the model file size. Leave room for multipart upload staging, retries, multiple models, and temporary overlap during replacement.

Use a multipart-capable client for large files. For AWS CLI:

```sh
aws configure set default.s3.multipart_threshold 64MB
aws configure set default.s3.multipart_chunksize 128MB
aws configure set default.s3.max_concurrent_requests 10
```

Then upload through VersityGW:

```sh
AWS_ACCESS_KEY_ID=user-a-key \
AWS_SECRET_ACCESS_KEY=user-a-secret \
aws --endpoint-url http://localhost:7070 \
  s3 cp ./model.safetensors s3://bucket-user-a/models/model.safetensors
```

For local testing with 10MiB quota, `./test-flow.sh` performs a real multipart upload using two parts: 5MiB + 1MiB. This verifies multipart behavior without requiring a large local file.

For actual 100GiB+ testing, make sure Docker has enough disk space. Prefer a host-mounted data path over a small Docker-managed volume, for example:

```yaml
volumes:
  - /data/mock-weka-minio:/data
```

Versioning is intentionally suspended. For large model artifacts, prefer explicit object keys instead of S3 bucket versioning, for example:

```text
models/llama-3.1/2026-08-05/model.safetensors
models/llama-3.1/latest.json
```

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

The repository also provides a `Makefile` for common operations:

```sh
make help
make validate
make up
make status
make test
make logs
make down
```

`make down` stops the containers but preserves the named volumes. `make reset`
deletes all mock bucket data, IAM state, and named volumes.

Useful endpoints:

- VersityGW S3 endpoint: `http://localhost:7070`
- VersityGW admin endpoint: `http://localhost:7071`
- VersityGW Web UI: `http://localhost:8080`
- MinIO S3 endpoint: `http://localhost:9000`
- MinIO console: `http://localhost:9001`

The VersityGW admin port `7071` is an authenticated API endpoint and does not
provide a browser homepage. Use the Web UI on port `8080`; it calls the S3 API
on port `7070` and the admin API on port `7071`.

### Access the Web UI through SSH port forwarding

The browser running on the client computer must be able to reach all three
VersityGW ports. Forwarding only port `8080` loads the page, but login and
gateway operations fail because the browser cannot reach ports `7070` and
`7071`.

From the client computer, such as a MacBook, run:

```sh
ssh \
  -L 8080:localhost:8080 \
  -L 7070:localhost:7070 \
  -L 7071:localhost:7071 \
  alan@vivo
```

Then open `http://localhost:8080` on the client. Verify the tunnel with:

```sh
curl http://localhost:7070/health
```

The expected response is `OK`.

### Web UI object deletion

The Web UI deletes objects with the S3 Multi-Object Delete API
(`POST /bucket?delete`). VersityGW v1.7.0 performs an initial bucket-resource
authorization check for this operation before checking each object. For
compatibility, each user policy grants the existing object actions on both the
user's exact bucket ARN and its object ARN pattern:

```json
"Resource": [
  "arn:aws:s3:::bucket-user-a",
  "arn:aws:s3:::bucket-user-a/*"
]
```

The policies still use exact bucket names: User_A has no grant for
`bucket-user-b`, and User_B has no grant for `bucket-user-a`. The acceptance
test verifies that each user can use Multi-Object Delete in their own bucket,
that cross-bucket delete attempts are denied, and that the target objects still
exist after those denied attempts.

After editing a policy, reapply both policies with:

```sh
make apply-policies
```

## Run verification

```sh
./test-flow.sh
```

The script:

1. Starts MinIO and VersityGW.
2. Re-runs all provisioning steps idempotently.
3. Confirms the provisioned VersityGW admin user can call the admin API.
4. Confirms User_A can read/write only `bucket-user-a`.
5. Confirms User_B can read/write only `bucket-user-b`.
6. Confirms User_A can complete a real multipart upload.
7. Confirms User_A cannot initiate multipart upload to User_B's bucket.
8. Confirms an 11MiB upload to a 10MiB bucket is rejected.

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
