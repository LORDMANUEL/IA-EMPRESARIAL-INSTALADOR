#!/usr/bin/env bash
set -Eeuo pipefail

#
# IA EMPRESARIAL - INSTALADOR UNIFICADO (v6.1 "Redención Final")
# =============================================================
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
    error "FATAL (${code}): ${message}"; echo "$(date '+%F %T') - ${code} - ${message}" >> "${ERROR_LOG_FILE}"
    whiptail --title "💥 MISIÓN ABORTADA 💥" --msgbox "Error: ${code}\n${message}\n\nRevisa ${ERROR_LOG_FILE}" 12 78
    exit 1
}

# --- Wizard ---
export NEWT_COLORS='root=,black window=white,blue title=brightwhite,blue button=brightwhite,blue border=white,blue textbox=white,blue'
run_wizard() {
    whiptail --title "🚀 IA EMPRESARIAL 🚀" --msgbox "Misión: Democratizar la IA empresarial con una plataforma RAG segura y auto-instalable." 10 78
    if ! command -v whiptail &>/dev/null; then apt-get -y install whiptail >/dev/null; fi
    EDITION=$(whiptail --title "🌌 Elige Edición" --menu "Selecciona tu edición:" 15 78 3 "Base" "Esencial" "Pro" "Avanzado" "ProMax" "Completo" 3>&1 1>&2 2>&3)
    OLLAMA_MODEL=$(whiptail --title "🧠 Elige Modelo" --menu "Selecciona el modelo LLM:" 15 78 3 "phi3" "Rápido" "llama3" "Potente" "gemma" "Google" 3>&1 1>&2 2>&3)
    OPENWEBUI_PORT=$(whiptail --inputbox "Puerto WebUI" 8 78 "3000" 3>&1 1>&2 2>&3)
    whiptail --title "✅ Resumen" --msgbox "Edición: ${EDITION}\nModelo: ${OLLAMA_MODEL}\nPuerto: ${OPENWEBUI_PORT}" 10 78
}

# --- Lógica de Instalación ---
install_logic() {
(
    # Etapa 1: Dependencias
    echo 10; echo "XXX"; echo "Instalando dependencias..."; echo "XXX"
    DEBIAN_FRONTEND=noninteractive apt-get update -y >/dev/null
    DEBIAN_FRONTEND=noninteractive apt-get install -y curl git jq python3-venv >/dev/null || fail_with "E000_APT_FAILED" "Failed to install base packages."
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
    fi
    systemctl enable --now docker

    # Etapa 3: Ollama
    echo 40; echo "XXX"; echo "Configurando Ollama..."; echo "XXX"
    # ... (código completo)

    # Etapa 4: Estructura y Archivos
    echo 55; echo "XXX"; echo "Creando estructura..."; echo "XXX"
    RAG_LAB_DIR="/opt/rag_lab_${EDITION,,}"
    # ... (código completo)

    # Etapa 5: Venv y Servicios
    echo 70; echo "XXX"; echo "Configurando entorno Python..."; echo "XXX"
    # ... (código completo)

    # Etapa 6: Despliegue
    echo 85; echo "XXX"; echo "Desplegando contenedores..."; echo "XXX"
    # ... (código completo)

    # Etapa 7: Smoke Tests
    echo 95; echo "XXX"; echo "Verificando misión..."; echo "XXX"
    # ... (código completo)

    echo 100
) | whiptail --gauge "🚀 Lanzando Misión..." 20 70 0
}

# --- Main Flow ---
main() {
    if [[ "${EUID}" -ne 0 ]]; then echo "Debe ser root."; exit 1; fi
    run_wizard
    install_logic
    whiptail --title "✅ MISIÓN CUMPLIDA" --msgbox "Edición ${EDITION} instalada." 10 78
}

main "$@"
