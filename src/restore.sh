#!/usr/bin/env bash
set -euo pipefail

# --- restore.sh ---
# Restaura un backup completo desde un archivo .tgz.

RAG_LAB_DIR=$(cd "$(dirname "$0")/.." && pwd)
CONFIG_FILE="${RAG_LAB_DIR}/config/.env"

if [[ ! -f "${CONFIG_FILE}" ]]; then
    echo "ERROR: No se encontró el archivo de configuración en ${CONFIG_FILE}." >&2
    exit 1
fi

source "${CONFIG_FILE}"

if [[ -z "${1-}" ]]; then
    echo "ERROR: Debes proporcionar la ruta al archivo de backup .tgz." >&2
    echo "Uso: $0 /ruta/a/backup.tgz" >&2
    exit 1
fi

BACKUP_FILE=$1
SERVICE_NAME="rag_lab_${EDITION,,}"

if [[ ! -f "${BACKUP_FILE}" ]]; then
    echo "ERROR: El archivo de backup no existe en ${BACKUP_FILE}." >&2
    exit 1
fi

echo "INFO: Deteniendo el servicio ${SERVICE_NAME} para la restauración..."
systemctl stop "${SERVICE_NAME}" || {
    echo "WARN: No se pudo detener el servicio (puede que no estuviera corriendo). Continuando..."
}

echo "INFO: Restaurando desde ${BACKUP_FILE}..."
# Restaurar en el directorio padre de RAG_LAB_DIR
tar -xzvf "${BACKUP_FILE}" -C "$(dirname "${RAG_LAB_DIR}")"

echo "INFO: Reiniciando el servicio ${SERVICE_NAME}..."
systemctl start "${SERVICE_NAME}"

echo "OK: Restauración completada exitosamente."
