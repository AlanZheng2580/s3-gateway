# Repository Guidelines

## Project Structure & Module Organization

This repository defines a local mock WEKA S3 lab using Docker Compose.

- `docker-compose.yml` orchestrates MinIO, VersityGW, provisioners, and tool containers.
- `scripts/` contains idempotent provisioning scripts for MinIO buckets/users/quotas and VersityGW users/policies.
- `policies/` contains VersityGW bucket policy JSON documents for User_A/User_B isolation.
- `test-flow.sh` runs the end-to-end verification flow.
- `.env.example` documents configurable defaults such as bucket quota and versioning behavior.
- `README.md` is the operator-facing setup and usage guide.

## Build, Test, and Development Commands

Use Docker Compose v2.

```sh
docker compose config --quiet
```

Validates Compose syntax.

```sh
sh -n scripts/provision-minio.sh scripts/provision-versitygw-users.sh scripts/provision-versitygw-policies.sh test-flow.sh
```

Checks shell syntax.

```sh
./test-flow.sh
```

Starts/provisions the lab and verifies bucket isolation, quota enforcement, and multipart upload behavior.

```sh
docker compose down -v
```

Resets containers and named volumes. This deletes mock bucket data and IAM state.

## Coding Style & Naming Conventions

Shell scripts must remain POSIX `sh` compatible. Use `set -eu`, quote variables, and keep provisioning idempotent. Prefer clear log helpers such as `log_step`, `log_info`, and `log_done`.

Use lowercase kebab-case for buckets, containers, and policy files, for example `bucket-user-a` and `bucket-user-a-policy.json`.

All Docker images must be pinned to explicit versions; do not use `latest`.

## Testing Guidelines

There is no separate unit test framework. `test-flow.sh` is the acceptance test and must pass before committing. It should fail fast on unexpected access grants, quota bypasses, or upload failures.

When changing policies, verify both positive and negative access paths. When changing upload behavior, keep tests small enough for local runs while preserving real S3 multipart semantics.

## Commit & Pull Request Guidelines

Commit history uses concise imperative messages, for example `Pin Docker image versions` and `Tune lab for LLM model uploads`. Follow that style.

Pull requests should include:

- summary of behavior/config changes;
- verification commands run;
- any required volume reset such as `docker compose down -v`;
- security impact for credentials, policies, quotas, or exposed ports.

## Security & Configuration Tips

This is a local mock lab. Credentials are intentionally hardcoded for reproducibility and must not be reused outside development. Keep `.env` untracked. Use `.env.example` for documented overrides.

