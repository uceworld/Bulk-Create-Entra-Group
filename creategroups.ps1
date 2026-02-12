$ErrorActionPreference = "Stop"

# ---------------- IMPORT CSV WITH ROW NUMBERS ----------------
$RawGroups = Import-Csv ".\groups.csv"

$Groups = for ($i = 0; $i -lt $RawGroups.Count; $i++) {
    $RawGroups[$i] |
        Add-Member -NotePropertyName RowNumber -NotePropertyValue ($i + 2) -PassThru
}

# ---------------- LOGGING ----------------
function Write-Info($m) { Write-Host "[INFO] $m" -ForegroundColor Cyan }
function Write-Warn($m) { Write-Host "[WARN] $m" -ForegroundColor Yellow }
function Write-Ok($m)   { Write-Host "[OK]   $m" -ForegroundColor Green }
function Write-Fail($m) { Write-Host "[FAIL] $m" -ForegroundColor Red }

# ---------------- SUMMARY ----------------
$Summary = @{
    Total         = 0
    Created       = 0
    SkippedExists = 0
    Failed        = 0
    FailReasons   = @{}
    FailedRows    = @()
}

function Add-FailureReason($Reason) {
    if (-not $Summary.FailReasons.ContainsKey($Reason)) {
        $Summary.FailReasons[$Reason] = 0
    }
    $Summary.FailReasons[$Reason]++
}

function Add-FailedRow {
    param (
        [int]$Row,
        [string]$DisplayName,
        [string]$Reason,
        [string]$Columns
    )

    $Summary.FailedRows += [PSCustomObject]@{
        Row         = $Row
        DisplayName = $DisplayName
        Reason      = $Reason
        Columns     = $Columns
    }
}

# ---------------- PREFETCH EXISTING GROUPS ----------------
Write-Info "Fetching existing group names from tenant..."

$ExistingGroupLookup = @{}

Get-MgGroup -All -Property DisplayName | ForEach-Object {
    if ($_.DisplayName) {
        $ExistingGroupLookup[$_.DisplayName] = $true
    }
}

# ---------------- PROCESS CSV ----------------
foreach ($Group in $Groups) {

    $Summary.Total++

    $DisplayName    = $Group.DisplayName
    $MailNickname   = $Group.MailNickname
    $Description    = $Group.Description
    $RoleAssignable = $Group.RoleAssignable
    $MembershipType = $Group.MembershipType
    $MembershipRule = $Group.MembershipRule
    $RowNumber      = $Group.RowNumber

    Write-Info "Processing group '$DisplayName'"

    # ---------- REQUIRED FIELD VALIDATION ----------
    $MissingCols = @()

    if ([string]::IsNullOrWhiteSpace($DisplayName)) { $MissingCols += "DisplayName" }
    if ([string]::IsNullOrWhiteSpace($MailNickname)) { $MissingCols += "MailNickname" }

    if ($MissingCols.Count -gt 0) {
        Write-Fail "Missing required fields."
        $Summary.Failed++
        Add-FailureReason "Missing required fields"
        Add-FailedRow -Row $RowNumber -DisplayName $DisplayName -Reason "Missing required fields" -Columns ($MissingCols -join ", ")
        continue
    }

    # ---------- DUPLICATE NAME CHECK ----------
    if ($ExistingGroupLookup.ContainsKey($DisplayName)) {
        Write-Warn "Group name '$DisplayName' already exists. Skipping."
        $Summary.SkippedExists++
        continue
    }

    # ---------- ROLE ASSIGNMENT ENFORCEMENT ----------
    $IsAssignableToRole = $RoleAssignable -eq "Yes"

    if ($IsAssignableToRole -and $MembershipType -ne "Assigned") {
        Write-Warn "Role-assignable group cannot be dynamic. MembershipType forced to 'Assigned'."
        $MembershipType = "Assigned"
    }

    # ---------- DYNAMIC MEMBERSHIP VALIDATION ----------
    if ($MembershipType -like "Dynamic*" -and
        [string]::IsNullOrWhiteSpace($MembershipRule)) {

        Write-Fail "Dynamic membership selected but MembershipRule is empty."
        $Summary.Failed++
        Add-FailureReason "Dynamic membership missing rule"
        Add-FailedRow -Row $RowNumber -DisplayName $DisplayName -Reason "Dynamic membership missing rule" -Columns "MembershipRule"
        continue
    }

    # ---------- BUILD GROUP PAYLOAD ----------
    $GroupParams = @{
        DisplayName        = $DisplayName
        MailEnabled        = $false
        MailNickname       = $MailNickname
        SecurityEnabled    = $true
        IsAssignableToRole = $IsAssignableToRole
        ErrorAction        = "Stop"
    }

    if (-not [string]::IsNullOrWhiteSpace($Description)) {
        $GroupParams.Description = $Description
    }

    if ($MembershipType -eq "DynamicUser" -or $MembershipType -eq "DynamicDevice") {
        $GroupParams.GroupTypes = @("DynamicMembership")
        $GroupParams.MembershipRule = $MembershipRule
        $GroupParams.MembershipRuleProcessingState = "On"
    }

    # ---------- CREATE GROUP ----------
    try {
        $Result = New-MgGroup @GroupParams

        if (-not $Result.Id) {
            throw "Graph did not return a group Id."
        }

        Write-Ok "Created '$DisplayName' (Id: $($Result.Id))"
        $ExistingGroupLookup[$DisplayName] = $true
        $Summary.Created++
    }
    catch {
        $Summary.Failed++
        Add-FailureReason "Graph or runtime error"

        $ErrorMessage =
            if ($_.ErrorDetails.Message) { $_.ErrorDetails.Message }
            elseif ($_.Exception.Message) { $_.Exception.Message }
            else { "Unknown error occurred." }

        Write-Fail "Failed to create '$DisplayName'"
        Write-Host "       Reason: $ErrorMessage" -ForegroundColor DarkRed

        Add-FailedRow -Row $RowNumber -DisplayName $DisplayName -Reason "Graph or runtime error" -Columns "Unknown"
        continue
    }
}

# ---------------- SUMMARY OUTPUT ----------------
Write-Host ""
Write-Host "========== EXECUTION SUMMARY ==========" -ForegroundColor White
Write-Host "Total groups processed : $($Summary.Total)"
Write-Host "Groups created         : $($Summary.Created)" -ForegroundColor Green
Write-Host "Skipped (name exists)  : $($Summary.SkippedExists)" -ForegroundColor Yellow
Write-Host "Failed                 : $($Summary.Failed)" -ForegroundColor Red

if ($Summary.FailReasons.Count -gt 0) {
    Write-Host ""
    Write-Host "Failure breakdown:" -ForegroundColor White
    foreach ($Key in $Summary.FailReasons.Keys) {
        Write-Host " - $Key : $($Summary.FailReasons[$Key])"
    }
}

if ($Summary.FailedRows.Count -gt 0) {
    Write-Host ""
    Write-Host "Failed row details:" -ForegroundColor White
    $Summary.FailedRows |
        Sort-Object Row |
        Format-Table Row, DisplayName, Reason, Columns -AutoSize
}

Write-Host "======================================"
