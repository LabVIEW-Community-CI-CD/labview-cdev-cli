#Requires -Version 7.0
[CmdletBinding()]
param(
    [Parameter()]
    [ValidatePattern('^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$')]
    [string]$ForkRepository = 'svelderrainruiz/labview-cdev-cli',

    [Parameter()]
    [ValidatePattern('^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$')]
    [string]$UpstreamRepository = 'LabVIEW-Community-CI-CD/labview-cdev-cli',

    [Parameter()]
    [ValidatePattern('^[A-Za-z0-9._/-]+$')]
    [string]$Branch = 'main',

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$OutputRoot = (Join-Path (Get-Location) 'artifacts/force-align'),

    [Parameter()]
    [ValidateRange(30, 3600)]
    [int]$CiWaitTimeoutSeconds = 900,

    [Parameter()]
    [ValidateRange(5, 120)]
    [int]$CiPollIntervalSeconds = 10,

    [Parameter()]
    [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Write-JsonFile {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,
        [Parameter(Mandatory = $true)]
        $Object
    )

    $directory = Split-Path -Path $Path -Parent
    if (-not [string]::IsNullOrWhiteSpace($directory)) {
        New-Item -Path $directory -ItemType Directory -Force | Out-Null
    }

    $Object | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath $Path -Encoding utf8
}

function Invoke-GhJson {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Arguments,
        [Parameter(Mandatory = $true)]
        [string]$Description
    )

    $output = & gh @Arguments 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to $Description. $([string]::Join("`n", @($output)))"
    }

    $text = [string]::Join("`n", @($output))
    if ([string]::IsNullOrWhiteSpace($text)) {
        return $null
    }

    return ($text | ConvertFrom-Json -Depth 100 -ErrorAction Stop)
}

function Invoke-GhRaw {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Arguments,
        [Parameter(Mandatory = $true)]
        [string]$Description
    )

    $output = & gh @Arguments 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to $Description. $([string]::Join("`n", @($output)))"
    }

    return ([string]::Join("`n", @($output))).Trim()
}

function Get-ObjectPropertyValue {
    param(
        [Parameter(Mandatory = $true)]
        $Object,
        [Parameter(Mandatory = $true)]
        [string]$Name,
        [Parameter()]
        $Default = $null
    )

    if ($null -eq $Object) {
        return $Default
    }

    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) {
        return $Default
    }

    return $property.Value
}

function Convert-BranchProtectionToUpdatePayload {
    param(
        [Parameter(Mandatory = $true)]
        $Protection
    )

    $requiredStatusChecks = $null
    $requiredStatusChecksSource = Get-ObjectPropertyValue -Object $Protection -Name 'required_status_checks'
    if ($null -ne $requiredStatusChecksSource) {
        $requiredStatusChecks = [ordered]@{
            strict = [bool](Get-ObjectPropertyValue -Object $requiredStatusChecksSource -Name 'strict' -Default $false)
            contexts = @((Get-ObjectPropertyValue -Object $requiredStatusChecksSource -Name 'contexts' -Default @()) | ForEach-Object { [string]$_ })
        }
    }

    $requiredPullRequestReviews = $null
    $requiredPullRequestReviewsSource = Get-ObjectPropertyValue -Object $Protection -Name 'required_pull_request_reviews'
    if ($null -ne $requiredPullRequestReviewsSource) {
        $requiredPullRequestReviews = [ordered]@{
            dismiss_stale_reviews = [bool](Get-ObjectPropertyValue -Object $requiredPullRequestReviewsSource -Name 'dismiss_stale_reviews' -Default $false)
            require_code_owner_reviews = [bool](Get-ObjectPropertyValue -Object $requiredPullRequestReviewsSource -Name 'require_code_owner_reviews' -Default $false)
            require_last_push_approval = [bool](Get-ObjectPropertyValue -Object $requiredPullRequestReviewsSource -Name 'require_last_push_approval' -Default $false)
            required_approving_review_count = [int](Get-ObjectPropertyValue -Object $requiredPullRequestReviewsSource -Name 'required_approving_review_count' -Default 0)
        }
    }

    $restrictions = $null
    $restrictionsSource = Get-ObjectPropertyValue -Object $Protection -Name 'restrictions'
    if ($null -ne $restrictionsSource) {
        $restrictions = [ordered]@{
            users = @((Get-ObjectPropertyValue -Object $restrictionsSource -Name 'users' -Default @()) | ForEach-Object { [string]$_.login })
            teams = @((Get-ObjectPropertyValue -Object $restrictionsSource -Name 'teams' -Default @()) | ForEach-Object { [string]$_.slug })
            apps = @((Get-ObjectPropertyValue -Object $restrictionsSource -Name 'apps' -Default @()) | ForEach-Object { [string]$_.slug })
        }
    }

    $enforceAdminsSource = Get-ObjectPropertyValue -Object $Protection -Name 'enforce_admins'
    $requiredLinearHistorySource = Get-ObjectPropertyValue -Object $Protection -Name 'required_linear_history'
    $allowForcePushesSource = Get-ObjectPropertyValue -Object $Protection -Name 'allow_force_pushes'
    $allowDeletionsSource = Get-ObjectPropertyValue -Object $Protection -Name 'allow_deletions'
    $blockCreationsSource = Get-ObjectPropertyValue -Object $Protection -Name 'block_creations'
    $requiredConversationSource = Get-ObjectPropertyValue -Object $Protection -Name 'required_conversation_resolution'
    $lockBranchSource = Get-ObjectPropertyValue -Object $Protection -Name 'lock_branch'
    $allowForkSyncingSource = Get-ObjectPropertyValue -Object $Protection -Name 'allow_fork_syncing'

    return [ordered]@{
        required_status_checks = $requiredStatusChecks
        enforce_admins = [bool](Get-ObjectPropertyValue -Object $enforceAdminsSource -Name 'enabled' -Default $false)
        required_pull_request_reviews = $requiredPullRequestReviews
        restrictions = $restrictions
        required_linear_history = [bool](Get-ObjectPropertyValue -Object $requiredLinearHistorySource -Name 'enabled' -Default $false)
        allow_force_pushes = [bool](Get-ObjectPropertyValue -Object $allowForcePushesSource -Name 'enabled' -Default $false)
        allow_deletions = [bool](Get-ObjectPropertyValue -Object $allowDeletionsSource -Name 'enabled' -Default $false)
        block_creations = [bool](Get-ObjectPropertyValue -Object $blockCreationsSource -Name 'enabled' -Default $false)
        required_conversation_resolution = [bool](Get-ObjectPropertyValue -Object $requiredConversationSource -Name 'enabled' -Default $false)
        lock_branch = [bool](Get-ObjectPropertyValue -Object $lockBranchSource -Name 'enabled' -Default $false)
        allow_fork_syncing = [bool](Get-ObjectPropertyValue -Object $allowForkSyncingSource -Name 'enabled' -Default $false)
    }
}

function Wait-ForCiSuccess {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Repository,
        [Parameter(Mandatory = $true)]
        [string]$BranchName,
        [Parameter(Mandatory = $true)]
        [string]$TargetSha,
        [Parameter(Mandatory = $true)]
        [DateTime]$DispatchFloorUtc,
        [Parameter(Mandatory = $true)]
        [int]$TimeoutSeconds,
        [Parameter(Mandatory = $true)]
        [int]$PollSeconds
    )

    $deadlineUtc = (Get-Date).ToUniversalTime().AddSeconds($TimeoutSeconds)
    while ((Get-Date).ToUniversalTime() -lt $deadlineUtc) {
        $runs = Invoke-GhJson -Arguments @(
            'run', 'list',
            '-R', $Repository,
            '--branch', $BranchName,
            '--workflow', 'CI Pipeline',
            '--event', 'push',
            '--limit', '20',
            '--json', 'databaseId,headSha,status,conclusion,createdAt,url'
        ) -Description "query CI runs for '$Repository@$BranchName'"

        $candidate = @($runs |
            Where-Object {
                [string]$_.headSha -eq $TargetSha -and
                [DateTime]::Parse([string]$_.createdAt).ToUniversalTime() -ge $DispatchFloorUtc
            } |
            Sort-Object -Property { [DateTime]::Parse([string]$_.createdAt).ToUniversalTime() } -Descending |
            Select-Object -First 1)

        if ($candidate.Count -eq 1) {
            $run = $candidate[0]
            if ([string]$run.status -eq 'completed') {
                if ([string]$run.conclusion -eq 'success') {
                    return [ordered]@{
                        status = 'success'
                        run_id = [string]$run.databaseId
                        url = [string]$run.url
                    }
                }

                throw "CI Pipeline run failed for $TargetSha. conclusion=$([string]$run.conclusion) url=$([string]$run.url)"
            }
        }

        Start-Sleep -Seconds $PollSeconds
    }

    throw "Timed out waiting for CI Pipeline success for $TargetSha in $Repository@$BranchName."
}

if (-not (Get-Command -Name 'gh' -ErrorAction SilentlyContinue)) {
    throw 'GitHub CLI (gh) is required.'
}

$timestamp = (Get-Date).ToUniversalTime().ToString('yyyyMMddHHmmss')
$outputDirectory = Join-Path $OutputRoot "$Branch-$timestamp"
New-Item -Path $outputDirectory -ItemType Directory -Force | Out-Null

$reportPath = Join-Path $outputDirectory 'controlled-force-align-report.json'
$protectionSnapshotPath = Join-Path $outputDirectory 'branch-protection.snapshot.json'
$protectionRelaxedPath = Join-Path $outputDirectory 'branch-protection.relaxed.json'
$protectionRestorePath = Join-Path $outputDirectory 'branch-protection.restore.json'

$report = [ordered]@{
    schema_version = '1.0'
    timestamp_utc = (Get-Date).ToUniversalTime().ToString('o')
    fork_repository = $ForkRepository
    upstream_repository = $UpstreamRepository
    branch = $Branch
    dry_run = [bool]$DryRun
    status = 'fail'
    reason_code = ''
    message = ''
    output_directory = $outputDirectory
    pre_alignment = [ordered]@{}
    post_alignment = [ordered]@{}
    protection_restore_attempted = $false
    protection_restore_succeeded = $false
    ci_verification = [ordered]@{
        status = 'skipped'
        run_id = ''
        url = ''
    }
}

$snapshotProtectionJson = $null
$restoreErrorMessage = ''
$skipMutation = $false

try {
    $upstreamHead = Invoke-GhRaw -Arguments @('api', "repos/$UpstreamRepository/commits/$Branch", '--jq', '.sha') -Description "query upstream head SHA"
    $forkHeadBefore = Invoke-GhRaw -Arguments @('api', "repos/$ForkRepository/commits/$Branch", '--jq', '.sha') -Description "query fork head SHA"

    if ($upstreamHead -notmatch '^[0-9a-f]{40}$' -or $forkHeadBefore -notmatch '^[0-9a-f]{40}$') {
        throw "Unable to resolve valid branch SHAs. upstream='$upstreamHead' fork='$forkHeadBefore'"
    }

    $report.pre_alignment = [ordered]@{
        upstream_head = $upstreamHead
        fork_head = $forkHeadBefore
        already_aligned = ($upstreamHead -eq $forkHeadBefore)
    }

    $snapshotProtectionJson = Invoke-GhJson -Arguments @('api', "repos/$ForkRepository/branches/$Branch/protection") -Description "snapshot branch protection"
    Write-JsonFile -Path $protectionSnapshotPath -Object $snapshotProtectionJson
    $restoreProtection = Convert-BranchProtectionToUpdatePayload -Protection $snapshotProtectionJson
    Write-JsonFile -Path $protectionRestorePath -Object $restoreProtection

    $relaxedProtection = [ordered]@{
        required_status_checks = $null
        enforce_admins = $false
        required_pull_request_reviews = $null
        restrictions = $null
        required_linear_history = $false
        allow_force_pushes = $true
        allow_deletions = $false
        block_creations = $false
        required_conversation_resolution = $false
        lock_branch = $false
        allow_fork_syncing = $false
    }
    Write-JsonFile -Path $protectionRelaxedPath -Object $relaxedProtection

    if ($upstreamHead -eq $forkHeadBefore) {
        $skipMutation = $true
        $report.status = 'pass'
        $report.reason_code = 'already_aligned'
        $report.message = "Fork '$ForkRepository@$Branch' is already aligned to upstream SHA '$upstreamHead'."
        $report.post_alignment = [ordered]@{
            fork_head = $forkHeadBefore
            upstream_head = $upstreamHead
            parity = $true
        }
        $report.ci_verification = [ordered]@{
            status = if ($DryRun) { 'skipped_dry_run' } else { 'skipped_no_alignment' }
            run_id = ''
            url = ''
        }
    }

    if (-not $skipMutation) {
        $alignDispatchFloorUtc = (Get-Date).ToUniversalTime()

        if (-not $DryRun) {
            & gh api -X PUT "repos/$ForkRepository/branches/$Branch/protection" --input $protectionRelaxedPath
            if ($LASTEXITCODE -ne 0) {
                throw "Failed to relax branch protection for '$ForkRepository@$Branch'."
            }

            & gh api -X PATCH "repos/$ForkRepository/git/refs/heads/$Branch" -f sha=$upstreamHead -F force=true
            if ($LASTEXITCODE -ne 0) {
                throw "Failed to force-align '$ForkRepository@$Branch' to '$upstreamHead'."
            }
        }

        $forkHeadAfter = if ($DryRun) { $upstreamHead } else {
            Invoke-GhRaw -Arguments @('api', "repos/$ForkRepository/commits/$Branch", '--jq', '.sha') -Description "query fork head SHA after alignment"
        }
        $parity = ($forkHeadAfter -eq $upstreamHead)
        if (-not $parity) {
            throw "Fork head mismatch after alignment. expected='$upstreamHead' actual='$forkHeadAfter'"
        }

        if (-not $DryRun) {
            $ciResult = Wait-ForCiSuccess `
                -Repository $ForkRepository `
                -BranchName $Branch `
                -TargetSha $upstreamHead `
                -DispatchFloorUtc $alignDispatchFloorUtc `
                -TimeoutSeconds $CiWaitTimeoutSeconds `
                -PollSeconds $CiPollIntervalSeconds
            $report.ci_verification = $ciResult
        } else {
            $report.ci_verification = [ordered]@{
                status = 'skipped_dry_run'
                run_id = ''
                url = ''
            }
        }

        $report.post_alignment = [ordered]@{
            fork_head = $forkHeadAfter
            upstream_head = $upstreamHead
            parity = $parity
        }
        $report.status = 'pass'
        $report.reason_code = if ($DryRun) { 'dry_run' } else { 'aligned' }
        $report.message = if ($DryRun) {
            "Dry run completed. No mutations were applied. Target alignment SHA: '$upstreamHead'."
        } else {
            "Fork '$ForkRepository@$Branch' force-aligned to upstream SHA '$upstreamHead'."
        }
    }
}
catch {
    $report.status = 'fail'
    $report.reason_code = 'force_align_failed'
    $report.message = [string]$_.Exception.Message
}
finally {
    if ($null -ne $snapshotProtectionJson) {
        $report.protection_restore_attempted = $true
        if (-not $DryRun) {
            try {
                & gh api -X PUT "repos/$ForkRepository/branches/$Branch/protection" --input $protectionRestorePath
                if ($LASTEXITCODE -ne 0) {
                    throw 'gh api returned a non-zero exit code during protection restore.'
                }
                $report.protection_restore_succeeded = $true
            }
            catch {
                $report.protection_restore_succeeded = $false
                $restoreErrorMessage = [string]$_.Exception.Message
            }
        } else {
            $report.protection_restore_succeeded = $true
        }
    }

    if ($report.protection_restore_succeeded) {
        $restoredProtection = Invoke-GhJson -Arguments @('api', "repos/$ForkRepository/branches/$Branch/protection") -Description "verify restored branch protection"
        if ([bool]$restoredProtection.allow_force_pushes.enabled) {
            $report.status = 'fail'
            $report.reason_code = 'protection_restore_failed'
            $report.message = 'Branch protection restore verification failed: allow_force_pushes is still enabled.'
        }
        if (-not (@($restoredProtection.required_status_checks.contexts) -contains 'CI Pipeline')) {
            $report.status = 'fail'
            $report.reason_code = 'protection_restore_failed'
            $report.message = 'Branch protection restore verification failed: required status check `CI Pipeline` is missing.'
        }
    } elseif ($report.protection_restore_attempted) {
        $report.status = 'fail'
        $report.reason_code = 'protection_restore_failed'
        if ([string]::IsNullOrWhiteSpace($restoreErrorMessage)) {
            $report.message = 'Branch protection restore failed.'
        } else {
            $report.message = "Branch protection restore failed: $restoreErrorMessage"
        }
    }

    Write-JsonFile -Path $reportPath -Object $report
    Write-Output ($report | ConvertTo-Json -Depth 20)
}

if ($report.status -eq 'pass') {
    exit 0
}

exit 1
