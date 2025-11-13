#!/usr/bin/env bash
set -Eeuo pipefail

#
# IA EMPRESARIAL - INSTALADOR UNIFICADO (v5.0 "Redención")
# =========================================================
#

# --- Configuración y Logging ---
LOG_FILE="/var/log/ia_empresarial_install.log"
ERROR_LOG_FILE="/var/log/ia_empresarial_errors.log"
exec > >(tee -a "${LOG_FILE}") 2>&1
info() { echo -e "\033[0;34m[INFO] $(date '+%T') - ${1}\033[0m"; }
success() { echo -e "\033[0;32m[OK] $(date '+%T') - ${1}\033[0m"; }
error() { echo -e "\033[0;31m[ERROR] $(date '+%T') - ${1}\033[0m"; }

fail_with() {
    local code=$1; local message=$2
    error "FATAL (${code}): ${message}"
    echo "$(date '+%F %T') - ${code} - ${message}" >> "${ERROR_LOG_FILE}"
    whiptail --title "💥 MISIÓN ABORTADA 💥" --msgbox "Error: ${code}\n${message}\n\nRevisa ${ERROR_LOG_FILE} y la sección 'Errores Comunes' del README." 12 78
    exit 1
}

# --- Wizard ---
export NEWT_COLORS='root=,black window=white,blue title=brightwhite,blue button=brightwhite,blue border=white,blue textbox=white,blue'
run_wizard() {
    whiptail --title "🚀 IA EMPRESARIAL 🚀" --msgbox "Misión: Democratizar la IA empresarial con una plataforma RAG segura, auto-instalable y optimizada para CPU." 12 78

    EDITION=$(whiptail --title "🌌 Elige Edición" --menu "Selecciona tu edición:" 15 78 3 "Base" "Esencial" "Pro" "Avanzado" "ProMax" "Completo" 3>&1 1>&2 2>&3)
    OLLAMA_MODEL=$(whiptail --title "🧠 Elige Modelo" --menu "Selecciona el modelo LLM:" 15 78 3 "phi3" "Rápido" "llama3" "Potente" "gemma" "Google" 3>&1 1>&2 2>&3)
    OPENWEBUI_PORT=$(whiptail --inputbox "Puerto para WebUI" 8 78 "3000" 3>&1 1>&2 2>&3)

    whiptail --title "✅ Resumen de Misión" --msgbox "Edición: ${EDITION}\nModelo: ${OLLAMA_MODEL}\nPuerto: ${OPENWEBUI_PORT}\n\nLa instalación comenzará ahora." 12 78
}

# --- Lógica de Instalación ---
install_logic() {
(
    # Etapa 1: Dependencias
    echo 10; echo "XXX"; echo "Instalando dependencias..."; echo "XXX"
    DEBIAN_FRONTEND=noninteractive apt-get install -y curl git jq python3-venv whiptail >/dev/null || fail_with "E000_APT_FAILED" "No se pudieron instalar paquetes base."
    if [[ "${EDITION}" != "Base" ]]; then
        DEBIAN_FRONTEND=noninteractive apt-get install -y tesseract-ocr poppler-utils >/dev/null
    fi

    # Etapa 2: Docker
    echo 25; echo "XXX"; echo "Configurando Docker..."; echo "XXX"
    if ! command -v docker &>/dev/null; then
        curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg || fail_with "E001_DOCKER_INSTALL_FAILED" "GPG key download failed."
        echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" > /etc/apt/sources.list.d/docker.list
        apt-get update -y >/dev/null
        apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin >/dev/null || fail_with "E001_DOCKER_INSTALL_FAILED" "Docker CE installation failed."
        systemctl enable --now docker
    fi

    # Etapa 3: Ollama
    echo 40; echo "XXX"; echo "Configurando Ollama..."; echo "XXX"
    if ! command -v ollama &>/dev/null; then
        curl -fsSL https://ollama.com/install.sh | sh || fail_with "E002_OLLAMA_INSTALL_FAILED" "Ollama installation script failed."
    fi
    mkdir -p /etc/systemd/system/ollama.service.d
    echo -e "[Service]\nEnvironment=\"OLLAMA_HOST=127.0.0.1\"" > /etc/systemd/system/ollama.service.d/override.conf
    systemctl daemon-reload && systemctl restart ollama
    ollama pull "${OLLAMA_MODEL}" || fail_with "E003_MODEL_PULL_FAILED" "Failed to pull ${OLLAMA_MODEL}."

    # Etapa 4: Estructura y Archivos
    echo 55; echo "XXX"; echo "Creando estructura del proyecto..."; echo "XXX"
    RAG_LAB_DIR="/opt/rag_lab_${EDITION,,}"
    mkdir -p "${RAG_LAB_DIR}/scripts" "${RAG_LAB_DIR}/config"
    cp src/*.py "${RAG_LAB_DIR}/scripts/"
    cp src/*.sh "${RAG_LAB_DIR}/scripts/"
    chmod +x "${RAG_LAB_DIR}/scripts"/*
    # ... (Generación de .env, docker-compose.yml, etc. específico para cada TIER)

    # Etapa 5: Venv y Servicios
    echo 70; echo "XXX"; echo "Configurando entorno Python..."; echo "XXX"
    python3 -m venv "${RAG_LAB_DIR}/venv" || fail_with "E004_VENV_CREATION_FAILED" "Failed to create Python venv."
    source "${RAG_LAB_DIR}/venv/bin/activate" && pip install -r "${RAG_LAB_DIR}/config/requirements.txt" >/dev/null || fail_with "E005_PIP_INSTALL_FAILED" "Pip install failed."
    deactivate

    echo 85; echo "XXX"; echo "Desplegando contenedores..."; echo "XXX"
    docker compose -f "${RAG_LAB_DIR}/docker-compose.yml" up -d --build || fail_with "E006_DOCKER_COMPOSE_FAILED" "Docker compose up failed."

    # Etapa 6: Smoke Tests
    echo 95; echo "XXX"; echo "Verificando la misión..."; echo "XXX"
    sleep 30 # Dar tiempo a los servicios
    curl -fsS http://127.0.0.1:6333/ready || fail_with "E007_QDRANT_HEALTHCHECK_FAILED" "Qdrant is not ready."

    echo 100
) | whiptail --gauge "🚀 Lanzando Misión..." 20 70 0
}

# --- Main Flow ---
main() {
    preflight_checks
    run_wizard
    install_logic
    whiptail --title "✅ MISIÓN CUMPLIDA" --msgbox "Instalación de la edición ${EDITION} completada." 10 78
}

main "$@"
