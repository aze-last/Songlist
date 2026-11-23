<#
run-verifier.ps1 -- Gate-first diff verifier runner (Windows; bash twin: run-verifier.sh).

Order of operations:
  1. Resolve the repo root and confirm the tool-less verifier agent exists.
  2. Run the deterministic gate only: diff-scan.ps1 -GateOnly.
     (allowlist -> denied files -> secrets -> pnpm/destructive). No model call on failure.
  3. Snapshot git status.
  4. Build the verifier packet: PLAN.md + changed-file list + tracked diff + untracked text.
  5. Call `opencode run --agent verifier --model <model>` with the packet.
  6. Snapshot git status again; a mutation is a contract violation.
  7. Require a final `Decision: APPROVE|BLOCK` line.

Exit codes: 0 = APPROVE, 1 = BLOCK (gate or verifier), 2 = runner/tamper error.

Model override: set VERIFIER_MODEL (or pass -Model). The free lineup rotates, so the
default lives in one variable below.
#>
param(
    [string]$TestFilter = "",
    [string]$Model = ""
)

$ErrorActionPreference = "Continue"
$DefaultVerifierModel = "opencode/deepseek-v4-flash-free"
$InlineLimit = 16000
$MaxPacketChars = 4 * 1024 * 1024

function Fail([string]$message, [int]$code = 2) {
    Write-Host "BLOCK: $message"
    Write-Host "RESULT: BLOCK"
    exit $code
}

function Get-StatusSnapshot {
    $lines = @(& git status --porcelain=v1 --untracked-files=all 2>$null)
    if ($LASTEXITCODE -ne 0) { Fail "git status failed - cannot enforce the clean-tree contract." }
    return ($lines -join "`n")
}

$script:RunnerBinaryExtensions = @(
    '.png', '.jpg', '.jpeg', '.gif', '.bmp', '.ico', '.webp', '.tif', '.tiff',
    '.pdf', '.zip', '.gz', '.tgz', '.tar', '.7z', '.rar', '.xz', '.bz2',
    '.exe', '.dll', '.so', '.dylib', '.bin', '.dat', '.pyc', '.pyo', '.class',
    '.jar', '.war', '.mp3', '.mp4', '.mov', '.avi', '.mkv', '.wav', '.flac',
    '.woff', '.woff2', '.ttf', '.otf', '.eot', '.sqlite', '.sqlite3', '.db',
    '.xls', '.xlsx', '.doc', '.docx', '.ppt', '.pptx', '.psd', '.blend'
)

function Test-RunnerBinary([string]$path) {
    $ext = [System.IO.Path]::GetExtension($path).ToLowerInvariant()
    if ($script:RunnerBinaryExtensions -contains $ext) { return $true }
    try {
        $full = (Get-Item -LiteralPath $path -ErrorAction Stop).FullName
        $fs = [System.IO.File]::OpenRead($full)
        try {
            $buf = New-Object byte[] 8000
            $n = $fs.Read($buf, 0, $buf.Length)
            for ($i = 0; $i -lt $n; $i++) {
                if ($buf[$i] -eq 0) { return $true }
            }
        } finally {
            $fs.Close()
        }
    } catch {
        return $true
    }
    return $false
}

function Add-UntrackedFileDiff([System.Text.StringBuilder]$sb, [string]$file) {
    [void]$sb.AppendLine("diff --git a/$file b/$file")
    if (Test-RunnerBinary $file) {
        [void]$sb.AppendLine("new file mode 100644")
        [void]$sb.AppendLine("Binary file (content not sent to the verifier).")
        [void]$sb.AppendLine("")
        return
    }
    $lines = @(Get-Content -LiteralPath $file -Encoding UTF8 -ErrorAction SilentlyContinue)
    [void]$sb.AppendLine("new file mode 100644")
    [void]$sb.AppendLine("--- /dev/null")
    [void]$sb.AppendLine("+++ b/$file")
    if ($lines.Count -eq 0) {
        [void]$sb.AppendLine("@@ -0,0 +0,0 @@")
    } else {
        [void]$sb.AppendLine("@@ -0,0 +1,$($lines.Count) @@")
        foreach ($line in $lines) { [void]$sb.AppendLine("+$line") }
    }
    [void]$sb.AppendLine("")
}

# 0. Preconditions -----------------------------------------------------------
$opencode = Get-Command opencode -ErrorAction SilentlyContinue
if (-not $opencode) { Fail "'opencode' is not on PATH - no verifier call was made." }

$rootOut = @(& git rev-parse --show-toplevel 2>$null)
if ($LASTEXITCODE -ne 0 -or $rootOut.Count -eq 0 -or [string]::IsNullOrWhiteSpace($rootOut[0])) {
    Fail "Cannot determine the repository root - no verifier call was made."
}
$root = $rootOut[0].Trim()
Set-Location -LiteralPath $root

$gate = Join-Path $root ".agents/team/diff-scan.ps1"
if (-not (Test-Path -LiteralPath $gate -PathType Leaf)) {
    Fail "Gate script not found at $gate - no verifier call was made."
}
$hasAgentDoc = Test-Path -LiteralPath (Join-Path $root ".opencode/agents/verifier.md") -PathType Leaf
$hasOpencodeJson = Test-Path -LiteralPath (Join-Path $root "opencode.json") -PathType Leaf
$hasTeamOpencodeJson = Test-Path -LiteralPath (Join-Path $root ".agents/team/opencode.json") -PathType Leaf
if (-not ($hasAgentDoc -or $hasOpencodeJson -or $hasTeamOpencodeJson)) {
    Fail "Verifier agent definition not found (neither .opencode/agents/verifier.md nor opencode.json) - no verifier call was made."
}
if (-not (Test-Path -LiteralPath (Join-Path $root "PLAN.md") -PathType Leaf)) {
    Fail "PLAN.md not found - spec conformance cannot be verified; no verifier call was made."
}

$Model = if ($Model.Trim() -ne "") { $Model.Trim() }
         elseif ($env:VERIFIER_MODEL -and $env:VERIFIER_MODEL.Trim() -ne "") { $env:VERIFIER_MODEL.Trim() }
         else { $DefaultVerifierModel }

# 1. Deterministic gate FIRST (no network, no model) -------------------------
Write-Host "--- Pre-Verifier Gate ---"
$gateArgs = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $gate, "-GateOnly")
if ($TestFilter -ne "") { $gateArgs += @("-TestFilter", $TestFilter) }
& powershell @gateArgs
if ($LASTEXITCODE -ne 0) {
    Fail "Deterministic gate returned BLOCK (exit $LASTEXITCODE); verifier was not called." 1
}

# 2. Build the packet --------------------------------------------------------
$hasHead = $false
& git rev-parse -q --verify HEAD *> $null
if ($LASTEXITCODE -eq 0) { $hasHead = $true }

$tracked = @()
if ($hasHead) {
    $tracked = @(& git diff HEAD --name-only 2>$null | Where-Object { $_ -ne "" })
    if ($LASTEXITCODE -ne 0) { Fail "git diff HEAD failed - cannot build the change set." }
} else {
    Write-Host "NOTE:  No HEAD commit; every file is presented as new content."
}

$untracked = @(& git ls-files --others --exclude-standard 2>$null | Where-Object { $_ -ne "" })
if ($LASTEXITCODE -ne 0) { Fail "git ls-files failed - cannot list untracked files." }

$allFiles = @($tracked + $untracked | Select-Object -Unique)

$planText = Get-Content -LiteralPath "PLAN.md" -Raw -Encoding UTF8
$remoteList = @(& git remote -v 2>$null | ForEach-Object { ($_ -split "\s+")[1] } | Where-Object { $_ } | Select-Object -Unique)

$sb = New-Object System.Text.StringBuilder
[void]$sb.AppendLine("You are the read-only diff verifier. Follow your agent contract exactly.")
[void]$sb.AppendLine("Review only the packet below. You have no tools; do not claim to inspect anything else.")
[void]$sb.AppendLine("")
[void]$sb.AppendLine("Repository: $root")
[void]$sb.AppendLine("Remotes: $(if ($remoteList.Count -gt 0) { $remoteList -join ', ' } else { '(none)' })")
[void]$sb.AppendLine("Changed files: $($allFiles.Count)")
[void]$sb.AppendLine("")
[void]$sb.AppendLine("=== PLAN.md (build contract) ===")
[void]$sb.AppendLine($planText)
[void]$sb.AppendLine("")
[void]$sb.AppendLine("=== CHANGED FILES ===")
if ($allFiles.Count -eq 0) {
    [void]$sb.AppendLine("(none)")
} else {
    foreach ($f in $allFiles) { [void]$sb.AppendLine("- $f") }
}
[void]$sb.AppendLine("")
[void]$sb.AppendLine("=== DIFF (tracked changes plus untracked text files) ===")
if ($hasHead) {
    $trackedDiff = (& git diff HEAD -- 2>$null) -join "`n"
    if ($LASTEXITCODE -ne 0) { Fail "git diff HEAD failed - cannot build the verifier packet." }
    if ($trackedDiff -ne "") {
        [void]$sb.AppendLine($trackedDiff)
    } else {
        [void]$sb.AppendLine("(no tracked changes)")
    }
} else {
    [void]$sb.AppendLine("(no HEAD commit; untracked files below are the change set)")
}
foreach ($f in $untracked) {
    if (-not (Test-Path -LiteralPath $f -PathType Leaf)) { continue }
    Add-UntrackedFileDiff $sb $f
}
[void]$sb.AppendLine("=== END PACKET ===")
[void]$sb.AppendLine("")
[void]$sb.AppendLine("Return only findings and the final 'Decision: APPROVE' or 'Decision: BLOCK' line.")
[void]$sb.AppendLine("Do not repeat suspected secret values; cite file:line and type only.")

$prompt = $sb.ToString()
if ($prompt.Length -gt $MaxPacketChars) {
    Fail "Verifier packet is $($prompt.Length) chars, above the $MaxPacketChars fail-closed cap. Split the change set or review manually."
}

# 3. Snapshot, call the tool-less verifier, snapshot again -------------------
$before = Get-StatusSnapshot
$packetFile = $null
$raw = @()
$code = 0
try {
    if ($prompt.Length -gt $InlineLimit) {
        $packetFile = Join-Path ([System.IO.Path]::GetTempPath()) ("verifier-packet-" + [guid]::NewGuid().ToString("N") + ".txt")
        [System.IO.File]::WriteAllText($packetFile, $prompt, (New-Object System.Text.UTF8Encoding($false)))
        $runArgs = @(
            "run", "--agent", "verifier", "--model", $Model,
            "--file", $packetFile,
            "Review the attached verifier packet. Return only findings and the final Decision line."
        )
        Write-Host "--- Verifier Run ---"
        Write-Host "MODEL:  $Model"
        Write-Host "PACKET: $($prompt.Length) chars (attached with --file)"
        $raw = & opencode @runArgs 2>&1
        $code = $LASTEXITCODE
    } else {
        $runArgs = @("run", "--agent", "verifier", "--model", $Model, $prompt)
        Write-Host "--- Verifier Run ---"
        Write-Host "MODEL:  $Model"
        Write-Host "PACKET: $($prompt.Length) chars (inline)"
        $raw = & opencode @runArgs 2>&1
        $code = $LASTEXITCODE
    }
} finally {
    if ($packetFile -and (Test-Path -LiteralPath $packetFile)) {
        Remove-Item -LiteralPath $packetFile -Force -ErrorAction SilentlyContinue
    }
}

$output = (@($raw) | ForEach-Object { [string]$_ }) -join "`n"
Write-Host $output

$after = Get-StatusSnapshot
if ($after -ne $before) {
    Write-Host "--- Working Tree Diff (before vs after) ---"
    Fail "The verifier run changed the working tree. The tool-less verifier must be read-only; treat this as a contract violation." 2
}

if ($code -ne 0) {
    Fail "opencode run failed (exit $code); the output above is not a valid review." 2
}

# 4. Require a final decision line ------------------------------------------
$decision = $null
foreach ($line in ($output -split "`r?`n")) {
    if ($line -match '^\s*Decision:\s*(APPROVE|BLOCK)([^A-Za-z]|$)') {
        $decision = $Matches[1].ToUpperInvariant()
    }
}
if (-not $decision) {
    Fail "Verifier output has no final 'Decision: APPROVE|BLOCK' line - fail-closed." 2
}

if ($decision -eq "BLOCK") {
    Write-Host "RESULT: BLOCK"
    exit 1
}
Write-Host "RESULT: APPROVE"
exit 0
