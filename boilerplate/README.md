# FluxCD Boilerplate Generator

This directory contains a [`gruntwork-io/boilerplate`](https://github.com/gruntwork-io/boilerplate) template to generate sample FluxCD app manifests.

## Contents

- `fluxcd-app-template/`: template directory.
- `fluxcd-app-template-vars.yaml.example`: example variable values.
- `Makefile`: helper targets to generate manifests.

## Prerequisites

- Go toolchain (for installing `boilerplate`), or a preinstalled `boilerplate` binary.
- Optional: `yq` for automatic output folder naming from `app_name`.

Install `boilerplate`:

```bash
go install github.com/gruntwork-io/boilerplate@latest
```

## Quick start

From repository root:

```bash
cd boilerplate
make vars-example
```

Edit `fluxcd-app-template-vars.yaml` and set values such as:

- `app_name`
- `app_namespace`
- `chart_repo_url`
- `chart_name`
- `chart_version`
- `chart_release_name`

Generate manifests:

```bash
make generate-fluxcd-app
```

By default, output is written to:

- `./output/<app_name>` when `yq` is installed
- `./output/` when `yq` is not installed or `app_name` cannot be read

## Custom output directory

Set `OUTPUT_DIR` explicitly:

```bash
make generate-fluxcd-app OUTPUT_DIR=../kubernetes/platform/my-app
```

## Command reference

Show available targets:

```bash
make help
```

Run generation directly with custom vars/template:

```bash
make generate-fluxcd-app \
  TEMPLATE_DIR=fluxcd-app-template \
  VARS_FILE=fluxcd-app-template-vars.yaml \
  OUTPUT_DIR=../kubernetes/platform/my-app
```

## Generated files

The template generates a FluxCD-ready app structure like:

```text
<output>/<app_name>/
├── app.yaml
├── helmrepo.yaml
├── app/
│   ├── base/
│   │   ├── helm.yaml
│   │   ├── kustomization.yaml
│   │   ├── kustomizeconfig.yaml
│   │   ├── ns.yaml
│   │   └── values.yaml
│   ├── components/
│   │   └── componentX/
│   │       ├── helm-patch.yaml
│   │       ├── kustomization.yaml
│   │       └── values.yaml
│   └── overlays/
│       ├── dev/
│       │   ├── helm-patch.yaml
│       │   ├── kustomization.yaml
│       │   └── values.yaml
│       └── prod/
│           ├── helm-patch.yaml
│           ├── kustomization.yaml
│           └── values.yaml
└── config/
    ├── base/kustomization.yaml
    └── overlays/
        ├── dev/kustomization.yaml
        └── prod/kustomization.yaml
```

### FluxCD manifests created

- `app.yaml`
  - Creates two Flux `Kustomization` resources in `flux-system`:
    - `<app_name>-app`: points to `./kubernetes/platform/<app_name>/app/overlays/prod`
    - `<app_name>-config`: points to `./kubernetes/platform/<app_name>/config/overlays/prod`
  - `-config` depends on `-app` through `dependsOn`.

- `helmrepo.yaml`
  - Creates a Flux `HelmRepository` in `flux-system`.
  - Uses `chart_repo_url` as repository URL.

### App manifests (`app/`)

- `app/base/helm.yaml`
  - Creates the Flux `HelmRelease` for `chart_name` and `chart_version`.
  - Uses the `HelmRepository` created in `helmrepo.yaml`.
  - Sets release name (`chart_release_name`) and namespace (`app_namespace`).

- `app/base/ns.yaml`
  - Creates the target Kubernetes namespace (`app_namespace`).

- `app/base/kustomization.yaml`
  - Base kustomize entrypoint for app resources.
  - Generates ConfigMap `<app_name>-helm-values` from `values.yaml`.

- `app/base/kustomizeconfig.yaml`
  - Ensures Kustomize name references for `valuesFrom` in `HelmRelease` are updated correctly.

- `app/overlays/dev/*` and `app/overlays/prod/*`
  - Overlay-specific values and patches.
  - `helm-patch.yaml` appends overlay value files into `spec.valuesFrom`.

- `app/components/componentX/*`
  - Optional component pattern for reusable patch/value bundles.
  - Demonstrates how to merge extra chart values through a Kustomize `Component`.

### Config manifests (`config/`)

- `config/base/kustomization.yaml`
  - Base location for non-Helm Kubernetes resources tied to the app (ConfigMaps, policies, etc.).

- `config/overlays/dev/kustomization.yaml` and `config/overlays/prod/kustomization.yaml`
  - Environment overlays for configuration resources.

### Reconciliation flow in Flux

1. Apply `helmrepo.yaml` so chart source is available.
2. Apply `app.yaml` to register Flux `Kustomization` objects.
3. Flux reconciles `<app_name>-app` (namespace + HelmRelease).
4. Flux reconciles `<app_name>-config` after app reconciliation.

## Example: copy generated app into this repo

From repository root, after generation:

```bash
APP_NAME=opentelemetry-demo

# 1) Generate manifests into boilerplate/output/<app_name>
cd boilerplate
make generate-fluxcd-app
cd ..

# 2) Copy app structure into kubernetes/platform/<app_name>
mkdir -p "kubernetes/platform/${APP_NAME}"
cp -r "boilerplate/output/${APP_NAME}/app" "kubernetes/platform/${APP_NAME}/"
cp -r "boilerplate/output/${APP_NAME}/config" "kubernetes/platform/${APP_NAME}/"

# 3) Copy Flux entry manifests (Kustomizations + HelmRepository)
cp "boilerplate/output/${APP_NAME}/app.yaml" "kubernetes/platform/${APP_NAME}/"
cp "boilerplate/output/${APP_NAME}/helmrepo.yaml" "kubernetes/platform/${APP_NAME}/"

# 4) Review and commit
git add "kubernetes/platform/${APP_NAME}"
git status
```

Optional one-step generation directly into platform path:

```bash
cd boilerplate
make generate-fluxcd-app OUTPUT_DIR=../kubernetes/platform/opentelemetry-demo
```
