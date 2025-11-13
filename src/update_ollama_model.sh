#!/usr/-bin/env bash
set -euo pipefail

# --- update_ollama_model.sh ---
# Vuelve a descargar el modelo de Ollama definido en el .env para obtener la última versión.

RAG_LAB_DIR=$(cd "$(dirname "$0")/.." && pwd)
CONFIG_FILE="${RAG_LAB_DIR}/config/.env"

if [[ ! -f "${CONFIG_FILE}" ]]; then
    echo "ERROR: No se encontró el archivo de configuración en ${CONFIG_FILE}." >&2
    exit 1
fi

source "${CONFIG_FILE}"

# Mapeo de modelos (debe coincidir con el instalador)
LLM_MODELS=("phi3" "llama3" "gemma")
OLLAMA_MODEL_NAMES=("phi3:3.8b-mini-4k-instruct-q4_K_M" "llama3:8b-instruct-q4_K_M" "gemma:7b-instruct-q4_K_M")
MODEL_CHOICE=${LLM_MODEL_CHOICE:-"phi3"}

OLLAMA_MODEL_TO_PULL=""
for i in "${!LLM_MODELS[@]}"; do
    if [[ "${LLM_MODELS[$i]}" = "${MODEL_CHOICE}" ]]; then
        OLLAMA_MODEL_TO_PULL=${OLLAMA_MODEL_NAMES[$i]}
        break
    fi
done

if [[ -z "${OLLAMA_MODEL_TO_PULL}" ]]; then
    echo "ERROR: El modelo '${MODEL_CHOICE}' configurado en .env no es una opción válida." >&2
    exit 1
fi

echo "INFO: Intentando actualizar el modelo de Ollama: ${OLLAMA_MODEL_TO_PULL}..."
if command -v ollama &> /dev/null; then
    ollama pull "${OLLAMA_MODEL_TO_PULL}"
    echo "OK: Proceso de actualización del modelo completado."
else
    echo "ERROR: El comando 'ollama' no se encontró. Asegúrate de que Ollama esté instalado correctamente." >&2
    exit 1
fi
