# labview-cdev-cli

Control-plane CLI for deterministic `C:\dev` workspace operations.

## Entrypoint

```powershell
powershell -NoProfile -ExecutionPolicy RemoteSigned -File .\scripts\Invoke-CdevCli.ps1 <group> <command> [options]
```

On Linux, invoke the same entrypoint with `pwsh -NoProfile -File`.

## Commands

- `help [topic]`
- `repos list`
- `repos doctor`
- `surface sync`
- `installer build`
- `installer exercise`
- `installer install`
- `postactions collect`
- `linux install`
- `linux deploy-ni`
- `ci integration-gate`
- `release package`

## Quick Start

```powershell
powershell -NoProfile -ExecutionPolicy RemoteSigned -File .\scripts\Invoke-CdevCli.ps1 repos list
powershell -NoProfile -ExecutionPolicy RemoteSigned -File .\scripts\Invoke-CdevCli.ps1 repos doctor --workspace-root C:\dev
powershell -NoProfile -ExecutionPolicy RemoteSigned -File .\scripts\Invoke-CdevCli.ps1 installer exercise --mode fast --iterations 1
powershell -NoProfile -ExecutionPolicy RemoteSigned -File .\scripts\Invoke-CdevCli.ps1 ci integration-gate --repo svelderrainruiz/labview-cdev-surface --branch main
```

## Linux Flow (Docker Desktop Linux)

```powershell
powershell -NoProfile -ExecutionPolicy RemoteSigned -File .\scripts\Invoke-CdevCli.ps1 linux install --workspace-root C:\dev-linux
powershell -NoProfile -ExecutionPolicy RemoteSigned -File .\scripts\Invoke-CdevCli.ps1 linux deploy-ni --workspace-root C:\dev-linux --docker-context desktop-linux --image nationalinstruments/labview:latest-linux
```

## Release Packaging

```powershell
powershell -NoProfile -ExecutionPolicy RemoteSigned -File .\scripts\Invoke-CdevCli.ps1 release package --output-root .\artifacts\release\cli
```

Release artifacts:
- `cdev-cli-win-x64.zip`
- `cdev-cli-linux-x64.tar.gz`
- `.sha256`
- `cdev-cli.spdx.json`
- `cdev-cli.slsa.json`

## Runtime Image (Base Layer)

`publish-cli-runtime-image.yml` publishes the base CLI runtime image to:
- `ghcr.io/<repository-owner>/labview-cdev-cli-runtime`

Canonical consumer reference remains:
- `ghcr.io/labview-community-ci-cd/labview-cdev-cli-runtime`

Deterministic tags:
- `sha-<12-char-commit>`
- `v1-YYYYMMDD`
- `v1` (when promoted)

Dispatch manually:

```powershell
gh workflow run publish-cli-runtime-image.yml `
  -R <owner>/labview-cdev-cli `
  -f promote_v1=true
```

## Operations Runbooks

- Controlled fork/upstream SHA parity recovery:
  - `docs/runbooks/controlled-force-align.md`
  - `scripts/Invoke-ControlledForkForceAlign.ps1`
