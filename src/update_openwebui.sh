#!/usr/bin/env bash
set -euo pipefail

# --- update_openwebui.sh ---
# Actualiza la imagen del contenedor de Open WebUI a la última versión.

RAG_LAB_DIR=$(cd "$(dirname "$0")/.." && pwd)
cd "${RAG_LAB_DIR}"

echo "INFO: Intentando actualizar la imagen de Open WebUI..."
docker compose pull open-webui

echo "INFO: Reiniciando el servicio de Open WebUI para aplicar la actualización..."
docker compose up -d open-webui

echo "OK: Proceso de actualización de Open WebUI completado."
