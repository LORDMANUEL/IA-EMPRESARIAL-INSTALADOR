#!/usr-bin/env bash
set -Eeuo pipefail

#
# RGIA MASTER - PRO VERSION INSTALLER (v2.7 Final Corrected)
# ==========================================================
#

# --- Logging & Utils ---
LOG_FILE="/var/log/rag_pro_install.log"
exec > >(tee -a "${LOG_FILE}") 2>&1
info() { echo -e "\033[0;34m[INFO] ${1}\033[0m"; }
success() { echo -e "\033[0;32m[SUCCESS] ${1}\033[0m"; }
error() { echo -e "\033[0;31m[ERROR] ${1}\033[0m" >&2; exit 1; }

# --- Preflight Checks ---
preflight_checks() {
    info "--- Preflight Checks ---"
    if [[ "${EUID}" -ne 0 ]]; then error "Must be root."; fi; success "Root OK."
    if ! grep -qiE "ubuntu|debian" /etc/os-release; then error "Only Ubuntu/Debian."; fi; success "Distro OK."
    if ! apt-get update -y >/dev/null; then error "apt-get update failed."; fi; success "APT OK."
}

# --- Variables ---
export RAG_LAB_DIR="/opt/rag_lab_pro"
export CONFIG_DIR="${RAG_LAB_DIR}/config"
export SCRIPTS_DIR="${RAG_LAB_DIR}/scripts"
export VENV_DIR="${RAG_LAB_DIR}/venv"
export DOCS_DIR_BASE="${RAG_LAB_DIR}/documents"
export CONTROL_CENTER_DIR="${RAG_LAB_DIR}/control_center"

# --- File Generation ---
generate_files() {
    info "--- Generating Files ---"
    mkdir -p "${SCRIPTS_DIR}" "${CONFIG_DIR}" "${CONTROL_CENTER_DIR}/templates" "${DOCS_DIR_BASE}"

    cat <<'EOF' >"${CONFIG_DIR}/.env"
OPENWEBUI_PORT=3000
CONTROL_CENTER_PORT=8001
TENANTS=default,dev_team
LLM_MODEL_CHOICE=phi3
EMBEDDING_MODEL=intfloat/multilingual-e5-small
ENABLE_OCR=true
OCR_LANGUAGES=spa
EOF

    cat <<EOF >"${RAG_LAB_DIR}/docker-compose.yml"
version: '3.8'
services:
  qdrant: { image: qdrant/qdrant:v1.9.2, container_name: rag_pro_qdrant, restart: unless-stopped, ports: ["127.0.0.1:6333:6333"], volumes: ["${RAG_LAB_DIR}/qdrant_storage:/qdrant/storage"], networks: ["rag_net"] }
  open-webui: { image: ghcr.io/open-webui/open-webui:main, container_name: rag_pro_open_webui, restart: unless-stopped, ports: ["\${OPENWEBUI_PORT-3000}:8080"], volumes: ["${RAG_LAB_DIR}/open_webui_data:/app/backend/data"], environment: ['OLLAMA_BASE_URL=http://host.docker.internal:11434'], extra_hosts: ["host.docker.internal:host-gateway"], networks: ["rag_net"] }
  control-center: { build: { context: ${CONTROL_CENTER_DIR} }, container_name: rag_pro_control_center, restart: unless-stopped, ports: ["127.0.0.1:\${CONTROL_CENTER_PORT-8001}:8000"], volumes: ["/var/run/docker.sock:/var/run/docker.sock", "${RAG_LAB_DIR}:${RAG_LAB_DIR}"], networks: ["rag_net"] }
networks: { rag_net: { driver: bridge } }
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
import os, subprocess
from fastapi import FastAPI, Request, Form
from fastapi.responses import HTMLResponse, JSONResponse
from fastapi.templating import Jinja2Templates

RAG_LAB_DIR = "/opt/rag_lab_pro"
app = FastAPI()
templates = Jinja2Templates(directory="templates")

@app.get("/", response_class=HTMLResponse)
async def root(request: Request):
    tenants = os.getenv("TENANTS", "default").split(',')
    return templates.TemplateResponse("index.html", {"request": request, "tenants": tenants})

@app.post("/run-ingest")
async def handle_ingest(tenant: str = Form(...)):
    script = os.path.join(RAG_LAB_DIR, "scripts/ingestion_script.py")
    venv_python = os.path.join(RAG_LAB_DIR, "venv/bin/python")
    try:
        proc = subprocess.run([venv_python, script, "--tenant", tenant], capture_output=True, text=True, check=True, env=os.environ)
        return JSONResponse({"status": "success", "output": proc.stdout})
    except subprocess.CalledProcessError as e:
        return JSONResponse({"status": "error", "output": e.stderr})
EOF
    cat <<'EOF' >"${CONTROL_CENTER_DIR}/templates/index.html"
<!DOCTYPE html><html lang="es"><head><title>RGIA CC</title><link href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.3/dist/css/bootstrap.min.css" rel="stylesheet"></head><body><div class="container mt-4"><h1>RGIA Control Center</h1><div class="card mt-3"><div class="card-body"><h5 class="card-title">Ingesta Manual</h5><form id="ingest-form"><select class="form-select" name="tenant">{% for t in tenants %}<option value="{{ t }}">{{ t }}</option>{% endfor %}</select><button type="submit" class="btn btn-primary mt-2">Iniciar</button></form><pre id="out" class="mt-2 bg-dark text-white p-2" style="height:200px;overflow-y:scroll;">...</pre></div></div></div><script>
document.getElementById('ingest-form').addEventListener('submit',async e=>{e.preventDefault();const o=document.getElementById('out');o.textContent='...';const r=await fetch('/run-ingest',{method:'POST',body:new FormData(e.target)});const j=await r.json();o.textContent=j.status==='success'?j.output:'ERROR:\n'+j.output;});</script></body></html>
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
install_ollama() {
    if command -v ollama &>/dev/null; then info "Ollama exists."; else info "Installing Ollama..."; curl -fsSL https://ollama.com/install.sh|sh; fi
    info "Configuring Ollama..."; mkdir -p /etc/systemd/system/ollama.service.d
    echo -e "[Service]\nExecStart=\nExecStart=/usr/local/bin/ollama serve\nEnvironment=\"OLLAMA_HOST=127.0.0.1\"">/etc/systemd/system/ollama.service.d/override.conf
    systemctl daemon-reload && systemctl restart ollama
    info "Pulling model..."; ollama pull phi3; success "Model pulled."
}
setup_python_env() {
    info "Setting up Python venv..."
    python3 -m venv "${VENV_DIR}"
    source "${VENV_DIR}/bin/activate" && pip install -r "${CONFIG_DIR}/requirements.txt" && deactivate
    success "Python venv configured."
}
setup_automation() {
    info "Setting up systemd service..."
    cat <<EOF >/etc/systemd/system/rag_lab_pro.service
[Unit]
Description=RGIA Pro
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
    systemctl daemon-reload; systemctl enable --now rag_lab_pro.service; success "Systemd service enabled."
}
run_smoke_tests() {
    info "--- Running Smoke Tests ---"
    info "Waiting 60s for services..."
    sleep 60
    local ok=true
    if ! docker compose -f "${RAG_LAB_DIR}/docker-compose.yml" ps | grep -q "Up"; then error "Test 1 FAILED: Containers not up."; ok=false; else success "Test 1: Containers OK."; fi
    local port; port=$(grep CONTROL_CENTER_PORT "${CONFIG_DIR}/.env" | cut -d= -f2)
    if ! curl -fsS "http://127.0.0.1:${port}/" >/dev/null; then error "Test 2 FAILED: CC not responding."; ok=false; else success "Test 2: CC OK."; fi
    if [[ "$ok" = false ]]; then error "Smoke tests failed."; else success "All smoke tests passed."; fi
}

# --- Main Flow ---
main() {
    preflight_checks
    info "--- Starting RGIA Master (Pro) ---"
    generate_files
    source "${CONFIG_DIR}/.env"
    IFS=',' read -ra ts <<< "$TENANTS"; for t in "${ts[@]}"; do mkdir -p "${DOCS_DIR_BASE}/${t}"; done
    install_dependencies
    install_docker
    install_ollama
    setup_python_env
    setup_automation
    run_smoke_tests
    success "--- RGIA Master (Pro) Finished ---"
}

main "$@"
