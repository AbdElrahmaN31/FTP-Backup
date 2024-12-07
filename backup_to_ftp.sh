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
        echo "[${level}] ${timestamp}: ${message}" >> "${BACKUP_LOG_DIR}/backup.log"
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

# Create backup directories
prepare_backup_dirs() {
    mkdir -p "${BACKUP_BASE_DIR}"
    mkdir -p "${BACKUP_LOG_DIR}"
}

# Database backup
backup_database() {
    log "INFO" "Starting database backup..."
    # shellcheck disable=SC2155
    local db_backup_file="${BACKUP_BASE_DIR}/db_backup_$(date +%F).sql"

    if ! mysqldump -h "${DB_HOST}" -u "${DB_USER}" -p"${DB_PASS}" "${DB_NAME}" > "${db_backup_file}"; then
        log "ERROR" "Database backup failed"
        exit 1
    fi

    echo "${db_backup_file}"
}

# Create backup archive
create_backup_archive() {
    local db_backup_file="$1"
    # shellcheck disable=SC2155
    local backup_file="${BACKUP_BASE_DIR}/backup_$(date +%F).tar.gz"

    log "INFO" "Creating backup archive..."
    if ! tar -czf "${backup_file}" "${BACKUP_DIRS[@]}" "${db_backup_file}"; then
        log "ERROR" "Backup archive creation failed"
        exit 1
    fi

    echo "${backup_file}"
}

# Encrypt backup
encrypt_backup() {
    local backup_file="$1"
    local encrypted_file="${backup_file}.gpg"

    log "INFO" "Encrypting backup..."
    if ! gpg --batch --yes --symmetric --cipher-algo "${ENCRYPTION_CIPHER}" \
        --passphrase "${ENCRYPTION_PASSPHRASE}" "${backup_file}"; then
        log "ERROR" "Backup encryption failed"
        exit 1
    fi

    echo "${encrypted_file}"
}

# Upload to FTP
upload_to_ftp() {
    local encrypted_file="$1"

    log "INFO" "Uploading backup to FTP..."
    if ! lftp -u "${FTP_USER},${FTP_PASS}" "ftps://${FTP_HOST}" <<EOF
        put "${encrypted_file}"
        bye
EOF
    then
        log "ERROR" "FTP upload failed"
        exit 1
    fi
}

# Manage backup retention
# shellcheck disable=SC2120
manage_backups() {
    log "INFO" "Managing backup retention..."
    local backups
    local retention_count="${BACKUP_RETENTION_COUNT:-8}"

    # List files and sort by date
    # Implementation depends on specific FTP server capabilities
    # This is a placeholder and might need customization
    lftp -u "${FTP_USER},${FTP_PASS}" "ftps://${FTP_HOST}" <<EOF
        find -l | sort -r | awk '{print $9}' > /tmp/backup_list.txt
        bye
EOF

    mapfile -t backups < /tmp/backup_list.txt

    if [[ "${#backups[@]}" -gt "${retention_count}" ]]; then
        local delete_count=$((${#backups[@]} - retention_count))
        for ((i=0; i<delete_count; i++)); do
            log "INFO" "Deleting old backup: ${backups[i]}"
            lftp -u "${FTP_USER},${FTP_PASS}" "ftps://${FTP_HOST}" <<EOF
                rm "${backups[i]}"
                bye
EOF
        done
    fi

    rm /tmp/backup_list.txt
}

# Cleanup temporary files
cleanup() {
    log "INFO" "Cleaning up temporary files..."
    rm -f "${BACKUP_BASE_DIR}"/*.{tar.gz,sql,gpg}
}

# Main backup process
main() {
    validate_env
    prepare_backup_dirs

    local db_backup
    local backup_archive
    local encrypted_backup

    db_backup=$(backup_database)
    backup_archive=$(create_backup_archive "${db_backup}")
    encrypted_backup=$(encrypt_backup "${backup_archive}")

    upload_to_ftp "${encrypted_backup}"
    manage_backups
    cleanup

    log "INFO" "Backup process completed successfully"
}

# Run main with error handling
if ! main; then
    log "ERROR" "Backup process failed"
    exit 1
fi