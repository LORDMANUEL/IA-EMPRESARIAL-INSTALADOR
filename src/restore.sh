#!/usr/bin/env bash
set -euo pipefail

if [[ ! -f "../config/.env" ]]; then
    echo "Error: Ejecutar desde el directorio 'scripts'."
    exit 1
fi

source ../config/.env

BACKUP_FILE=$1

if [[ -z "$BACKUP_FILE" ]]; then
    echo "Uso: $0 /ruta/al/backup.tgz"
    exit 1
fi

if [[ ! -f "$BACKUP_FILE" ]]; then
    echo "Error: El archivo de backup no existe."
    exit 1
fi

echo ">>> Deteniendo servicios..."
systemctl stop "rag_lab_${EDITION,,}"

echo ">>> Restaurando backup desde ${BACKUP_FILE}..."
tar -xzvf "${BACKUP_FILE}" -C "$(dirname "${RAG_LAB_DIR}")"

echo ">>> Reiniciando servicios..."
systemctl start "rag_lab_${EDITION,,}"

echo ">>> Restauración completada."
