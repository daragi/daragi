$ErrorActionPreference = 'Stop'

$profileUser = 'daragi'
$readmePath = Join-Path (Split-Path $PSScriptRoot -Parent) 'README.md'
$headers = @{
    Accept = 'application/vnd.github+json'
    'X-GitHub-Api-Version' = '2022-11-28'
    'User-Agent' = 'daragi-profile-activity'
}

if ($env:GH_TOKEN) {
    $headers.Authorization = "Bearer $($env:GH_TOKEN)"
}

$events = Invoke-RestMethod -Uri "https://api.github.com/users/$profileUser/events/public?per_page=30" -Headers $headers

$activityLines = [System.Collections.Generic.List[string]]::new()

foreach ($event in $events) {
    if ($activityLines.Count -ge 8) {
        break
    }

    if ($event.created_at -is [DateTime]) {
        $eventTime = [DateTimeOffset]$event.created_at
    }
    else {
        $eventTime = [DateTimeOffset]::Parse(
            [string]$event.created_at,
            [Globalization.CultureInfo]::InvariantCulture,
            [Globalization.DateTimeStyles]::AssumeUniversal
        )
    }
    $timestamp = $eventTime.ToUniversalTime().ToOffset([TimeSpan]::FromHours(9)).ToString('yyyy-MM-dd HH:mm')
    $repoName = [string]$event.repo.name
    $repoUrl = "https://github.com/$repoName"

    switch ([string]$event.type) {
        'PushEvent' {
            $commitCount = if ($null -ne $event.payload.size) {
                [int]$event.payload.size
            }
            else {
                @($event.payload.commits).Count
            }
            $commitLabel = if ($commitCount -eq 1) { '1 commit' } else { "$commitCount commits" }
            $activityLines.Add("- **$timestamp KST** · **$commitLabel** → [$repoName]($repoUrl)")
        }
        'PullRequestEvent' {
            $action = [string]$event.payload.action
            $number = [int]$event.payload.number
            $activityLines.Add("- **$timestamp KST** · PR #$number $action → [$repoName]($repoUrl/pulls)")
        }
        'IssuesEvent' {
            $action = [string]$event.payload.action
            $number = [int]$event.payload.issue.number
            $activityLines.Add("- **$timestamp KST** · Issue #$number $action → [$repoName]($repoUrl/issues)")
        }
        'CreateEvent' {
            $refType = [string]$event.payload.ref_type
            $activityLines.Add("- **$timestamp KST** · $refType created → [$repoName]($repoUrl)")
        }
        'ReleaseEvent' {
            $tag = [string]$event.payload.release.tag_name
            $activityLines.Add("- **$timestamp KST** · Release $tag published → [$repoName]($repoUrl/releases)")
        }
    }
}

if ($activityLines.Count -eq 0) {
    $activityLines.Add('- 최근 공개 활동이 없습니다.')
}

$readme = [IO.File]::ReadAllText($readmePath)
$replacement = "<!--START_SECTION:activity-->`n$($activityLines -join "`n")`n<!--END_SECTION:activity-->"
$pattern = '(?s)<!--START_SECTION:activity-->.*?<!--END_SECTION:activity-->'

if (-not [regex]::IsMatch($readme, $pattern)) {
    throw 'Activity markers are missing from README.md.'
}

$updatedReadme = [regex]::Replace($readme, $pattern, $replacement, 1)

if ($updatedReadme -ne $readme) {
    [IO.File]::WriteAllText($readmePath, $updatedReadme, [Text.UTF8Encoding]::new($false))
}
