#Requires -Version 7.0
#Requires -Modules Pester

$ErrorActionPreference = 'Stop'

Describe 'cdev CLI runtime image publish contract' {
    BeforeAll {
        $script:repoRoot = (Resolve-Path -Path (Join-Path $PSScriptRoot '..')).Path
        $script:dockerfilePath = Join-Path $script:repoRoot 'tools/cli-runtime/Dockerfile'
        $script:workflowPath = Join-Path $script:repoRoot '.github/workflows/publish-cli-runtime-image.yml'
        $script:agentsPath = Join-Path $script:repoRoot 'AGENTS.md'

        foreach ($path in @($script:dockerfilePath, $script:workflowPath, $script:agentsPath)) {
            if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
                throw "Missing runtime-image contract file: $path"
            }
        }

        $script:dockerfile = Get-Content -LiteralPath $script:dockerfilePath -Raw
        $script:workflow = Get-Content -LiteralPath $script:workflowPath -Raw
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
        $script:workflow | Should -Match 'ghcr\.io/\$\{\{\s*github\.repository_owner\s*\}\}/labview-cdev-cli-runtime'
        $script:workflow | Should -Match 'docker/login-action@v3'
        $script:workflow | Should -Match 'docker/build-push-action@v6'
    }

    It 'publishes immutable tags and summary digest evidence' {
        $script:workflow | Should -Match 'sha-\$\{short_sha\}'
        $script:workflow | Should -Match 'v1-\$\{date_utc\}'
        $script:workflow | Should -Match 'steps\.build\.outputs\.digest'
    }

    It 'documents fork-safe mutation target for runtime publish operations' {
        $script:agents | Should -Match 'Allowed mutation target'
        $script:agents | Should -Match 'svelderrainruiz/labview-cdev-cli'
        $script:agents | Should -Match 'ghcr\.io/labview-community-ci-cd/labview-cdev-cli-runtime'
    }
}
