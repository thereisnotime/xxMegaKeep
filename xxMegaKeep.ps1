# PowerShell script equivalent to the provided Bash script

# Configuration
$SCRIPT_VERSION = "1.3"
$SCRIPT_NAME = "xxMegaKeep"
if (Test-Path .env) {
    Get-Content .env | ForEach-Object {
        if ($_ -notmatch '^#.*') {
            $key, $value = $_ -split '=', 2
            Set-Variable -Name $key -Value $value
        }
    }
}
$ACCOUNTS_FILE = if ($env:ACCOUNTS_FILE) { $env:ACCOUNTS_FILE } else { '.\.accounts' }

# Helpers
function Log {
    param(
        [string]$Message,
        [string]$Level
    )
    $timestamp = Get-Date -Format "dd.MM.yyyy-HH:mm:ss-zz"
    switch ($Level.ToLower()) {
        "info" { Write-Host "[INFO][$SCRIPT_NAME $SCRIPT_VERSION][$timestamp]: $Message" -ForegroundColor White }
        "warn" { Write-Host "[WARN][$SCRIPT_NAME $SCRIPT_VERSION][$timestamp]: $Message" -ForegroundColor Yellow }
        "err"  { Write-Host "[ERR][$SCRIPT_NAME $SCRIPT_VERSION][$timestamp]: $Message" -ForegroundColor Red }
        default { Write-Host "[UNKNOWN][$SCRIPT_NAME $SCRIPT_VERSION][$timestamp]: $Message" -ForegroundColor Blue }
    }
}

function Failure {
    param(
        [string]$Message,
        [int]$ExitStatus
    )
    Log "Error: $Message with status $ExitStatus" "err"
    exit $ExitStatus
}

# Function
function CheckIfCommandExists {
    param(
        [string]$Command
    )
    $path = Get-Command $Command -ErrorAction SilentlyContinue
    if (-not $path) {
        Log "Command '$Command' not found. Aborting." "err"
        exit 1
    }
}

function KeepAccounts {
    param (
        [string]$AccountsFile
    )
    $localLocation = ".\xxMegaKeep.txt"
    $remoteLocation = "/Root/xxMegaKeep.txt"
    $failedAccounts = ""
    $totalSpace = 0
    $totalUsed = 0
    $totalFree = 0
    $accounts = @()
    Get-Content $AccountsFile | ForEach-Object {
        $label, $number = $_ -split ' ', 2
        if ($label.Length -ge 3 -and $number.Length -ge 3) {
            $accounts += [PSCustomObject]@{ Label = $label; Number = $number }
        }
    }

    $count = 0
    $totalCount = $accounts.Count
    Log "Loaded $($accounts.Count) accounts from '$AccountsFile'" "info"

    foreach ($account in $accounts) {
        $loginResult = megatools.exe ls --username $account.Label --password $account.Number /Root/ 2>&1 | Out-Null
        if ($?) {
            Log "Logging in $($account.Label) successful" "info"
            $date = Get-Date -Format "dddd dd.MM.yyyy HH:mm:ss zz"
            $total = megatools.exe df --total --gb --username $account.Label --password $account.Number
            $used = megatools.exe df --gb --used --username $account.Label --password $account.Number
            $free = megatools.exe df --gb --free --username $account.Label --password $account.Number
            $stats = "Total $total GiB | Used $used GiB | Free $free GiB"
            $totalSpace += $total
            $totalUsed += $used
            $totalFree += $free
            $stats = $stats -replace "`n", " "
            Set-Content $localLocation @"
===xxMegaKeep
Ran on: $date
# Account: $($account.Label)
Stats: $stats
"@

            if (megatools.exe test --username $account.Label --password $account.Number -f $remoteLocation > $null) {
                megatools.exe rm --username $account.Label --password $account.Number --no-ask-password $remoteLocation > $null
            }

            $uploadResult = megatools.exe put --username $account.Label --password $account.Number --disable-previews --no-progress --path $remoteLocation $localLocation 2>&1 | Out-Null
            if (!$?) {
                Log "Failed uploading to $($account.Label) | Disk: $stats" "err"
                $failedAccounts += " $($account.Label)"
                $count--
            } else {
                Log "Success with $($account.Label) | Disk: $stats" "info"
            }
            Remove-Item $localLocation -Force
            
        } else {
            Log "Failed login with $($account.Label)" "err"
            $failedAccounts += " $($account.Label)"
            $count--
        }
    }
    $statsSum = "Total $totalSpace GiB | Used $totalUsed GiB | Free $totalFree GiB"
    if ($count -lt $totalCount) {
        Log "Finished $count/$totalCount accounts (except:$failedAccounts) | Disk: $statsSum" "info"
    } else {
        Log "Finished $totalCount accounts | Disk $statsSum" "info"
    }
}


# Main
$ErrorActionPreference = 'Stop'
trap {
    Failure $_.Exception.Message $_.Exception.HResult
}

$Start = Get-Date
CheckIfCommandExists "megatools.exe"
KeepAccounts $ACCOUNTS_FILE

# Clean Exit
$End = Get-Date
$Runtime = ($End - $Start).TotalSeconds
Log "Done in $Runtime seconds. Performing clean exit" "info"
exit 0
