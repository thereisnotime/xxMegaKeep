<#
.SYNOPSIS
    xxMegaKeep - MEGA Account Keeper

.DESCRIPTION
    Prevents MEGA accounts from expiring by performing periodic file operations.
    This script logs into MEGA accounts and uploads a timestamp file to keep them active.

.NOTES
    Version: 2.0
    Author: xxMegaKeep
    Requires: megatools.exe
#>

[CmdletBinding()]
param()

#Requires -Version 5.1

###########################
# Script Constants
###########################
$Script:SCRIPT_VERSION = "2.0"
$Script:SCRIPT_NAME = "xxMegaKeep"
$Script:DEFAULT_ACCOUNTS_FILE = ".\.accounts"
$Script:TEMP_FILE_NAME = "xxMegaKeep.txt"
$Script:REMOTE_FILE_PATH = "/Root/xxMegaKeep.txt"
$Script:MAX_RETRIES = 3
$Script:RETRY_DELAY = 5

# Set strict mode
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

###########################
# Configuration
###########################
function Initialize-Configuration {
    <#
    .SYNOPSIS
        Loads configuration from .env file if it exists
    #>
    
    $envFile = ".env"
    if (Test-Path $envFile) {
        Get-Content $envFile | ForEach-Object {
            $line = $_.Trim()
            
            # Skip comments and empty lines
            if ($line -match '^#' -or [string]::IsNullOrWhiteSpace($line)) {
                return
            }
            
            # Parse key-value pairs
            if ($line -match '^([^=]+)=(.*)$') {
                $key = $Matches[1].Trim()
                $value = $Matches[2].Trim()
                Set-Variable -Name $key -Value $value -Scope Script
            }
        }
    }
    
    # Set accounts file location
    if ($env:ACCOUNTS_FILE) {
        $Script:ACCOUNTS_FILE = $env:ACCOUNTS_FILE
    } else {
        $Script:ACCOUNTS_FILE = $Script:DEFAULT_ACCOUNTS_FILE
    }
}

###########################
# Logging Functions
###########################
function Write-Log {
    <#
    .SYNOPSIS
        Writes a formatted log message
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,
        
        [Parameter(Mandatory = $false)]
        [ValidateSet('INFO', 'WARN', 'ERROR', 'SUCCESS')]
        [string]$Level = 'INFO'
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss K"
    
    $color = switch ($Level) {
        'INFO'    { 'White' }
        'WARN'    { 'Yellow' }
        'ERROR'   { 'Red' }
        'SUCCESS' { 'Green' }
        default   { 'Cyan' }
    }
    
    $logMessage = "[$Level][$Script:SCRIPT_NAME v$Script:SCRIPT_VERSION][$timestamp]: $Message"
    Write-Host $logMessage -ForegroundColor $color
}

function Write-LogInfo {
    param([string]$Message)
    Write-Log -Message $Message -Level 'INFO'
}

function Write-LogWarn {
    param([string]$Message)
    Write-Log -Message $Message -Level 'WARN'
}

function Write-LogError {
    param([string]$Message)
    Write-Log -Message $Message -Level 'ERROR'
}

function Write-LogSuccess {
    param([string]$Message)
    Write-Log -Message $Message -Level 'SUCCESS'
}

###########################
# Error Handling
###########################
function Invoke-Cleanup {
    <#
    .SYNOPSIS
        Cleanup function to remove temporary files
    #>
    param(
        [int]$ExitCode = 0
    )
    
    # Remove temporary file if it exists
    if (Test-Path $Script:TEMP_FILE_NAME) {
        Remove-Item $Script:TEMP_FILE_NAME -Force -ErrorAction SilentlyContinue
    }
    
    if ($ExitCode -ne 0) {
        Write-LogError "Script exited with error code: $ExitCode"
    }
}

###########################
# Validation Functions
###########################
function Test-CommandExists {
    <#
    .SYNOPSIS
        Checks if a command exists in the system
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$Command
    )
    
    $commandInfo = Get-Command $Command -ErrorAction SilentlyContinue
    if (-not $commandInfo) {
        Write-LogError "Required command '$Command' not found. Please install it first."
        Invoke-Cleanup -ExitCode 1
        exit 1
    }
    
    return $true
}

function Test-FileExists {
    <#
    .SYNOPSIS
        Checks if a file exists
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$FilePath
    )
    
    if (-not (Test-Path $FilePath)) {
        Write-LogError "Required file '$FilePath' not found."
        Invoke-Cleanup -ExitCode 1
        exit 1
    }
    
    return $true
}

function Test-AccountCredentials {
    <#
    .SYNOPSIS
        Validates account credentials
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$Account,
        
        [Parameter(Mandatory = $true)]
        [string]$Password
    )
    
    if ($Account.Length -lt 3) {
        Write-LogWarn "Account name '$Account' is too short (minimum 3 characters). Skipping."
        return $false
    }
    
    if ($Password.Length -lt 3) {
        Write-LogWarn "Password for '$Account' is too short (minimum 3 characters). Skipping."
        return $false
    }
    
    # Basic email format validation
    if ($Account -notmatch '^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$') {
        Write-LogWarn "Account '$Account' doesn't appear to be a valid email format. Proceeding anyway."
    }
    
    return $true
}

###########################
# MEGA Operations
###########################
function Invoke-MegaCommandWithRetry {
    <#
    .SYNOPSIS
        Executes a MEGA command with retry logic
    #>
    param(
        [Parameter(Mandatory = $true)]
        [scriptblock]$Command,
        
        [Parameter(Mandatory = $true)]
        [string]$OperationDescription,
        
        [Parameter(Mandatory = $false)]
        [int]$MaxAttempts = $Script:MAX_RETRIES
    )
    
    $attempt = 1
    
    while ($attempt -le $MaxAttempts) {
        try {
            $result = & $Command
            if ($LASTEXITCODE -eq 0 -or $?) {
                return $result
            }
        }
        catch {
            # Command failed
        }
        
        if ($attempt -lt $MaxAttempts) {
            Write-LogWarn "$OperationDescription - Attempt $attempt/$MaxAttempts failed. Retrying in $($Script:RETRY_DELAY)s..."
            Start-Sleep -Seconds $Script:RETRY_DELAY
        }
        
        $attempt++
    }
    
    return $null
}

function Test-MegaLogin {
    <#
    .SYNOPSIS
        Tests login credentials for a MEGA account
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$Account,
        
        [Parameter(Mandatory = $true)]
        [string]$Password
    )
    
    $result = Invoke-MegaCommandWithRetry -MaxAttempts 2 -OperationDescription "Login check for $Account" -Command {
        megatools.exe ls --username $Account --password $Password /Root/ 2>&1 | Out-Null
        return $?
    }
    
    return ($null -ne $result)
}

function Get-MegaStorageInfo {
    <#
    .SYNOPSIS
        Retrieves storage information from MEGA account
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$Account,
        
        [Parameter(Mandatory = $true)]
        [string]$Password,
        
        [Parameter(Mandatory = $true)]
        [ValidateSet('Total', 'Used', 'Free')]
        [string]$InfoType
    )
    
    $flags = switch ($InfoType) {
        'Total' { '--total --gb' }
        'Used'  { '--used --gb' }
        'Free'  { '--free --gb' }
    }
    
    try {
        $result = Invoke-Expression "megatools.exe df $flags --username `"$Account`" --password `"$Password`" 2>&1"
        if ($LASTEXITCODE -eq 0) {
            return [double]($result -replace '[^0-9.]', '')
        }
    }
    catch {
        Write-LogWarn "Failed to get storage info ($InfoType) for $Account"
    }
    
    return 0
}

function Invoke-MegaUploadFile {
    <#
    .SYNOPSIS
        Uploads a file to MEGA account
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$Account,
        
        [Parameter(Mandatory = $true)]
        [string]$Password,
        
        [Parameter(Mandatory = $true)]
        [string]$LocalFile,
        
        [Parameter(Mandatory = $true)]
        [string]$RemotePath
    )
    
    # Check if file exists remotely and remove it
    try {
        $testResult = megatools.exe test --username $Account --password $Password -f $RemotePath 2>&1
        if ($LASTEXITCODE -eq 0) {
            megatools.exe rm --username $Account --password $Password --no-ask-password $RemotePath 2>&1 | Out-Null
        }
    }
    catch {
        # File doesn't exist, that's fine
    }
    
    # Upload the file
    $uploadResult = Invoke-MegaCommandWithRetry -OperationDescription "Upload to $Account" -Command {
        megatools.exe put --username $Account --password $Password --disable-previews --no-progress --path $RemotePath $LocalFile 2>&1 | Out-Null
        return $?
    }
    
    return ($null -ne $uploadResult)
}

###########################
# Account Processing
###########################
function New-TimestampFile {
    <#
    .SYNOPSIS
        Creates a timestamp file with account information
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$Account,
        
        [Parameter(Mandatory = $true)]
        [string]$Stats,
        
        [Parameter(Mandatory = $true)]
        [string]$OutputFile
    )
    
    $timestamp = Get-Date -Format "dddd, MMMM dd, yyyy 'at' HH:mm:ss K"
    
    $content = @"
===xxMegaKeep Activity Log===
Timestamp: $timestamp
Account: $Account
Storage Stats: $Stats
Status: Active
"@
    
    Set-Content -Path $OutputFile -Value $content -Force
}

function Invoke-ProcessAccount {
    <#
    .SYNOPSIS
        Processes a single MEGA account
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$Account,
        
        [Parameter(Mandatory = $true)]
        [string]$Password
    )
    
    Write-LogInfo "Processing account: $Account"
    
    # Test login
    if (-not (Test-MegaLogin -Account $Account -Password $Password)) {
        Write-LogError "Failed to login with $Account"
        return $null
    }
    
    Write-LogSuccess "Login successful for $Account"
    
    # Get storage information
    $totalSpace = Get-MegaStorageInfo -Account $Account -Password $Password -InfoType 'Total'
    $usedSpace = Get-MegaStorageInfo -Account $Account -Password $Password -InfoType 'Used'
    $freeSpace = Get-MegaStorageInfo -Account $Account -Password $Password -InfoType 'Free'
    
    $stats = "Total $totalSpace GiB | Used $usedSpace GiB | Free $freeSpace GiB"
    
    # Create timestamp file
    New-TimestampFile -Account $Account -Stats $stats -OutputFile $Script:TEMP_FILE_NAME
    
    # Upload file
    if (-not (Invoke-MegaUploadFile -Account $Account -Password $Password -LocalFile $Script:TEMP_FILE_NAME -RemotePath $Script:REMOTE_FILE_PATH)) {
        Write-LogError "Failed to upload file for $Account | Storage: $stats"
        Remove-Item $Script:TEMP_FILE_NAME -Force -ErrorAction SilentlyContinue
        return $null
    }
    
    Write-LogSuccess "Successfully processed $Account | Storage: $stats"
    Remove-Item $Script:TEMP_FILE_NAME -Force -ErrorAction SilentlyContinue
    
    # Return storage stats
    return @{
        TotalSpace = $totalSpace
        UsedSpace  = $usedSpace
        FreeSpace  = $freeSpace
        Account    = $Account
    }
}

function Import-Accounts {
    <#
    .SYNOPSIS
        Loads accounts from the accounts file
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$AccountsFile
    )
    
    $accounts = @()
    $lineNumber = 0
    
    Get-Content $AccountsFile | ForEach-Object {
        $lineNumber++
        $line = $_.Trim()
        
        # Skip empty lines and comments
        if ([string]::IsNullOrWhiteSpace($line) -or $line.StartsWith('#')) {
            return
        }
        
        # Parse account and password
        $parts = $line -split '\s+', 2
        if ($parts.Count -ge 2) {
            $account = $parts[0].Trim()
            $password = $parts[1].Trim()
            
            # Validate credentials
            if (Test-AccountCredentials -Account $account -Password $password) {
                $accounts += [PSCustomObject]@{
                    Account  = $account
                    Password = $password
                }
            }
        }
        else {
            Write-LogWarn "Invalid format on line $lineNumber. Expected: 'account password'"
        }
    }
    
    if ($accounts.Count -eq 0) {
        Write-LogError "No valid accounts found in '$AccountsFile'"
        Invoke-Cleanup -ExitCode 1
        exit 1
    }
    
    return $accounts
}

function Invoke-ProcessAllAccounts {
    <#
    .SYNOPSIS
        Processes all MEGA accounts from the accounts file
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$AccountsFile
    )
    
    # Load accounts
    $accounts = Import-Accounts -AccountsFile $AccountsFile
    $totalAccounts = $accounts.Count
    
    Write-LogInfo "Loaded $totalAccounts account(s) from '$AccountsFile'"
    Write-Host ""
    
    # Initialize counters
    $successfulCount = 0
    $failedAccounts = @()
    $totalSpace = 0
    $usedSpace = 0
    $freeSpace = 0
    
    # Process each account
    $currentAccount = 0
    foreach ($accountInfo in $accounts) {
        $currentAccount++
        
        Write-Host "----------------------------------------"
        Write-LogInfo "Account $currentAccount/$totalAccounts`: $($accountInfo.Account)"
        
        $result = Invoke-ProcessAccount -Account $accountInfo.Account -Password $accountInfo.Password
        
        if ($null -ne $result) {
            $successfulCount++
            $totalSpace += $result.TotalSpace
            $usedSpace += $result.UsedSpace
            $freeSpace += $result.FreeSpace
        }
        else {
            $failedAccounts += $accountInfo.Account
        }
        
        # Add spacing between account processing
        Write-Host ""
    }
    
    # Display summary
    Show-Summary -Successful $successfulCount -Total $totalAccounts `
                 -TotalSpace $totalSpace -UsedSpace $usedSpace -FreeSpace $freeSpace `
                 -FailedAccounts $failedAccounts
}

function Show-Summary {
    <#
    .SYNOPSIS
        Displays processing summary
    #>
    param(
        [int]$Successful,
        [int]$Total,
        [double]$TotalSpace,
        [double]$UsedSpace,
        [double]$FreeSpace,
        [array]$FailedAccounts
    )
    
    Write-Host "========================================"
    Write-LogInfo "Processing Complete"
    Write-Host "========================================"
    
    $statsSum = "Total $TotalSpace GiB | Used $UsedSpace GiB | Free $FreeSpace GiB"
    
    if ($Successful -eq $Total) {
        Write-LogSuccess "All $Total accounts processed successfully | Storage: $statsSum"
    }
    else {
        $failedCount = $Total - $Successful
        Write-LogWarn "Processed $Successful/$Total accounts ($failedCount failed) | Storage: $statsSum"
        
        if ($FailedAccounts.Count -gt 0) {
            Write-LogWarn "Failed accounts: $($FailedAccounts -join ', ')"
        }
    }
}

###########################
# Pre-flight Checks
###########################
function Invoke-PreflightChecks {
    <#
    .SYNOPSIS
        Performs pre-flight checks before processing accounts
    #>
    
    Write-LogInfo "Performing pre-flight checks..."
    
    # Check for required commands
    Test-CommandExists -Command "megatools.exe"
    
    # Check for accounts file
    Test-FileExists -FilePath $Script:ACCOUNTS_FILE
    
    Write-LogSuccess "Pre-flight checks passed"
    Write-Host ""
}

###########################
# Main Execution
###########################
function Main {
    <#
    .SYNOPSIS
        Main execution function
    #>
    
    try {
        Write-Host "========================================"
        Write-LogInfo "Starting $Script:SCRIPT_NAME v$Script:SCRIPT_VERSION"
        Write-Host "========================================"
        Write-Host ""
        
        $startTime = Get-Date
        
        # Initialize configuration
        Initialize-Configuration
        
        # Run pre-flight checks
        Invoke-PreflightChecks
        
        # Process all accounts
        Invoke-ProcessAllAccounts -AccountsFile $Script:ACCOUNTS_FILE
        
        # Calculate runtime
        $endTime = Get-Date
        $runtime = ($endTime - $startTime).TotalSeconds
        $runtime = [math]::Round($runtime, 2)
        
        Write-Host ""
        Write-Host "========================================"
        Write-LogSuccess "Completed in $runtime seconds"
        Write-Host "========================================"
        
        Invoke-Cleanup -ExitCode 0
        exit 0
    }
    catch {
        Write-LogError "An unexpected error occurred: $_"
        Write-LogError $_.ScriptStackTrace
        Invoke-Cleanup -ExitCode 1
        exit 1
    }
}

# Execute main function
Main
