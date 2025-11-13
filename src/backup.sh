#!/usr/bin/env bash
set -euo pipefail

# --- backup.sh ---
# Crea un backup completo del directorio de la aplicación.

# Se asume que este script se encuentra en RAG_LAB_DIR/scripts
RAG_LAB_DIR=$(cd "$(dirname "$0")/.." && pwd)
CONFIG_FILE="${RAG_LAB_DIR}/config/.env"

if [[ ! -f "${CONFIG_FILE}" ]]; then
    echo "ERROR: No se encontró el archivo de configuración en ${CONFIG_FILE}." >&2
    exit 1
fi

source "${CONFIG_FILE}"

BACKUP_DIR="${RAG_LAB_DIR}/backups"
TIMESTAMP=$(date +"%Y-%m-%d_%H-%M-%S")
BACKUP_FILE="${BACKUP_DIR}/rag_lab_backup_${TIMESTAMP}.tgz"
SERVICE_NAME="rag_lab_${EDITION,,}"

echo "INFO: Creando directorio de backups en ${BACKUP_DIR}..."
mkdir -p "${BACKUP_DIR}"

echo "INFO: Deteniendo el servicio ${SERVICE_NAME} para un backup consistente..."
systemctl stop "${SERVICE_NAME}" || {
    echo "WARN: No se pudo detener el servicio (puede que no estuviera corriendo). Continuando..."
}

echo "INFO: Creando backup en ${BACKUP_FILE}..."
tar --exclude="${BACKUP_DIR}" \
    -czvf "${BACKUP_FILE}" \
    -C "$(dirname "${RAG_LAB_DIR}")" \
    "$(basename "${RAG_LAB_DIR}")"

echo "INFO: Reiniciando el servicio ${SERVICE_NAME}..."
systemctl start "${SERVICE_NAME}"

echo "OK: Backup completado exitosamente."
ls -lh "${BACKUP_FILE}"
