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
