# Secure FTP Backup and Restore Scripts

## Overview

This project provides robust, secure scripts for automated server data backups using FTP with encryption and retention management.

## Features

- **Secure Backup**:
  - Encrypted database and file backups
  - Supports multiple directories
  - Secure FTP transfer

- **Automated Management**:
  - Automatic backup scheduling
  - Retention of last 8 backups
  - Old backups automatically pruned

- **Easy Configuration**:
  - Single `.env` file for all sensitive configurations
  - Strict file permission recommendations

## Prerequisites

- `bash`
- `lftp`
- `gpg`
- `mysql` (for database backups)

## Setup and Installation

### 1. Environment Configuration

Create a `.env` file with the following structure:

```plaintext
# FTP Credentials
FTP_HOST="your-ftp-host"
FTP_USER="your-ftp-username"
FTP_PASS="your-ftp-password"

# Backup Configuration
BACKUP_DIRS=("/path/to/directory1" "/path/to/directory2")
BACKUP_RETENTION_COUNT=8

# Database Configuration
DB_HOST="localhost"
DB_USER="root"
DB_PASS="your-root-password"
DB_NAME="your-database-name"

# Security
ENCRYPTION_PASSPHRASE="strong-unique-passphrase"
```

### 2. Secure Permissions

```bash
# Secure .env file
chmod 600 .env

# Make scripts executable
chmod 700 backup_to_ftp.sh restore_from_ftp.sh
```

## Usage

### Manual Backup

```bash
./backup_to_ftp.sh
```

### Manual Restore

```bash
./restore_from_ftp.sh
```

### Automated Backups with Cron

Edit crontab to schedule daily backups:

```bash
crontab -e
```

Add the following line (adjusts time as needed):
```
0 2 * * * /path/to/backup_to_ftp.sh
```

## Security Recommendations

- Use strong, unique passphrases
- Regularly rotate encryption keys
- Monitor backup logs
- Test restore procedures periodically
- Store `.env` file securely
- Use firewall and network restrictions

## Troubleshooting

- Check system logs for detailed error information
- Verify FTP and database credentials
- Ensure all dependencies are installed
- Confirm network connectivity

## Contributing

Contributions welcome! Please submit pull requests or open issues for improvements.