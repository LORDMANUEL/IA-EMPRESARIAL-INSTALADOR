#!/usr/bin/env bash
set -euo pipefail

# Este script se copia a /opt/rag_lab_<tier>/scripts/
# Debe leer la configuración desde el .env en ese directorio

# Salir si no estamos en el directorio de scripts
if [[ ! -f "../config/.env" ]]; then
    echo "Error: Este script debe ser ejecutado desde el directorio 'scripts' de su instalación."
    exit 1
fi

source ../config/.env

BACKUP_BASE_DIR="${RAG_LAB_DIR}/backups"
TIMESTAMP=$(date +"%Y-%m-%d_%H-%M-%S")
BACKUP_FILE="${BACKUP_BASE_DIR}/rag_lab_backup_${TIMESTAMP}.tgz"

echo ">>> Creando backup de ${RAG_LAB_DIR}..."
mkdir -p "${BACKUP_BASE_DIR}"

# Detener servicios para asegurar consistencia
echo ">>> Deteniendo la pila de servicios..."
systemctl stop "rag_lab_${EDITION,,}" || echo "El servicio no estaba corriendo, continuando..."

# Crear el archivo tar
tar --exclude="${BACKUP_BASE_DIR}" -czvf "${BACKUP_FILE}" -C "$(dirname "${RAG_LAB_DIR}")" "$(basename "${RAG_LAB_DIR}")"

# Reiniciar servicios
echo ">>> Reiniciando la pila de servicios..."
systemctl start "rag_lab_${EDITION,,}"

echo ">>> Backup completado: ${BACKUP_FILE}"
ls -lh "${BACKUP_FILE}"
