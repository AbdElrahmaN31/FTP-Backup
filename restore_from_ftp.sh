#!/usr/bin/env bash

# Strict mode for better error handling
set -euo pipefail

# Load environment configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=.env
source "${SCRIPT_DIR}/.env"

# Logging function
log() {
    local level="$1"
    local message="$2"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    echo "[${level}] ${timestamp}: ${message}"

    # Optional: Log to file if LOG_DIR exists
    if [[ -d "${BACKUP_LOG_DIR}" ]]; then
        echo "[${level}] ${timestamp}: ${message}" >> "${BACKUP_LOG_DIR}/restore.log"
    fi
}

# Validate required environment variables
validate_env() {
    local required_vars=(
        "FTP_HOST" "FTP_USER" "FTP_PASS"
        "DB_USER" "DB_PASS" "DB_NAME"
        "ENCRYPTION_PASSPHRASE"
    )

    for var in "${required_vars[@]}"; do
        if [[ -z "${!var:-}" ]]; then
            log "ERROR" "Missing required environment variable: ${var}"
            exit 1
        fi
    done
}

# Fetch latest backup from FTP
# shellcheck disable=SC2120
fetch_latest_backup() {
    log "INFO" "Fetching latest backup from FTP..."
    local latest_backup

    # Get the most recent backup file
    latest_backup=$(lftp -u "${FTP_USER},${FTP_PASS}" "ftps://${FTP_HOST}" <<EOF
        find -l | sort -r | awk '{print $9}' | grep "\.gpg$" | head -n 1
        bye
EOF
    )

    if [[ -z "${latest_backup}" ]]; then
        log "ERROR" "No backup files found on FTP server"
        exit 1
    fi

    local local_encrypted_file="${BACKUP_BASE_DIR}/latest_backup.tar.gz.gpg"

    if ! lftp -u "${FTP_USER},${FTP_PASS}" "ftps://${FTP_HOST}" <<EOF
        get "${latest_backup}" -o "${local_encrypted_file}"
        bye
EOF
    then
        log "ERROR" "Failed to download backup file"
        exit 1
    fi

    echo "${local_encrypted_file}"
}

# Decrypt backup
decrypt_backup() {
    local encrypted_file="$1"
    local decrypted_file="${encrypted_file%.*}"

    log "INFO" "Decrypting backup..."
    if ! gpg --batch --yes --decrypt \
        --passphrase "${ENCRYPTION_PASSPHRASE}" \
        -o "${decrypted_file}" \
        "${encrypted_file}"; then
        log "ERROR" "Backup decryption failed"
        exit 1
    fi

    echo "${decrypted_file}"
}

# Extract backup archive
extract_backup() {
    local backup_file="$1"

    log "INFO" "Extracting backup archive..."
    if ! tar -xzf "${backup_file}" -C "${BACKUP_BASE_DIR}"; then
        log "ERROR" "Backup extraction failed"
        exit 1
    fi
}

# Restore database
restore_database() {
    local sql_file
    sql_file=$(find "${BACKUP_BASE_DIR}" -name "*.sql" -print -quit)

    if [[ -z "${sql_file}" ]]; then
        log "WARNING" "No database backup file found"
        return
    fi

    log "INFO" "Restoring database..."
    if ! mysql -h "${DB_HOST}" -u "${DB_USER}" -p"${DB_PASS}" "${DB_NAME}" < "${sql_file}"; then
        log "ERROR" "Database restore failed"
        exit 1
    fi
}

# Restore file system
restore_files() {
    log "INFO" "Restoring file system..."

    # Restore each backup directory
    for dir in "${BACKUP_DIRS[@]}"; do
        local backup_dir
        backup_dir=$(find "${BACKUP_BASE_DIR}" -type d -name "$(basename "${dir}")")

        if [[ -z "${backup_dir}" ]]; then
            log "WARNING" "No backup found for directory: ${dir}"
            continue
        fi

        if ! cp -r "${backup_dir}"/* "${dir}"/; then
            log "ERROR" "Failed to restore directory: ${dir}"
            exit 1
        fi
    done
}

# Cleanup temporary files
cleanup() {
    log "INFO" "Cleaning up temporary files..."
    rm -rf "${BACKUP_BASE_DIR:?}"/*
}

# Main restore process
main() {
    validate_env

    local encrypted_backup
    local decrypted_backup

    encrypted_backup=$(fetch_latest_backup)
    decrypted_backup=$(decrypt_backup "${encrypted_backup}")

    extract_backup "${decrypted_backup}"
    restore_database
    restore_files
    cleanup

    log "INFO" "Restore process completed successfully"
}

# Run main with error handling
if ! main; then
    log "ERROR" "Restore process failed"
    exit 1
fi