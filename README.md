# xxMegaKeep

Script that prevents your MEGA accounts from expiring by logging and doing file operations.

## Concept

1. The script gets all accounts from a file.
2. Tries to login and if successfull - uploads/replaces a file called xxMegaKeep.txt which contains the last date when this action had succeeded.

## Requirements

1. Bash
2. [Megatools](https://megous.com/git/megatools)

## Setup Accounts

Create a file (example: .accounts) and store the accounts you need checked in the following format:

```bash
acc1 pass1
acc2 pass2
acc3 pass3

```

## Usage

1. Copy the .env.example to .env and change the variables accordingly.
2. Copy the .accounts.example to .accounts and add your MEGA accounts.
3. Start the script

```bash
bash xxMegaKeep.sh
```

or

```bash
./xxMegaKeep.sh
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

## Todos

- [ ] Fix the uploading for the PowerShell version.
- [ ] Create a script to set everything up on a fresh device - Windows/Linux/Mac.
- [ ] Add example setup snippet for a cronjob and for a sheduled task.
