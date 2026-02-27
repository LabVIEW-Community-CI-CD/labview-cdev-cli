#Requires -Version 7.0
#Requires -Modules Pester

$ErrorActionPreference = 'Stop'

Describe 'cdev CLI runtime image publish contract' {
    BeforeAll {
        $script:repoRoot = (Resolve-Path -Path (Join-Path $PSScriptRoot '..')).Path
        $script:dockerfilePath = Join-Path $script:repoRoot 'tools/cli-runtime/Dockerfile'
        $script:workflowPath = Join-Path $script:repoRoot '.github/workflows/publish-cli-runtime-image.yml'
        $script:attestationScriptPath = Join-Path $script:repoRoot 'scripts/Write-CliDependencyAttestation.ps1'
        $script:agentsPath = Join-Path $script:repoRoot 'AGENTS.md'

        foreach ($path in @($script:dockerfilePath, $script:workflowPath, $script:attestationScriptPath, $script:agentsPath)) {
            if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
                throw "Missing runtime-image contract file: $path"
            }
        }

        $script:dockerfile = Get-Content -LiteralPath $script:dockerfilePath -Raw
        $script:workflow = Get-Content -LiteralPath $script:workflowPath -Raw
        $script:attestationScript = Get-Content -LiteralPath $script:attestationScriptPath -Raw
        $script:agents = Get-Content -LiteralPath $script:agentsPath -Raw
    }

    It 'builds a PowerShell-based CLI runtime image with required tooling and entrypoint' {
        $script:dockerfile | Should -Match 'mcr\.microsoft\.com/powershell'
        $script:dockerfile | Should -Match 'git jq gh'
        $script:dockerfile | Should -Match 'ENTRYPOINT \["pwsh", "-NoProfile", "-File", "/opt/cdev-cli/scripts/Invoke-CdevCli\.ps1"\]'
        $script:dockerfile | Should -Match 'COPY scripts'
    }

    It 'defines deterministic GHCR publish flow with package write permission' {
        $script:workflow | Should -Match 'workflow_dispatch:'
        $script:workflow | Should -Match 'push:'
        $script:workflow | Should -Match 'packages:\s*write'
        $script:workflow | Should -Match "tr '\[:upper:\]' '\[:lower:\]'"
        $script:workflow | Should -Match 'image_repo="ghcr\.io/\$\{owner_lc\}/labview-cdev-cli-runtime"'
        $script:workflow | Should -Match 'docker/login-action@v3'
        $script:workflow | Should -Match 'docker/build-push-action@v6'
    }

    It 'publishes immutable tags and summary digest evidence' {
        $script:workflow | Should -Match 'sha-\$\{short_sha\}'
        $script:workflow | Should -Match 'v1-\$\{date_utc\}'
        $script:workflow | Should -Match 'steps\.build\.outputs\.digest'
    }

    It 'emits CLI dependency attestation with sync-guard parity evidence' {
        $script:workflow | Should -Match 'Capture fork/upstream sync evidence'
        $script:workflow | Should -Match 'Test-ForkUpstreamSyncGuard\.ps1'
        $script:workflow | Should -Match 'Write-CliDependencyAttestation\.ps1'
        $script:workflow | Should -Match 'Upload CLI dependency attestation'
        $script:workflow | Should -Match 'cli-dependency-attestation\.json'
        $script:workflow | Should -Match 'Upload sync-guard evidence report'
        $script:workflow | Should -Match 'fork-upstream-sync-drift-report\.json'

        $script:attestationScript | Should -Match 'schema_version'
        $script:attestationScript | Should -Match 'source_commit'
        $script:attestationScript | Should -Match 'runtime_image'
        $script:attestationScript | Should -Match 'canonical_runtime_repository'
        $script:attestationScript | Should -Match 'sync_guard_evidence'
        $script:attestationScript | Should -Match 'parity_evidence'
        $script:attestationScript | Should -Match 'required_asset_digest_match'
    }

    It 'documents fork-safe mutation target for runtime publish operations' {
        $script:agents | Should -Match 'Allowed mutation target'
        $script:agents | Should -Match 'svelderrainruiz/labview-cdev-cli'
        $script:agents | Should -Match 'ghcr\.io/labview-community-ci-cd/labview-cdev-cli-runtime'
        $script:agents | Should -Match 'cli-dependency-attestation\.json'
    }
}
