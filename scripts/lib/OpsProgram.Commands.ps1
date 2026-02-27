function Convert-CdevBooleanToString {
    param([Parameter(Mandatory = $true)][bool]$Value)
    if ($Value) {
        return 'true'
    }
    return 'false'
}

function Resolve-CdevOpsProgramRunId {
    param(
        [Parameter(Mandatory = $true)][string]$Repository,
        [Parameter(Mandatory = $true)][string]$Workflow
    )

    $runListJson = & gh run list -R $Repository --workflow $Workflow --limit 1 --json databaseId,status,conclusion,url,createdAt
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to resolve latest run for workflow '$Workflow' in '$Repository'."
    }

    $runs = @($runListJson | ConvertFrom-Json -ErrorAction Stop)
    if (@($runs).Count -eq 0) {
        throw "No runs found for workflow '$Workflow' in '$Repository'."
    }

    return [string]$runs[0].databaseId
}

function Invoke-CdevOpsProgramRun {
    param([string[]]$PassThroughArgs)

    Assert-CdevCommand -Name 'gh'
    $argsMap = Convert-CdevArgsToMap -InputArgs $PassThroughArgs

    $repository = if ($argsMap.ContainsKey('repo')) { [string]$argsMap['repo'] } else { 'LabVIEW-Community-CI-CD/labview-release-control-plane' }
    $branch = if ($argsMap.ContainsKey('branch')) { [string]$argsMap['branch'] } else { 'main' }
    $workflow = if ($argsMap.ContainsKey('workflow')) { [string]$argsMap['workflow'] } else { 'release-program.yml' }
    $mode = if ($argsMap.ContainsKey('mode')) { [string]$argsMap['mode'] } else { 'Validate' }
    $dryRun = if ($argsMap.ContainsKey('dry-run')) { [System.Convert]::ToBoolean($argsMap['dry-run']) } else { $true }
    $enrollmentRepo = if ($argsMap.ContainsKey('enrollment-repo')) { [string]$argsMap['enrollment-repo'] } else { 'LabVIEW-Community-CI-CD/labview-cdev-surface-fork' }
    $policyPath = if ($argsMap.ContainsKey('policy-path')) { [string]$argsMap['policy-path'] } else { 'contracts/platform-policy.json' }

    $dispatchArgs = @('workflow', 'run', $workflow, '-R', $repository, '--ref', $branch)
    if (-not [string]::IsNullOrWhiteSpace($mode)) {
        $dispatchArgs += @('-f', "mode=$mode")
    }
    $dispatchArgs += @('-f', "dry_run=$(Convert-CdevBooleanToString -Value $dryRun)")
    if (-not [string]::IsNullOrWhiteSpace($enrollmentRepo)) {
        $dispatchArgs += @('-f', "enrollment_repo=$enrollmentRepo")
    }
    if (-not [string]::IsNullOrWhiteSpace($policyPath)) {
        $dispatchArgs += @('-f', "policy_path=$policyPath")
    }

    & gh @dispatchArgs
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to dispatch release program workflow '$workflow' on '$repository' ref '$branch'."
    }

    return (New-CdevResult -Status 'succeeded' -Data ([ordered]@{
        repository = $repository
        workflow = $workflow
        branch = $branch
        mode = $mode
        dry_run = $dryRun
        enrollment_repo = $enrollmentRepo
        policy_path = $policyPath
        status = 'dispatched'
    }))
}

function Invoke-CdevOpsProgramStatus {
    param([string[]]$PassThroughArgs)

    Assert-CdevCommand -Name 'gh'
    $argsMap = Convert-CdevArgsToMap -InputArgs $PassThroughArgs

    $repository = if ($argsMap.ContainsKey('repo')) { [string]$argsMap['repo'] } else { 'LabVIEW-Community-CI-CD/labview-release-control-plane' }
    $workflow = if ($argsMap.ContainsKey('workflow')) { [string]$argsMap['workflow'] } else { 'release-program.yml' }
    $limit = if ($argsMap.ContainsKey('limit')) { [int]$argsMap['limit'] } else { 5 }

    $runListJson = & gh run list -R $repository --workflow $workflow --limit $limit --json databaseId,status,conclusion,url,headSha,event,createdAt,updatedAt
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to list release program runs for '$repository' workflow '$workflow'."
    }

    $runs = @($runListJson | ConvertFrom-Json -ErrorAction Stop)
    return (New-CdevResult -Status 'succeeded' -Data ([ordered]@{
        repository = $repository
        workflow = $workflow
        run_count = @($runs).Count
        runs = @($runs)
    }))
}

function Invoke-CdevOpsProgramFreeze {
    param([string[]]$PassThroughArgs)

    Assert-CdevCommand -Name 'gh'
    $argsMap = Convert-CdevArgsToMap -InputArgs $PassThroughArgs

    $repository = if ($argsMap.ContainsKey('repo')) { [string]$argsMap['repo'] } else { 'LabVIEW-Community-CI-CD/labview-release-control-plane' }
    $branch = if ($argsMap.ContainsKey('branch')) { [string]$argsMap['branch'] } else { 'main' }
    $workflow = if ($argsMap.ContainsKey('workflow')) { [string]$argsMap['workflow'] } else { 'release-program.yml' }
    $reason = if ($argsMap.ContainsKey('reason')) { [string]$argsMap['reason'] } else { 'manual_freeze' }

    & gh workflow run $workflow -R $repository --ref $branch -f mode=Freeze -f "freeze_reason=$reason"
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to dispatch freeze operation in '$repository' workflow '$workflow'."
    }

    return (New-CdevResult -Status 'succeeded' -Data ([ordered]@{
        repository = $repository
        workflow = $workflow
        branch = $branch
        operation = 'freeze'
        reason = $reason
        status = 'dispatched'
    }))
}

function Invoke-CdevOpsProgramUnfreeze {
    param([string[]]$PassThroughArgs)

    Assert-CdevCommand -Name 'gh'
    $argsMap = Convert-CdevArgsToMap -InputArgs $PassThroughArgs

    $repository = if ($argsMap.ContainsKey('repo')) { [string]$argsMap['repo'] } else { 'LabVIEW-Community-CI-CD/labview-release-control-plane' }
    $branch = if ($argsMap.ContainsKey('branch')) { [string]$argsMap['branch'] } else { 'main' }
    $workflow = if ($argsMap.ContainsKey('workflow')) { [string]$argsMap['workflow'] } else { 'release-program.yml' }
    $reason = if ($argsMap.ContainsKey('reason')) { [string]$argsMap['reason'] } else { 'manual_unfreeze' }

    & gh workflow run $workflow -R $repository --ref $branch -f mode=Unfreeze -f "unfreeze_reason=$reason"
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to dispatch unfreeze operation in '$repository' workflow '$workflow'."
    }

    return (New-CdevResult -Status 'succeeded' -Data ([ordered]@{
        repository = $repository
        workflow = $workflow
        branch = $branch
        operation = 'unfreeze'
        reason = $reason
        status = 'dispatched'
    }))
}

function Invoke-CdevOpsProgramDrill {
    param([string[]]$PassThroughArgs)

    Assert-CdevCommand -Name 'gh'
    $argsMap = Convert-CdevArgsToMap -InputArgs $PassThroughArgs

    $repository = if ($argsMap.ContainsKey('repo')) { [string]$argsMap['repo'] } else { 'LabVIEW-Community-CI-CD/labview-release-control-plane' }
    $branch = if ($argsMap.ContainsKey('branch')) { [string]$argsMap['branch'] } else { 'main' }
    $workflow = if ($argsMap.ContainsKey('workflow')) { [string]$argsMap['workflow'] } else { 'release-program.yml' }
    $drillType = if ($argsMap.ContainsKey('drill-type')) { [string]$argsMap['drill-type'] } else { 'recovery' }
    $dryRun = if ($argsMap.ContainsKey('dry-run')) { [System.Convert]::ToBoolean($argsMap['dry-run']) } else { $false }

    & gh workflow run $workflow -R $repository --ref $branch -f mode=Drill -f "drill_type=$drillType" -f "dry_run=$(Convert-CdevBooleanToString -Value $dryRun)"
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to dispatch drill operation in '$repository' workflow '$workflow'."
    }

    return (New-CdevResult -Status 'succeeded' -Data ([ordered]@{
        repository = $repository
        workflow = $workflow
        branch = $branch
        operation = 'drill'
        drill_type = $drillType
        dry_run = $dryRun
        status = 'dispatched'
    }))
}

function Invoke-CdevOpsProgramEvidenceExport {
    param([string[]]$PassThroughArgs)

    Assert-CdevCommand -Name 'gh'
    $argsMap = Convert-CdevArgsToMap -InputArgs $PassThroughArgs

    $repository = if ($argsMap.ContainsKey('repo')) { [string]$argsMap['repo'] } else { 'LabVIEW-Community-CI-CD/labview-release-control-plane' }
    $workflow = if ($argsMap.ContainsKey('workflow')) { [string]$argsMap['workflow'] } else { 'release-program.yml' }
    $runId = if ($argsMap.ContainsKey('run-id')) { [string]$argsMap['run-id'] } else { '' }
    $outputRoot = if ($argsMap.ContainsKey('output-root')) { [string]$argsMap['output-root'] } else { Join-Path (Get-Location).Path 'artifacts\ops-evidence' }
    $resolvedOutputRoot = [System.IO.Path]::GetFullPath($outputRoot)
    Ensure-CdevDirectory -Path $resolvedOutputRoot

    if ([string]::IsNullOrWhiteSpace($runId)) {
        $runId = Resolve-CdevOpsProgramRunId -Repository $repository -Workflow $workflow
    }

    & gh run download $runId -R $repository --dir $resolvedOutputRoot
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to download run artifacts for run '$runId' in '$repository'."
    }

    return (New-CdevResult -Status 'succeeded' -Data ([ordered]@{
        repository = $repository
        workflow = $workflow
        run_id = $runId
        output_root = $resolvedOutputRoot
    }))
}
