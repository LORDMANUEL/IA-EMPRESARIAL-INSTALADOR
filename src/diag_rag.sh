#!/usr/bin/env bash
set -euo pipefail

# --- diag_rag.sh ---
# Proporciona un diagnóstico rápido del estado de la plataforma.

RAG_LAB_DIR=$(cd "$(dirname "$0")/.." && pwd)
CONFIG_FILE="${RAG_LAB_DIR}/config/.env"

if [[ ! -f "${CONFIG_FILE}" ]]; then
    echo "ERROR: No se encontró el archivo de configuración en ${CONFIG_FILE}." >&2
    exit 1
fi

source "${CONFIG_FILE}"
SERVICE_NAME="rag_lab_${EDITION,,}"

echo "--- 🛰️  Diagnóstico Rápido de IA Empresarial (${EDITION}) ---"

echo -e "\n--- 🐳 Estado de los Contenedores Docker ---"
if command -v docker &> /dev/null && docker compose -f "${RAG_LAB_DIR}/docker-compose.yml" ps &> /dev/null; then
    docker compose -f "${RAG_LAB_DIR}/docker-compose.yml" ps
else
    echo "WARN: Docker o docker-compose no está disponible o el archivo .yml no se encuentra."
fi

echo -e "\n--- ⚙️  Estado del Servicio Systemd (${SERVICE_NAME}) ---"
if systemctl is-active --quiet "${SERVICE_NAME}"; then
    echo "✅ Servicio está ACTIVO."
else
    echo "❌ Servicio está INACTIVO."
fi
systemctl status "${SERVICE_NAME}" --no-pager | grep 'Loaded\|Active\|Main PID'

echo -e "\n--- 🌐 Endpoints Principales ---"
echo "Intentando conectar con Qdrant..."
if curl -fsS http://127.0.0.1:6333/ready > /dev/null; then
    echo "✅ Qdrant está respondiendo en http://127.0.0.1:6333"
else
    echo "❌ Qdrant NO responde."
fi

if [[ "${ENABLE_CONTROL_CENTER:-false}" == "true" ]]; then
    echo "Intentando conectar con el Control Center..."
    if curl -fsS http://127.0.0.1:${CONTROL_CENTER_PORT}/ > /dev/null; then
        echo "✅ Control Center está respondiendo en http://127.0.0.1:${CONTROL_CENTER_PORT}"
    else
        echo "❌ Control Center NO responde."
    fi
fi

echo -e "\n--- 🧠 Modelo Ollama ---"
if command -v ollama &> /dev/null; then
    ollama list | head -n 2
else
    echo "WARN: Comando 'ollama' no encontrado."
fi

echo -e "\n--- 💾 Uso de Disco y Memoria ---"
df -h "${RAG_LAB_DIR}"
free -h

echo -e "\n--- 📜 Últimos Logs de Ingesta ---"
INGEST_LOG="/var/log/rag_ingest_${EDITION,,}.log"
if [[ -f "${INGEST_LOG}" ]]; then
    tail -n 5 "${INGEST_LOG}"
else
    echo "No se han encontrado logs de ingesta en ${INGEST_LOG}."
fi

echo -e "\n--- Diagnóstico Completado ---"
