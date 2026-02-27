# cdev CLI Runtime Image

Base runtime image for `labview-cdev-cli` command execution.

Publish repository:
- `ghcr.io/<repository-owner>/labview-cdev-cli-runtime`

Canonical consumer repository:
- `ghcr.io/labview-community-ci-cd/labview-cdev-cli-runtime`

Deterministic tags:
- `sha-<12-char-commit>`
- `v1-YYYYMMDD`
- `v1` (when promoted)

Local build:

```powershell
docker build -f .\tools\cli-runtime\Dockerfile -t cdev-cli-runtime:local .
```

Local run:

```powershell
docker run --rm cdev-cli-runtime:local help
```
