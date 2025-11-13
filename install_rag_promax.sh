#!/usr/bin/env bash
set -Eeuo pipefail

#
# RGIA MASTER - PRO MAX INSTALLER (v3.7 Final y Completo)
# =======================================================
#

# --- Logging & Utils ---
LOG_FILE="/var/log/rag_promax_install.log"
exec > >(tee -a "${LOG_FILE}") 2>&1
info() { echo -e "\033[0;34m[INFO] ${1}\033[0m"; }
success() { echo -e "\033[0;32m[SUCCESS] ${1}\033[0m"; }
error() { echo -e "\033[0;31m[ERROR] ${1}\033[0m" >&2; exit 1; }

# --- Preflight & Wizard ---
preflight_checks() {
    info "--- Preflight Checks ---"
    if [[ "${EUID}" -ne 0 ]]; then error "Must be root."; fi; success "Root OK."
    if ! grep -qiE "ubuntu|debian" /etc/os-release; then error "Only Ubuntu/Debian."; fi; success "Distro OK."
    if ! apt-get update -y >/dev/null; then error "apt-get update failed."; fi; success "APT OK."
}
run_wizard() {
    if ! command -v whiptail &>/dev/null; then apt-get -y install whiptail >/dev/null; fi
    export OPENWEBUI_PORT=$(whiptail --inputbox "WebUI Port" 8 78 "3000" 3>&1 1>&2 2>&3)
    export CONTROL_CENTER_PORT=$(whiptail --inputbox "CC Port" 8 78 "8001" 3>&1 1>&2 2>&3)
    export TENANTS=$(whiptail --inputbox "Tenants" 8 78 "default,project_alpha" 3>&1 1>&2 2>&3)
    export LLM_MODEL_CHOICE=$(whiptail --menu "LLM Model" 15 78 4 "phi3" "(Fast)" "llama3" "(Powerful)" "gemma" "(Google)" 3>&1 1>&2 2>&3)
}

# --- Variables ---
export RAG_LAB_DIR="/opt/rag_lab_promax"
export CONFIG_DIR="${RAG_LAB_DIR}/config"
export SCRIPTS_DIR="${RAG_LAB_DIR}/scripts"
export VENV_DIR="${RAG_LAB_DIR}/venv"
export DOCS_DIR_BASE="${RAG_LAB_DIR}/documents"
export CONTROL_CENTER_DIR="${RAG_LAB_DIR}/control_center"

# --- File Generation ---
generate_files() {
    info "--- Generating Files ---"
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
  qdrant: { image: qdrant/qdrant:v1.9.2, container_name: rag_promax_qdrant, restart: unless-stopped, ports: ["127.0.0.1:6333:6333"], volumes: ["${RAG_LAB_DIR}/qdrant_storage:/qdrant/storage"], networks: ["rag_net"] }
  open-webui: { image: ghcr.io/open-webui/open-webui:main, container_name: rag_promax_open_webui, restart: unless-stopped, ports: ["\${OPENWEBUI_PORT-3000}:8080"], volumes: ["${RAG_LAB_DIR}/open_webui_data:/app/backend/data"], environment: ['OLLAMA_BASE_URL=http://host.docker.internal:11434'], extra_hosts: ["host.docker.internal:host-gateway"], networks: ["rag_net"] }
  control-center:
    build: { context: ${CONTROL_CENTER_DIR} }
    container_name: rag_promax_control_center
    restart: unless-stopped
    ports: ["127.0.0.1:\${CONTROL_CENTER_PORT-8001}:8000"]
    volumes: ["/var/run/docker.sock:/var/run/docker.sock", "${RAG_LAB_DIR}:${RAG_LAB_DIR}", "/usr/local/bin/ollama:/usr/local/bin/ollama:ro"]
    extra_hosts: ["host.docker.internal:host-gateway"]
    networks: ["rag_net"]
networks: { rag_net: { driver: bridge } }
EOF

    cp "src/ingestion.py" "${SCRIPTS_DIR}/ingestion_script.py"
    cp "src/query.py" "${SCRIPTS_DIR}/query_agent.py"
    chmod +x "${SCRIPTS_DIR}"/*.py

    cat <<'EOF' >"${CONFIG_DIR}/requirements.txt"
llama-index
qdrant-client
pypdf
sentence-transformers
ollama
python-dotenv
tqdm
pytesseract
pdf2image
urllib3<2.0
EOF

    cat <<'EOF' >"${CONTROL_CENTER_DIR}/Dockerfile"
FROM python:3.11-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY . .
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000"]
EOF
    cat <<'EOF' >"${CONTROL_CENTER_DIR}/requirements.txt"
fastapi
uvicorn[standard]
jinja2
python-dotenv
EOF
    cat <<'EOF' >"${CONTROL_CENTER_DIR}/main.py"
import os, subprocess, json
from fastapi import FastAPI, Request, Form
from fastapi.responses import HTMLResponse, JSONResponse
from fastapi.templating import Jinja2Templates

app=FastAPI(); templates=Jinja2Templates(directory="templates")

@app.get("/",response_class=HTMLResponse)
async def root(request: Request):
    return templates.TemplateResponse("index.html",{"request":request,"tenants":os.getenv("TENANTS","default").split(',')})

@app.get("/api/models")
async def list_models():
    try:
        proc=subprocess.run(["/usr/local/bin/ollama","list"],capture_output=True,text=True,check=True)
        return {"status":"success","models":proc.stdout.strip().split('\n')}
    except Exception as e: return JSONResponse({"status":"error","message":str(e)},500)

@app.post("/api/models/pull")
async def pull_model(model_name:str=Form(...)):
    try:
        subprocess.Popen(["/usr/local/bin/ollama","pull",model_name],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
        return {"status":"success","message":f"Pulling '{model_name}'..."}
    except Exception as e: return JSONResponse({"status":"error","message":str(e)},500)
EOF
    cat <<'EOF' >"${CONTROL_CENTER_DIR}/templates/index.html"
<!DOCTYPE html><html><head><title>RGIA CC</title><link href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.3/dist/css/bootstrap.min.css" rel="stylesheet"></head><body><div class="container mt-4"><h1>RGIA CC (Pro Max)</h1>
<div class="card mt-3"><div class="card-body"><h5 class="card-title">Manage Models</h5><form id="pull-form" class="d-flex mb-3"><input type="text" name="model_name" class="form-control me-2" required><button type="submit" class="btn btn-success">Pull</button></form><h6>Available Models:</h6><ul class="list-group" id="model-list"></ul></div></div>
</div><script src="https://cdn.jsdelivr.net/npm/bootstrap@5.3.3/dist/js/bootstrap.bundle.min.js"></script><script>
const ml=document.getElementById('model-list');async function lm(){const r=await fetch('/api/models');const d=await r.json();if(d.status==='success'){ml.innerHTML=d.models.map(m=>`<li class="list-group-item">${m}</li>`).join('')||'<li>No models.</li>';}}
document.getElementById('pull-form').addEventListener('submit',async e=>{e.preventDefault();await fetch('/api/models/pull',{method:'POST',body:new FormData(e.target)});e.target.reset();setTimeout(lm,1000);});
document.addEventListener('DOMContentLoaded',lm);</script></body></html>
EOF
    success "File generation complete."
}

# --- Installation ---
install_dependencies() {
    info "Installing dependencies..."
    DEBIAN_FRONTEND=noninteractive apt-get install -y tesseract-ocr poppler-utils ca-certificates curl gnupg python3-venv git
    success "Dependencies installed."
}
install_docker() {
    if command -v docker &>/dev/null; then info "Docker exists."; return; fi
    info "Installing Docker..."; install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg|gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    chmod a+r /etc/apt/keyrings/docker.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" >/etc/apt/sources.list.d/docker.list
    DEBIAN_FRONTEND=noninteractive apt-get update -y && apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
    systemctl enable --now docker; success "Docker installed."
}
install_ollama_promax() {
    if command -v ollama &>/dev/null; then info "Ollama exists."; else curl -fsSL https://ollama.com/install.sh|sh; fi
    mkdir -p /etc/systemd/system/ollama.service.d
    echo -e "[Service]\nExecStart=\nExecStart=/usr/local/bin/ollama serve\nEnvironment=\"OLLAMA_HOST=127.0.0.1\"">/etc/systemd/system/ollama.service.d/override.conf
    systemctl daemon-reload && systemctl restart ollama
    LLM_MODELS=("phi3" "llama3" "gemma"); OLLAMA_MODEL_NAMES=("phi3:3.8b-mini-4k-instruct-q4_K_M" "llama3:8b-instruct-q4_K_M" "gemma:7b-instruct-q4_K_M")
    model_idx=0
    for i in "${!LLM_MODELS[@]}"; do if [[ "${LLM_MODELS[$i]}" = "${LLM_MODEL_CHOICE}" ]]; then model_idx=$i; fi; done
    OLLAMA_MODEL_NAME=${OLLAMA_MODEL_NAMES[$model_idx]}
    info "Pulling model ${OLLAMA_MODEL_NAME}..."; ollama pull "${OLLAMA_MODEL_NAME}"; success "Model pulled."
}
setup_python_env() {
    info "Setting up Python venv..."
    python3 -m venv "${VENV_DIR}"
    source "${VENV_DIR}/bin/activate" && pip install -r "${CONFIG_DIR}/requirements.txt" && deactivate
    success "Python venv configured."
}
setup_automation() {
    info "Setting up systemd service..."
    cat <<EOF >/etc/systemd/system/rag_lab_promax.service
[Unit]
Description=RGIA ProMax
After=docker.service network-online.target ollama.service
[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=${RAG_LAB_DIR}
ExecStart=/usr/bin/docker compose up -d --build
ExecStop=/usr/bin/docker compose down
[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload; systemctl enable --now rag_lab_promax.service; success "Systemd service enabled."
}
run_smoke_tests_promax() {
    info "--- Running Smoke Tests (Pro Max) ---"
    sleep 60; local ok=true
    if ! docker compose -f "${RAG_LAB_DIR}/docker-compose.yml" ps | grep -q "Up"; then error "Test 1 FAILED: Containers not up."; ok=false; else success "Test 1: Containers OK."; fi
    local port; port=$(grep CONTROL_CENTER_PORT "${CONFIG_DIR}/.env"|cut -d= -f2)
    if ! curl -fsS "http://127.0.0.1:${port}/api/models"|grep -q "status"; then error "Test 2 FAILED: CC API not responding."; ok=false; else success "Test 2: CC API OK."; fi
    if [[ "$ok" = false ]]; then error "Smoke tests failed."; else success "All smoke tests passed."; fi
}

# --- Main Flow ---
main() {
    preflight_checks
    run_wizard
    info "--- Starting RGIA Master (Pro Max) ---"
    generate_files
    source "${CONFIG_DIR}/.env"
    IFS=',' read -ra ts <<< "$TENANTS"; for t in "${ts[@]}"; do mkdir -p "${DOCS_DIR_BASE}/${t}"; done
    install_dependencies
    install_docker
    install_ollama_promax
    setup_python_env
    setup_automation
    run_smoke_tests_promax
    success "--- RGIA Master (Pro Max) Finished ---"
}

main "$@"
