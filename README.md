# xxMegaKeep

Professional script that prevents your MEGA accounts from expiring by performing periodic file operations.

## Version

**Current Version**: 2.0

## Features

- ✅ Automatic login and keep-alive for multiple MEGA accounts
- ✅ Comprehensive error handling and validation
- ✅ Retry logic for network operations (up to 3 attempts)
- ✅ Storage statistics tracking (Total/Used/Free space)
- ✅ Clean logging with color-coded messages
- ✅ Pre-flight checks for required dependencies
- ✅ Graceful cleanup on exit
- ✅ Support for both Bash and PowerShell environments

## Concept

1. The script loads all accounts from a configuration file
2. Validates account credentials and checks for required dependencies
3. Attempts to login to each account with retry logic
4. Uploads/replaces a timestamp file (`xxMegaKeep.txt`) with activity information
5. Tracks and displays storage statistics for all accounts
6. Provides comprehensive summary of successful and failed operations

## Requirements

### For Linux/macOS (Bash)
- Bash 4.0+
- [Megatools](https://megous.com/git/megatools)
- `bc` (for calculations)

### For Windows (PowerShell)
- PowerShell 5.1+
- [Megatools for Windows](https://megous.com/git/megatools) (megatools.exe)

## Installation

### Install Megatools

**Linux (Debian/Ubuntu):**
```bash
sudo apt-get install megatools
```

**Linux (Fedora):**
```bash
sudo dnf install megatools
```

**macOS:**
```bash
brew install megatools
```

**Windows:**
Download from the [official website](https://megous.com/git/megatools) and add to PATH.

## Setup Accounts

Create a file named `.accounts` (or any name you prefer) and add your MEGA accounts in the following format:

```
account1@example.com password1
account2@example.com password2
account3@example.com password3
```

**Important:**
- One account per line
- Separate email and password with a space
- Lines starting with `#` are treated as comments
- Empty lines are ignored
- Minimum 3 characters required for both account and password

## Configuration (Optional)

You can create a `.env` file to customize the accounts file location:

```bash
ACCOUNTS_FILE=./my-accounts.txt
```

## Usage

### Linux/macOS (Bash)

Make the script executable:
```bash
chmod +x xxMegaKeep.sh
```

Run the script:
```bash
./xxMegaKeep.sh
```

### Windows (PowerShell)

Run the script:
```powershell
.\xxMegaKeep.ps1
```

Or with execution policy bypass:
```powershell
PowerShell -ExecutionPolicy Bypass -File .\xxMegaKeep.ps1
```

## Systemd Setup

`~/.config/systemd/user/xxmegakeep.service`:

```ini
[Unit]
Description=Run xxMegaKeep script

[Service]
Type=oneshot
WorkingDirectory=%h/Private/Projects/personal/xxMegaKeep
ExecStart=/usr/bin/bash xxMegaKeep.sh
```

`~/.config/systemd/user/xxmegakeep.timer`:

```ini
[Unit]
Description=Run xxMegaKeep every week

[Timer]
OnCalendar=weekly       # runs once per week on the same weekday/time the timer is first started
Persistent=true         # catch-up run if the system was off

[Install]
WantedBy=timers.target
```

Enable and start:

```bash
systemctl --user daemon-reload
systemctl --user enable --now xxmegakeep.timer
```

Check status/logs:

```bash
# Next run & last run
systemctl --user list-timers xxmegakeep.timer

# Detailed unit status
systemctl --user status xxmegakeep.timer
systemctl --user status xxmegakeep.service

# Reverse-chronological logs for the service
journalctl --user -u xxmegakeep.service -r
```

Manual run:

```bash
systemctl --user start xxmegakeep.service
```

## Output Example

```
========================================
[INFO][xxMegaKeep v2.0][2025-10-27 14:30:00 UTC]: Starting xxMegaKeep v2.0
========================================

[INFO][xxMegaKeep v2.0][2025-10-27 14:30:00 UTC]: Performing pre-flight checks...
[SUCCESS][xxMegaKeep v2.0][2025-10-27 14:30:00 UTC]: Pre-flight checks passed

[INFO][xxMegaKeep v2.0][2025-10-27 14:30:01 UTC]: Loaded 3 account(s) from './.accounts'

[INFO][xxMegaKeep v2.0][2025-10-27 14:30:02 UTC]: Login successful for account1@example.com
[SUCCESS][xxMegaKeep v2.0][2025-10-27 14:30:05 UTC]: Successfully processed account1@example.com | Storage: Total 50 GiB | Used 12.5 GiB | Free 37.5 GiB

[INFO][xxMegaKeep v2.0][2025-10-27 14:30:06 UTC]: Login successful for account2@example.com
[SUCCESS][xxMegaKeep v2.0][2025-10-27 14:30:09 UTC]: Successfully processed account2@example.com | Storage: Total 50 GiB | Used 8.2 GiB | Free 41.8 GiB

========================================
[INFO][xxMegaKeep v2.0][2025-10-27 14:30:10 UTC]: Processing Complete
========================================
[SUCCESS][xxMegaKeep v2.0][2025-10-27 14:30:10 UTC]: All 2 accounts processed successfully | Storage: Total 100 GiB | Used 20.7 GiB | Free 79.3 GiB

========================================
[SUCCESS][xxMegaKeep v2.0][2025-10-27 14:30:10 UTC]: Completed in 9.45 seconds
========================================
```

## What's New in Version 2.0

### Major Improvements

**Code Quality:**
- Complete rewrite with professional coding standards
- Removed shellcheck warnings
- Proper use of `readonly` for constants
- Consistent naming conventions
- Comprehensive inline documentation

**Error Handling:**
- Proper error trapping and cleanup
- Graceful exit on failures
- Pre-flight checks for dependencies
- Input validation for accounts and passwords

**Reliability:**
- Retry logic for network operations (up to 3 attempts with 5s delay)
- Better handling of edge cases
- Fixed counting logic bugs in PowerShell version
- Proper file cleanup on exit

**User Experience:**
- Color-coded log messages (INFO, WARN, ERROR, SUCCESS)
- Better formatted output with separators
- Detailed storage statistics
- Clear summary of operations
- Email format validation

**PowerShell Specific:**
- Fixed critical bug where success counter was never incremented
- Added proper parameter validation
- PowerShell best practices (approved verbs, comment-based help)
- Proper type declarations

## Future Enhancements

- [ ] Add syslog logging support
- [ ] Implement parallel processing for multiple accounts
- [ ] Add notification hooks (webhooks/Telegram/email)
- [ ] Create automated setup script for fresh installations
- [ ] Add support for configuration profiles
- [ ] Implement rate limiting/throttling options
