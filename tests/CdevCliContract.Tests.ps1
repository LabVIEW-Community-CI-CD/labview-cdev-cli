#Requires -Version 7.0
#Requires -Modules Pester

$ErrorActionPreference = 'Stop'

Describe 'cdev CLI command contract' {
    BeforeAll {
        $script:repoRoot = (Resolve-Path -Path (Join-Path $PSScriptRoot '..')).Path
        $script:entrypoint = Join-Path $script:repoRoot 'scripts/Invoke-CdevCli.ps1'
        $script:contractPath = Join-Path $script:repoRoot 'cli-contract.json'
        $script:agentsPath = Join-Path $script:repoRoot 'AGENTS.md'
        $script:readmePath = Join-Path $script:repoRoot 'README.md'

        foreach ($path in @($script:entrypoint, $script:contractPath, $script:agentsPath, $script:readmePath)) {
            if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
                throw "Missing required file: $path"
            }
        }

        $script:content = Get-Content -LiteralPath $script:entrypoint -Raw
        $script:contract = Get-Content -LiteralPath $script:contractPath -Raw | ConvertFrom-Json -ErrorAction Stop
        $script:agents = Get-Content -LiteralPath $script:agentsPath -Raw
        $script:readme = Get-Content -LiteralPath $script:readmePath -Raw
    }

    It 'defines required command groups in cli-contract' {
        $script:contract.commands.PSObject.Properties.Name | Should -Contain 'repos'
        $script:contract.commands.PSObject.Properties.Name | Should -Contain 'installer'
        $script:contract.commands.PSObject.Properties.Name | Should -Contain 'postactions'
        $script:contract.commands.PSObject.Properties.Name | Should -Contain 'linux'
        $script:contract.commands.PSObject.Properties.Name | Should -Contain 'ci'
        $script:contract.commands.PSObject.Properties.Name | Should -Contain 'release'
    }

    It 'implements required command tokens in entrypoint' {
        foreach ($token in @(
            'repos', 'doctor', 'surface', 'sync', 'installer', 'build', 'exercise', 'install',
            'postactions', 'collect', 'linux', 'deploy-ni', 'integration-gate', 'release', 'package'
        )) {
            $script:content | Should -Match ([regex]::Escape($token))
        }
    }

    It 'documents CLI orchestration in AGENTS and README' {
        foreach ($token in @('Invoke-CdevCli.ps1', 'repos doctor', 'installer exercise', 'postactions collect', 'linux deploy-ni', 'desktop-linux', 'nationalinstruments/labview:latest-linux')) {
            $script:agents | Should -Match ([regex]::Escape($token))
        }
        $script:readme | Should -Match ([regex]::Escape('Invoke-CdevCli.ps1'))
        $script:readme | Should -Match ([regex]::Escape('linux deploy-ni'))
    }

    It 'runs help command without requiring a surface root path' {
        $tempRoot = if ([string]::IsNullOrWhiteSpace($env:TEMP)) { [System.IO.Path]::GetTempPath() } else { $env:TEMP }
        $reportPath = Join-Path $tempRoot ("cdev-cli-help-" + [Guid]::NewGuid().ToString('N') + '.json')
        $previousSurfaceRoot = $env:CDEV_SURFACE_ROOT

        try {
            Remove-Item Env:CDEV_SURFACE_ROOT -ErrorAction SilentlyContinue
            & pwsh -NoProfile -File $script:entrypoint -ReportPath $reportPath help
            $LASTEXITCODE | Should -Be 0
            (Test-Path -LiteralPath $reportPath -PathType Leaf) | Should -BeTrue
        } finally {
            if ($null -eq $previousSurfaceRoot) {
                Remove-Item Env:CDEV_SURFACE_ROOT -ErrorAction SilentlyContinue
            } else {
                $env:CDEV_SURFACE_ROOT = $previousSurfaceRoot
            }
            Remove-Item -LiteralPath $reportPath -Force -ErrorAction SilentlyContinue
        }
    }

    It 'has parse-safe PowerShell syntax' {
        $tokens = $null
        $errors = $null
        [void][System.Management.Automation.Language.Parser]::ParseInput($script:content, [ref]$tokens, [ref]$errors)
        @($errors).Count | Should -Be 0
    }
}
