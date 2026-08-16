# VersityGW GitOps reconciliation

This directory contains the Kubernetes resources that reconcile VersityGW
users and bucket policies from Git and Vault. The root `kustomization.yaml`
generates ConfigMaps directly from the repository policy files and reconciliation
scripts.

## Assumptions

- Argo CD applies this repository with Kustomize.
- VersityGW is reachable as `versitygw` in namespace `mock-weka-s3`.
- The VersityGW admin API listens on port `7071` and S3 API on port `7070`.
- `ricoberger/vault-secrets-operator` is installed with the
  `ricoberger.de/v1alpha1` `VaultSecret` CRD.
- Vault KV v2 contains the paths and keys listed below.

Confirm the installed `VaultSecret` CRD before deploying. If the company uses a
different operator, adapt `vault-secrets.yaml` to its schema.

## Required Vault data

```text
kv/versitygw/admin/reconciler
  accessKey
  secretAccessKey

kv/versitygw/users/user-a
  secretAccessKey

kv/versitygw/users/user-b
  secretAccessKey
```

The Vault Secrets Operator creates Kubernetes Secrets with the same names as
the `VaultSecret` objects. Configure the operator reconciliation interval so a
Vault rotation updates the generated Kubernetes Secret.

## Desired user state

Non-secret user properties live in `user-metadata.yaml`. To remove a user, set:

```yaml
VGW_USER_STATE: absent
```

Do not remove the user manifest to request deletion. Explicit `absent` state
keeps deletion reviewable in Git. The secret reference is optional for an
absent user, so the Vault secret can be removed after VersityGW deletion has
succeeded.

## Reconciliation

User and policy CronJobs run every five minutes with
`concurrencyPolicy: Forbid`. User jobs call the authenticated VersityGW Admin
API. The policy job applies every `*-policy.json` file through the S3 API.

Run a reconciliation immediately when troubleshooting:

```sh
kubectl -n mock-weka-s3 create job \
  --from=cronjob/versitygw-user-a-reconciler \
  versitygw-user-a-reconcile-manual

kubectl -n mock-weka-s3 create job \
  --from=cronjob/versitygw-policy-reconciler \
  versitygw-policy-reconcile-manual
```

## Render

```sh
make k8s-validate
make k8s-render
```

Argo CD should point its Kustomize application at the repository root. Generated
ConfigMap names include a content hash, so policy or script changes update the
CronJob pod templates automatically.
