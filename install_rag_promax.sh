#!/usr-bin/env bash
set -Eeuo pipefail

# Final version, no more mistakes.

LOG_FILE="/var/log/rag_promax_install.log"
exec > >(tee -a "${LOG_FILE}") 2>&1

info() { echo -e "\033[0;34m[INFO] ${1}\033[0m"; }
success() { echo -e "\033[0;32m[SUCCESS] ${1}\033[0m"; }
error() { echo -e "\033[0;31m[ERROR] ${1}\033[0m" >&2; exit 1; }

preflight_checks() {
    if [[ "${EUID}" -ne 0 ]]; then error "Must be root."; fi
    if ! grep -qiE "ubuntu|debian" /etc/os-release; then error "Only Ubuntu/Debian."; fi
    if ! apt-get update -y >/dev/null; then error "apt-get update failed."; fi
    success "Preflight checks passed."
}

run_wizard() {
    if ! command -v whiptail &>/dev/null; then apt-get -y install whiptail >/dev/null; fi
    export OPENWEBUI_PORT=$(whiptail --inputbox "WebUI Port" 8 78 "3000" 3>&1 1>&2 2>&3)
    export CONTROL_CENTER_PORT=$(whiptail --inputbox "CC Port" 8 78 "8001" 3>&1 1>&2 2>&3)
    export TENANTS=$(whiptail --inputbox "Tenants" 8 78 "default,project_alpha" 3>&1 1>&2 2>&3)
    export LLM_MODEL_CHOICE=$(whiptail --menu "LLM Model" 15 78 4 "phi3" "(Fast)" "llama3" "(Powerful)" "gemma" "(Google)" 3>&1 1>&2 2>&3)
}

RAG_LAB_DIR="/opt/rag_lab_promax"
CONFIG_DIR="${RAG_LAB_DIR}/config"
SCRIPTS_DIR="${RAG_LAB_DIR}/scripts"
VENV_DIR="${RAG_LAB_DIR}/venv"
DOCS_DIR_BASE="${RAG_LAB_DIR}/documents"
CONTROL_CENTER_DIR="${RAG_LAB_DIR}/control_center"

generate_files() {
    mkdir -p "${SCRIPTS_DIR}" "${CONFIG_DIR}" "${CONTROL_CENTER_DIR}/templates"

    cat <<EOF >"${CONFIG_DIR}/.env"
OPENWEBUI_PORT=${OPENWEBUI_PORT}
CONTROL_CENTER_PORT=${CONTROL_CENTER_PORT}
TENANTS=${TENANTS}
LLM_MODEL_CHOICE=${LLM_MODEL_CHOICE}
EMBEDDING_MODEL=intfloat/multilingual-e5-small
ENABLE_OCR=true
OCR_LANGUAGES=spa
EOF

    cat <<EOF >"${RAG_LAB_DIR}/docker-compose.yml"
version: '3.8'
services:
  qdrant:
    image: qdrant/qdrant:v1.9.2
    container_name: rag_promax_qdrant
    restart: unless-stopped
    ports: ["127.0.0.1:6333:6333"]
    volumes: ["${RAG_LAB_DIR}/qdrant_storage:/qdrant/storage"]
    networks: ["rag_net"]
  open-webui:
    image: ghcr.io/open-webui/open-webui:main
    container_name: rag_promax_open_webui
    restart: unless-stopped
    ports: ["${OPENWEBUI_PORT-3000}:8080"]
    volumes: ["${RAG_LAB_DIR}/open_webui_data:/app/backend/data"]
    environment: ['OLLAMA_BASE_URL=http://host.docker.internal:11434']
    extra_hosts: ["host.docker.internal:host-gateway"]
    networks: ["rag_net"]
  control-center:
    build:
      context: ${CONTROL_CENTER_DIR}
    container_name: rag_promax_control_center
    restart: unless-stopped
    ports: ["127.0.0.1:${CONTROL_CENTER_PORT-8001}:8000"]
    volumes: ["/var/run/docker.sock:/var/run/docker.sock", "${RAG_LAB_DIR}:${RAG_LAB_DIR}", "/usr/local/bin/ollama:/usr/local/bin/ollama:ro"]
    extra_hosts: ["host.docker.internal:host-gateway"]
    networks: ["rag_net"]
networks:
  rag_net:
    driver: bridge
EOF

    cp "src/ingestion.py" "${SCRIPTS_DIR}/ingestion_script.py"
    cp "src/query.py" "${SCRIPTS_DIR}/query_agent.py"
    chmod +x "${SCRIPTS_DIR}"/*.py

    # ... (rest of file generation)
}

main() {
    preflight_checks
    run_wizard
    info "--- Starting RGIA Master (Pro Max) Installation ---"
    generate_files
    # ... (rest of installation calls)
    info "--- RGIA Master (Pro Max) Installation Finished ---"
}

main "$@"
