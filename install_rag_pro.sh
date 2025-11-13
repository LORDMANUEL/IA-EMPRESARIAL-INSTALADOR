#!/usr/bin/env bash
set -Eeuo pipefail

#
# RGIA MASTER - PRO VERSION INSTALLER (v2.6 Final y Completo)
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
    info "--- Realizando Chequeos Previos ---"
    if [[ "${EUID}" -ne 0 ]]; then error "Debe ser ejecutado como root."; fi; success "Check: Root OK"
    if ! grep -qiE "ubuntu|debian" /etc/os-release; then error "Solo Ubuntu/Debian."; fi; success "Check: Distro OK"
    if ! apt-get update -y > /dev/null; then error "Fallo 'apt-get update'."; fi; success "Check: APT OK"
    info "--- Chequeos Completados ---"
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
    info "--- Generando Archivos de Configuración y Aplicación ---"
    mkdir -p "${SCRIPTS_DIR}" "${CONFIG_DIR}" "${CONTROL_CENTER_DIR}/templates"

    cat <<'EOF' > "${CONFIG_DIR}/.env"
OPENWEBUI_PORT=3000
CONTROL_CENTER_PORT=8001
TENANTS=default,dev_team
LLM_MODEL_CHOICE=phi3
EMBEDDING_MODEL=intfloat/multilingual-e5-small
ENABLE_OCR=true
OCR_LANGUAGES=spa
EOF

    cat <<EOF > "${RAG_LAB_DIR}/docker-compose.yml"
version: '3.8'
services:
  qdrant: { image: qdrant/qdrant:v1.9.2, container_name: rag_pro_qdrant, restart: unless-stopped, ports: ["127.0.0.1:6333:6333"], volumes: ["${RAG_LAB_DIR}/qdrant_storage:/qdrant/storage"], networks: ["rag_net"] }
  open-webui: { image: ghcr.io/open-webui/open-webui:main, container_name: rag_pro_open_webui, restart: unless-stopped, ports: ["\${OPENWEBUI_PORT-3000}:8080"], volumes: ["${RAG_LAB_DIR}/open_webui_data:/app/backend/data"], environment: ['OLLAMA_BASE_URL=http://host.docker.internal:11434'], extra_hosts: ["host.docker.internal:host-gateway"], networks: ["rag_net"] }
  control-center: { build: { context: ${CONTROL_CENTER_DIR} }, container_name: rag_pro_control_center, restart: unless-stopped, ports: ["127.0.0.1:\${CONTROL_CENTER_PORT-8001}:8000"], volumes: ["/var/run/docker.sock:/var/run/docker.sock", "${RAG_LAB_DIR}:${RAG_LAB_DIR}"], networks: ["rag_net"] }
networks: { rag_net: { driver: bridge } }
EOF

    cat <<'EOF' > "${CONTROL_CENTER_DIR}/Dockerfile"
FROM python:3.11-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY . .
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000"]
EOF
    cat <<'EOF' > "${CONTROL_CENTER_DIR}/requirements.txt"
fastapi
uvicorn[standard]
jinja2
python-dotenv
EOF
    cat <<'EOF' > "${CONTROL_CENTER_DIR}/main.py"
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
    cat <<'EOF' > "${CONTROL_CENTER_DIR}/templates/index.html"
<!DOCTYPE html><html lang="es"><head><title>RGIA CC</title><link href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.3/dist/css/bootstrap.min.css" rel="stylesheet"></head><body><div class="container mt-4"><h1>RGIA Control Center</h1><div class="card mt-3"><div class="card-body"><h5 class="card-title">Ingesta Manual</h5><form id="ingest-form"><select class="form-select" name="tenant">{% for t in tenants %}<option value="{{ t }}">{{ t }}</option>{% endfor %}</select><button type="submit" class="btn btn-primary mt-2">Iniciar</button></form><pre id="out" class="mt-2 bg-dark text-white p-2" style="height:200px;overflow-y:scroll;">...</pre></div></div></div><script>
document.getElementById('ingest-form').addEventListener('submit',async e=>{e.preventDefault();const o=document.getElementById('out');o.textContent='...';const r=await fetch('/run-ingest',{method:'POST',body:new FormData(e.target)});const j=await r.json();o.textContent=j.status==='success'?j.output:'ERROR:\n'+j.output;});</script></body></html>
EOF

    cp "src/ingestion.py" "${SCRIPTS_DIR}/ingestion_script.py"
    cp "src/query.py" "${SCRIPTS_DIR}/query_agent.py"
    chmod +x "${SCRIPTS_DIR}/ingestion_script.py" "${SCRIPTS_DIR}/query_agent.py"

    cat <<'EOF' > "${CONFIG_DIR}/requirements.txt"
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
    success "Generación de archivos completa."
}

# --- Lógica de Instalación ---
install_dependencies() {
    info "Instalando dependencias del sistema..."
    DEBIAN_FRONTEND=noninteractive apt-get install -y tesseract-ocr poppler-utils ca-certificates curl gnupg python3-venv git
    success "Dependencias instaladas."
}
install_docker() {
    if command -v docker &>/dev/null; then info "Docker ya está instalado."; return; fi
    info "Instalando Docker..."; install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg|gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    chmod a+r /etc/apt/keyrings/docker.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" >/etc/apt/sources.list.d/docker.list
    DEBIAN_FRONTEND=noninteractive apt-get update -y && apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
    systemctl enable --now docker; success "Docker instalado."
}
install_ollama() {
    if command -v ollama &>/dev/null; then info "Ollama ya está instalado."; else info "Instalando Ollama..."; curl -fsSL https://ollama.com/install.sh|sh; fi
    info "Configurando Ollama..."; mkdir -p /etc/systemd/system/ollama.service.d
    echo -e "[Service]\nExecStart=\nExecStart=/usr/local/bin/ollama serve\nEnvironment=\"OLLAMA_HOST=127.0.0.1\"">/etc/systemd/system/ollama.service.d/override.conf
    systemctl daemon-reload && systemctl restart ollama
    info "Descargando modelo LLM..."; ollama pull phi3; success "Modelo LLM descargado."
}
setup_python_env() {
    info "Configurando entorno virtual de Python..."
    python3 -m venv "${VENV_DIR}"
    source "${VENV_DIR}/bin/activate" && pip install -r "${CONFIG_DIR}/requirements.txt" && deactivate
    success "Entorno virtual de Python configurado."
}
setup_automation() {
    info "Configurando servicio systemd..."
    cat <<EOF >/etc/systemd/system/rag_lab_pro.service
[Unit]
Description=RGIA Pro RAG Stack
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
    systemctl daemon-reload; systemctl enable --now rag_lab_pro.service; success "Servicio systemd habilitado."
}
run_smoke_tests() {
    info "--- Ejecutando Smoke Tests ---"
    info "Esperando 60 segundos para que los servicios se inicien..."
    sleep 60
    local all_ok=true
    if ! docker compose -f "${RAG_LAB_DIR}/docker-compose.yml" ps | grep -q "Up"; then error "Test 1 FAILED: No todos los contenedores están 'Up'."; all_ok=false; else success "Test 1: Contenedores Docker OK."; fi
    local cc_port; cc_port=$(grep CONTROL_CENTER_PORT "${CONFIG_DIR}/.env" | cut -d= -f2)
    if ! curl -fsS "http://127.0.0.1:${cc_port}/" > /dev/null; then error "Test 2 FAILED: Control Center no responde."; all_ok=false; else success "Test 2: Control Center OK."; fi
    if [[ "$all_ok" = false ]]; then error "Algunos smoke tests fallaron."; else success "Todos los smoke tests pasaron."; fi
}

# --- Flujo Principal ---
main() {
    preflight_checks
    info "--- Iniciando Instalación de RGIA Master (Pro) ---"
    generate_files
    source "${CONFIG_DIR}/.env"
    IFS=',' read -ra tenants <<< "$TENANTS"; for t in "${tenants[@]}"; do mkdir -p "${DOCS_DIR_BASE}/${t}"; done
    install_dependencies
    install_docker
    install_ollama
    setup_python_env
    setup_automation
    run_smoke_tests
    success "--- Instalación de RGIA Master (Pro) Finalizada ---"
}

main "$@"
