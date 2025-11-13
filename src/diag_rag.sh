#!/usr/bin/env bash
set -euo pipefail

if [[ ! -f "../config/.env" ]]; then
    echo "Error: Ejecutar desde el directorio 'scripts'."
    exit 1
fi

source ../config/.env

echo "--- Estado de los Contenedores Docker ---"
docker compose -f "${RAG_LAB_DIR}/docker-compose.yml" ps

echo -e "\n--- Estado del Servicio systemd ---"
systemctl status "rag_lab_${EDITION,,}" --no-pager

echo -e "\n--- Endpoints Principales ---"
curl -s -o /dev/null -w "Qdrant Ready: %{http_code}\n" http://127.0.0.1:6333/ready

echo -e "\n--- Últimos logs de ingesta ---"
tail -n 10 "/var/log/rag_ingest_${EDITION,,}.log" || echo "No hay logs de ingesta."
