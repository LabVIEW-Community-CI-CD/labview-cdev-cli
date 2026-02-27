#Requires -Version 7.0
[CmdletBinding()]
param(
    [Parameter()]
    [string]$SourceCommit = '',

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$RuntimeImageRepository,

    [Parameter(Mandatory = $true)]
    [ValidatePattern('^sha256:[0-9a-f]{64}$')]
    [string]$RuntimeImageDigest,

    [Parameter()]
    [ValidatePattern('^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$')]
    [string]$UpstreamRepository = 'LabVIEW-Community-CI-CD/labview-cdev-cli',

    [Parameter()]
    [ValidatePattern('^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$')]
    [string]$ForkRepository = 'svelderrainruiz/labview-cdev-cli',

    [Parameter()]
    [ValidatePattern('^[A-Za-z0-9._/-]+$')]
    [string]$UpstreamBranch = 'main',

    [Parameter()]
    [ValidatePattern('^[A-Za-z0-9._/-]+$')]
    [string]$ForkBranch = 'main',

    [Parameter()]
    [string[]]$RequiredAssets = @(
        'cdev-cli-win-x64.zip',
        'cdev-cli-linux-x64.tar.gz'
    ),

    [Parameter()]
    [string]$SyncGuardReportPath = '',

    [Parameter()]
    [string]$OutputPath = 'cli-dependency-attestation.json'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-PropertyValueOrDefault {
    param(
        [Parameter()][object]$Object,
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter()][object]$DefaultValue = $null
    )

    if ($null -eq $Object) {
        return $DefaultValue
    }

    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) {
        return $DefaultValue
    }

    return $property.Value
}

if ([string]::IsNullOrWhiteSpace([string]$SourceCommit)) {
    $SourceCommit = [string]$env:GITHUB_SHA
}
if ([string]::IsNullOrWhiteSpace([string]$SourceCommit)) {
    $SourceCommit = 'unknown'
}

$syncGuardStatus = 'unavailable'
$syncGuardEvidence = [ordered]@{
    status = 'unavailable'
    reason = 'sync_guard_report_missing'
    report_path = ''
    upstream_repository = $UpstreamRepository
    fork_repository = $ForkRepository
    branch_parity = $null
    release_parity = $null
    asset_parity = @()
    mismatches = @()
}

if (-not [string]::IsNullOrWhiteSpace($SyncGuardReportPath) -and (Test-Path -LiteralPath $SyncGuardReportPath -PathType Leaf)) {
    try {
        $syncGuardReport = Get-Content -LiteralPath $SyncGuardReportPath -Raw | ConvertFrom-Json -Depth 20
        $syncGuardStatus = [string](Get-PropertyValueOrDefault -Object $syncGuardReport -Name 'status' -DefaultValue 'drift_detected')
        if ([string]::IsNullOrWhiteSpace($syncGuardStatus)) {
            $syncGuardStatus = 'drift_detected'
        }

        $syncGuardEvidence = [ordered]@{
            status = $syncGuardStatus
            reason = if ($syncGuardStatus -eq 'in_sync') { 'ok' } else { 'sync_drift_detected' }
            report_path = [System.IO.Path]::GetFullPath($SyncGuardReportPath)
            generated_at_utc = [string](Get-PropertyValueOrDefault -Object $syncGuardReport -Name 'generated_at_utc' -DefaultValue '')
            upstream_repository = [string](Get-PropertyValueOrDefault -Object $syncGuardReport -Name 'upstream_repository' -DefaultValue $UpstreamRepository)
            fork_repository = [string](Get-PropertyValueOrDefault -Object $syncGuardReport -Name 'fork_repository' -DefaultValue $ForkRepository)
            branch_parity = Get-PropertyValueOrDefault -Object $syncGuardReport -Name 'branch_parity' -DefaultValue $null
            release_parity = Get-PropertyValueOrDefault -Object $syncGuardReport -Name 'release_parity' -DefaultValue $null
            asset_parity = @(
                @(Get-PropertyValueOrDefault -Object $syncGuardReport -Name 'asset_parity' -DefaultValue @()) |
                    ForEach-Object {
                        [ordered]@{
                            asset = [string](Get-PropertyValueOrDefault -Object $_ -Name 'asset' -DefaultValue '')
                            upstream_digest = [string](Get-PropertyValueOrDefault -Object $_ -Name 'upstream_digest' -DefaultValue '')
                            fork_digest = [string](Get-PropertyValueOrDefault -Object $_ -Name 'fork_digest' -DefaultValue '')
                            matches = [bool](Get-PropertyValueOrDefault -Object $_ -Name 'matches' -DefaultValue $false)
                        }
                    }
            )
            mismatches = @(
                @(Get-PropertyValueOrDefault -Object $syncGuardReport -Name 'mismatches' -DefaultValue @()) |
                    ForEach-Object { [string]$_ }
            )
        }
    } catch {
        $syncGuardStatus = 'unavailable'
        $syncGuardEvidence = [ordered]@{
            status = 'unavailable'
            reason = 'sync_guard_report_parse_failed'
            message = [string]$_.Exception.Message
            report_path = [System.IO.Path]::GetFullPath($SyncGuardReportPath)
            upstream_repository = $UpstreamRepository
            fork_repository = $ForkRepository
            branch_parity = $null
            release_parity = $null
            asset_parity = @()
            mismatches = @()
        }
    }
}

$requiredAssetSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
foreach ($assetName in @($RequiredAssets)) {
    $normalizedAsset = ([string]$assetName).Trim()
    if (-not [string]::IsNullOrWhiteSpace($normalizedAsset)) {
        [void]$requiredAssetSet.Add($normalizedAsset)
    }
}

$assetParityRecords = @(
    @($syncGuardEvidence.asset_parity) |
        Where-Object { $requiredAssetSet.Contains([string]$_.asset) }
)
$assetParityComplete = ($requiredAssetSet.Count -gt 0) -and (@($assetParityRecords).Count -eq $requiredAssetSet.Count)
$assetParityMatches = $assetParityComplete -and (@($assetParityRecords | Where-Object { -not [bool]$_.matches }).Count -eq 0)
$branchParityMatches = [bool](Get-PropertyValueOrDefault -Object $syncGuardEvidence.branch_parity -Name 'matches' -DefaultValue $false)
$releaseParityMatches = [bool](Get-PropertyValueOrDefault -Object $syncGuardEvidence.release_parity -Name 'matches' -DefaultValue $false)

$attestation = [ordered]@{
    schema_version = '1.0'
    generated_at_utc = (Get-Date).ToUniversalTime().ToString('o')
    source_commit = $SourceCommit
    canonical_runtime_repository = 'ghcr.io/labview-community-ci-cd/labview-cdev-cli-runtime'
    runtime_image = [ordered]@{
        repository = $RuntimeImageRepository
        digest = $RuntimeImageDigest
    }
    sync_guard_evidence = $syncGuardEvidence
    parity_evidence = [ordered]@{
        branch_head_match = $branchParityMatches
        latest_release_tag_match = $releaseParityMatches
        required_asset_digest_match = $assetParityMatches
        required_assets = @($requiredAssetSet | Sort-Object)
    }
    status = if ($branchParityMatches -and $releaseParityMatches -and $assetParityMatches) { 'in_sync' } else { 'drift_detected' }
}

$outputDirectory = Split-Path -Path $OutputPath -Parent
if (-not [string]::IsNullOrWhiteSpace($outputDirectory)) {
    New-Item -Path $outputDirectory -ItemType Directory -Force | Out-Null
}

$attestation | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $OutputPath -Encoding utf8NoBOM
Write-Host "CLI dependency attestation written: $OutputPath"
