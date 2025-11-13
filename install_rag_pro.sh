#!/usr/bin/env bash
set -Eeuo pipefail

#
# RGIA MASTER - PRO VERSION INSTALLER
# ==================================
#
# Descripción:
# Este script instala y configura una plataforma RAG (Retrieval-Augmented Generation)
# completa y avanzada sobre sistemas Ubuntu/Debian. Incluye el motor RAG,
# paneles de monitoreo, un Centro de Control web, soporte multi-tenant,
# OCR para documentos escaneados y gestión gráfica de backups.
#
# Idempotente, seguro y diseñado para funcionar en un entorno de CPU.
#
# Autor: Jules, Agente DevOps Senior
# Versión: 2.0 (Pro)
#

# --- Configuración de Logging y Entorno ---
LOG_FILE="/var/log/rag_pro_install.log"
exec > >(tee -a "${LOG_FILE}") 2>&1

# -- Constantes y Colores --
readonly C_GREEN='\033[0;32m'
readonly C_BLUE='\033[0;34m'
readonly C_RED='\033[0;31m'
readonly C_YELLOW='\033[0;33m'
readonly C_NC='\033[0m'

# --- Funciones de Utilidad ---
info() { echo -e "${C_BLUE}[INFO] ${1}${C_NC}"; }
success() { echo -e "${C_GREEN}[SUCCESS] ${1}${C_NC}"; }
warn() { echo -e "${C_YELLOW}[WARNING] ${1}${C_NC}"; }
error() { echo -e "${C_RED}[ERROR] ${1}${C_NC}" >&2; exit 1; }

# --- Chequeos Previos ---
check_root() {
    if [[ "${EUID}" -ne 0 ]]; then
        error "Este script debe ser ejecutado como root o con sudo."
    fi
    info "Chequeo de permisos de root: OK"
}

check_distro() {
    if ! grep -qiE "ubuntu|debian" /etc/os-release; then
        error "Este script está diseñado para Ubuntu o Debian."
    fi
    info "Distribución compatible: OK"
}

# --- Variables y Rutas Principales ---
export RAG_LAB_DIR="/opt/rag_lab_pro"
export CONFIG_DIR="${RAG_LAB_DIR}/config"
export SCRIPTS_DIR="${RAG_LAB_DIR}/scripts"
export VENV_DIR="${RAG_LAB_DIR}/venv"
export LOGS_DIR="${RAG_LAB_DIR}/logs"
export DOCS_DIR_BASE="${RAG_LAB_DIR}/documents"
export BACKUP_DIR="${RAG_LAB_DIR}/backups"
export CONTROL_CENTER_DIR="${RAG_LAB_DIR}/control_center"

# --- Definición de Archivos con Heredocs ---

generate_env_file() {
    info "Generando archivo de configuración .env..."
    mkdir -p "${CONFIG_DIR}"
    cat <<'EOF' > "${CONFIG_DIR}/.env"
# === Red y Puertos ===
OPENWEBUI_PORT=3000
CONTROL_CENTER_PORT=8001
EXPOSE_OLLAMA=false
OLLAMA_BIND=127.0.0.1

# === Modelos y RAG ===
# Modelos disponibles: "phi3", "llama3", "gemma"
LLM_MODEL_CHOICE=phi3
EMBEDDING_MODEL=intfloat/multilingual-e5-small

# === Tenancy (Separación de Datos) ===
TENANTS=default,dev_team

# === Configuración de Servicios ===
FILEBROWSER_USER=admin
FILEBROWSER_PASS=admin
ENABLE_NETDATA=true

# === OCR (Pro) ===
ENABLE_OCR=true
OCR_LANGUAGES=spa
EOF
    success "Archivo .env generado."
}

generate_docker_compose() {
    info "Generando archivo docker-compose.yml..."
    source "${CONFIG_DIR}/.env"
    cat <<EOF > "${RAG_LAB_DIR}/docker-compose.yml"
version: '3.8'

services:
  qdrant:
    image: qdrant/qdrant:v1.9.2
    container_name: rag_pro_qdrant
    restart: unless-stopped
    ports: ["127.0.0.1:6333:6333"]
    volumes: ["${RAG_LAB_DIR}/qdrant_storage:/qdrant/storage"]
    networks: ["rag_net"]

  open-webui:
    image: ghcr.io/open-webui/open-webui:main
    container_name: rag_pro_open_webui
    restart: unless-stopped
    ports: ["${OPENWEBUI_PORT}:8080"]
    volumes: ["${RAG_LAB_DIR}/open_webui_data:/app/backend/data"]
    environment: ['OLLAMA_BASE_URL=http://host.docker.internal:11434']
    extra_hosts: ["host.docker.internal:host-gateway"]
    networks: ["rag_net"]

  filebrowser:
    image: filebrowser/filebrowser:v2
    container_name: rag_pro_filebrowser
    restart: unless-stopped
    ports: ["127.0.0.1:8081:80"]
    volumes: ["${DOCS_DIR_BASE}:/srv"]
    environment: ["FB_USERNAME=\${FILEBROWSER_USER}", "FB_PASSWORD=\${FILEBROWSER_PASS}"]
    networks: ["rag_net"]

  portainer:
    image: portainer/portainer-ce:latest
    container_name: rag_pro_portainer
    restart: unless-stopped
    ports: ["127.0.0.1:9000:9000"]
    volumes: ["/var/run/docker.sock:/var/run/docker.sock", "${RAG_LAB_DIR}/portainer_data:/data"]
    networks: ["rag_net"]

  control-center:
    build:
      context: ${CONTROL_CENTER_DIR}
      dockerfile: Dockerfile
    container_name: rag_pro_control_center
    restart: unless-stopped
    ports: ["127.0.0.1:${CONTROL_CENTER_PORT}:8000"]
    volumes: ["/var/run/docker.sock:/var/run/docker.sock", "${RAG_LAB_DIR}:${RAG_LAB_DIR}", "/var/log:/var/log"]
    environment: ["RAG_LAB_DIR=${RAG_LAB_DIR}", "LOG_FILE=${LOG_FILE}"]
    networks: ["rag_net"]
EOF

    if [[ "${ENABLE_NETDATA}" == "true" ]]; then
        info "Añadiendo Netdata al docker-compose..."
        cat <<'EOF' >> "${RAG_LAB_DIR}/docker-compose.yml"

  netdata:
    image: netdata/netdata:latest
    container_name: rag_pro_netdata
    ports: ["127.0.0.1:19999:19999"]
    volumes: ["/proc:/host/proc:ro", "/sys:/host/sys:ro", "/var/run/docker.sock:/var/run/docker.sock:ro"]
    restart: unless-stopped
    networks: ["rag_net"]
EOF
    fi

    cat <<'EOF' >> "${RAG_LAB_DIR}/docker-compose.yml"

networks:
  rag_net:
    driver: bridge
EOF
    success "Archivo docker-compose.yml generado."
}

generate_control_center_files() {
    info "Generando archivos para el RAG Control Center..."
    mkdir -p "${CONTROL_CENTER_DIR}/templates" "${CONTROL_CENTER_DIR}/static"

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
python-multipart
python-dotenv
subprocess.run
EOF

    cat <<'EOF' > "${CONTROL_CENTER_DIR}/main.py"
import os
import subprocess
from fastapi import FastAPI, Request, Form
from fastapi.responses import HTMLResponse, JSONResponse
from fastapi.templating import Jinja2Templates
from dotenv import load_dotenv

RAG_LAB_DIR = os.getenv("RAG_LAB_DIR", "/opt/rag_lab_pro")
load_dotenv(os.path.join(RAG_LAB_DIR, "config", ".env"))

app = FastAPI()
templates = Jinja2Templates(directory="templates")

def run_script(command):
    try:
        process = subprocess.run(command, capture_output=True, text=True, check=True)
        return {"status": "success", "output": process.stdout}
    except subprocess.CalledProcessError as e:
        return {"status": "error", "output": e.stderr}

@app.get("/", response_class=HTMLResponse)
async def read_root(request: Request):
    tenants = [t.strip() for t in os.getenv("TENANTS", "default").split(',')]
    return templates.TemplateResponse("index.html", {"request": request, "tenants": tenants})

@app.post("/run-ingest")
async def handle_ingest(tenant: str = Form(...)):
    venv_python = os.path.join(RAG_LAB_DIR, "venv/bin/python")
    script = os.path.join(RAG_LAB_DIR, "scripts/ingestion_script.py")
    return JSONResponse(run_script([venv_python, script, "--tenant", tenant]))

@app.post("/api/backups/create")
async def handle_backup():
    script = os.path.join(RAG_LAB_DIR, "scripts/backup.sh")
    return JSONResponse(run_script([script]))

@app.get("/api/backups")
async def list_backups():
    backup_dir = os.path.join(RAG_LAB_DIR, "backups")
    if not os.path.isdir(backup_dir): return {"backups": []}
    files = sorted([f for f in os.listdir(backup_dir) if f.endswith(".tgz")], reverse=True)
    return {"backups": files}
EOF

    cat <<'EOF' > "${CONTROL_CENTER_DIR}/templates/index.html"
<!DOCTYPE html>
<html lang="es">
<head>
    <meta charset="UTF-8">
    <title>RGIA Master - Control Center</title>
    <link href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.3/dist/css/bootstrap.min.css" rel="stylesheet">
</head>
<body>
    <div class="container mt-4">
        <h1>RGIA Master - Control Center</h1>
        <!-- Ingesta -->
        <div class="card mt-3">
            <div class="card-body">
                <h5 class="card-title">Ejecutar Ingesta Manual</h5>
                <form id="ingest-form">
                    <select class="form-select" name="tenant">
                        {% for tenant in tenants %}<option value="{{ tenant }}">{{ tenant }}</option>{% endfor %}
                    </select>
                    <button type="submit" class="btn btn-primary mt-2">Iniciar Ingesta</button>
                </form>
                <pre id="ingest-output" class="mt-2 bg-dark text-white p-2" style="height: 200px; overflow-y: scroll;">Esperando...</pre>
            </div>
        </div>
        <!-- Backups -->
        <div class="card mt-3">
            <div class="card-body">
                <h5 class="card-title">Gestión de Backups</h5>
                <button id="create-backup-btn" class="btn btn-success">Crear Nuevo Backup</button>
                <h6 class="mt-3">Backups Existentes:</h6>
                <ul class="list-group" id="backup-list"></ul>
                <pre id="backup-output" class="mt-2 bg-dark text-white p-2">Esperando...</pre>
            </div>
        </div>
    </div>
    <script>
        document.getElementById('ingest-form').addEventListener('submit', async e => {
            e.preventDefault();
            const out = document.getElementById('ingest-output');
            out.textContent = 'Ejecutando...';
            const res = await fetch('/run-ingest', { method: 'POST', body: new FormData(e.target) });
            const result = await res.json();
            out.textContent = result.status === 'success' ? result.output : 'ERROR:\n' + result.output;
        });

        async function loadBackups() {
            const res = await fetch('/api/backups');
            const data = await res.json();
            const list = document.getElementById('backup-list');
            list.innerHTML = data.backups.length ? data.backups.map(f => `<li class="list-group-item">${f}</li>`).join('') : '<li class="list-group-item">No hay backups.</li>';
        }

        document.getElementById('create-backup-btn').addEventListener('click', async () => {
            const out = document.getElementById('backup-output');
            out.textContent = 'Creando backup...';
            const res = await fetch('/api/backups/create', { method: 'POST' });
            const result = await res.json();
            out.textContent = result.status === 'success' ? result.output : 'ERROR:\n' + result.output;
            loadBackups();
        });
        document.addEventListener('DOMContentLoaded', loadBackups);
    </script>
</body>
</html>
EOF
    success "Archivos del Control Center generados."
}

generate_python_scripts_pro() {
    info "Generando scripts Python (versión Pro)..."
    cat <<'EOF' > "${CONFIG_DIR}/requirements.txt"
llama-index
qdrant-client
pypdf
sentence-transformers
ollama
tenacity
tqdm
requests
python-dotenv
urllib3<2.0
pytesseract
pdf2image
EOF

    cat <<'EOF' > "${SCRIPTS_DIR}/ingestion_script.py"
import os, hashlib, logging, argparse
from pathlib import Path
import pytesseract
from pdf2image import convert_from_path
from llama_index.core import SimpleDirectoryReader, Document
from llama_index.core.node_parser import SentenceSplitter
from llama_index.embeddings.huggingface import HuggingFaceEmbedding
from qdrant_client import QdrantClient, models
from dotenv import load_dotenv
from tqdm import tqdm

logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(message)s')
load_dotenv(dotenv_path=Path(__file__).parent.parent / 'config' / '.env')

RAG_LAB_DIR = Path(os.getenv("RAG_LAB_DIR"))
EMBEDDING_MODEL = os.getenv("EMBEDDING_MODEL")
ENABLE_OCR = os.getenv("ENABLE_OCR", "false").lower() == "true"
OCR_LANGUAGES = os.getenv("OCR_LANGUAGES", "spa")

def ocr_pdf(path):
    try:
        text = "".join(pytesseract.image_to_string(img, lang=OCR_LANGUAGES) for img in convert_from_path(path))
        return text
    except Exception as e:
        logging.error(f"Fallo en OCR para {path}: {e}")
        return ""

def load_docs(path):
    docs = []
    for p in Path(path).rglob('*'):
        if p.suffix in [".pdf", ".txt", ".md"]:
            try:
                loaded = SimpleDirectoryReader(input_files=[p]).load_data()
                if p.suffix == ".pdf" and ENABLE_OCR and (not loaded or not loaded[0].text.strip()):
                    logging.warning(f"PDF sin texto, intentando OCR: {p}")
                    ocr_text = ocr_pdf(p)
                    if ocr_text: docs.append(Document(text=ocr_text, metadata={"source_path": str(p)}))
                else:
                    docs.extend(loaded)
            except Exception as e:
                logging.error(f"Error cargando {p}: {e}")
    return docs

def main(tenant):
    collection = f"rag_coll_{tenant}"
    docs_dir = RAG_LAB_DIR / "documents" / tenant
    client = QdrantClient(host="127.0.0.1", port=6333)
    try: client.get_collection(collection_name=collection)
    except: client.create_collection(collection, vectors_config=models.VectorParams(size=384, distance=models.Distance.COSINE))

    documents = load_docs(docs_dir)
    if not documents: logging.info("No hay documentos nuevos."); return

    nodes = SentenceSplitter(chunk_size=512).get_nodes_from_documents(documents)
    embed_model = HuggingFaceEmbedding(EMBEDDING_MODEL)
    for n in tqdm(nodes, desc="Embeddings"): n.embedding = embed_model.get_text_embedding(n.get_content())

    points = [models.PointStruct(id=hashlib.sha256(n.get_content().encode()).hexdigest(), vector=n.embedding, payload={"text": n.get_content(), "metadata": n.metadata}) for n in nodes]
    client.upsert(collection, points, wait=True)
    logging.info(f"Ingesta para '{tenant}' completada. {len(points)} chunks procesados.")

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--tenant", required=True)
    args = parser.parse_args()
    main(args.tenant)
EOF
    success "Scripts Python (Pro) generados."
}

generate_helper_scripts_pro() {
    info "Generando scripts de ayuda (Pro)..."
    cat <<'EOF' > "${SCRIPTS_DIR}/backup.sh"
#!/usr/bin/env bash
set -euo pipefail
RAG_LAB_DIR="/opt/rag_lab_pro"
BACKUP_DIR="${RAG_LAB_DIR}/backups"
FILE="${BACKUP_DIR}/backup_$(date +"%Y-%m-%d_%H%M%S").tgz"
mkdir -p "${BACKUP_DIR}"
echo "Deteniendo servicios..."
systemctl stop rag_lab_pro
echo "Creando backup en ${FILE}..."
tar --exclude="${BACKUP_DIR}" -czvf "${FILE}" -C "$(dirname ${RAG_LAB_DIR})" "$(basename ${RAG_LAB_DIR})"
echo "Reiniciando servicios..."
systemctl start rag_lab_pro
echo "Backup completado."
EOF
    chmod +x "${SCRIPTS_DIR}/backup.sh"
    success "Scripts de ayuda (Pro) generados."
}

# --- Lógica de Instalación ---
install_dependencies_pro() {
    info "Instalando dependencias del sistema (incluyendo Tesseract para OCR)..."
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -y
    apt-get install -y ca-certificates curl gnupg lsb-release htop python3 python3-venv python3-pip git tesseract-ocr poppler-utils
    success "Dependencias (Pro) instaladas."
}

install_docker() {
    if ! command -v docker &> /dev/null; then
        info "Instalando Docker Engine..."
        install -m 0755 -d /etc/apt/keyrings
        curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
        chmod a+r /etc/apt/keyrings/docker.gpg
        echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" > /etc/apt/sources.list.d/docker.list
        apt-get update -y
        apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
        systemctl enable --now docker
        success "Docker Engine instalado."
    else
        info "Docker ya está instalado."
    fi
}

install_ollama_pro() {
    if ! command -v ollama &> /dev/null; then
        info "Instalando Ollama..."
        curl -fsSL https://ollama.com/install.sh | sh
    else
        info "Ollama ya está instalado."
    fi
    source "${CONFIG_DIR}/.env"
    mkdir -p /etc/systemd/system/ollama.service.d
    echo -e "[Service]\nExecStart=\nExecStart=/usr/local/bin/ollama serve\nEnvironment=\"OLLAMA_HOST=${OLLAMA_BIND}\"" > /etc/systemd/system/ollama.service.d/override.conf
    systemctl daemon-reload && systemctl restart ollama

    LLM_MODELS=("phi3:3.8b-mini-4k-instruct-q4_K_M" "llama3:8b-instruct-q4_K_M" "gemma:7b-instruct-q4_K_M")
    OLLAMA_MODEL_NAME=${LLM_MODELS[0]}
    if [[ "${LLM_MODEL_CHOICE}" == "llama3" ]]; then OLLAMA_MODEL_NAME=${LLM_MODELS[1]}; fi
    if [[ "${LLM_MODEL_CHOICE}" == "gemma" ]]; then OLLAMA_MODEL_NAME=${LLM_MODELS[2]}; fi

    info "Descargando modelo LLM: ${OLLAMA_MODEL_NAME}..."
    ollama pull "${OLLAMA_MODEL_NAME}"
    success "Modelo LLM descargado."
}

setup_python_env_pro() {
    info "Configurando entorno virtual Python (Pro)..."
    python3 -m venv "${VENV_DIR}"
    source "${VENV_DIR}/bin/activate"
    pip install -r "${CONFIG_DIR}/requirements.txt"
    deactivate
    success "Entorno virtual Python (Pro) configurado."
}

setup_automation_pro() {
    info "Configurando servicio systemd 'rag_lab_pro'..."
    cat <<EOF > /etc/systemd/system/rag_lab_pro.service
[Unit]
Description=RGIA Pro RAG Stack
After=docker.service network-online.target ollama.service
Requires=docker.service ollama.service
[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=${RAG_LAB_DIR}
ExecStart=/usr/bin/docker compose up -d --build
ExecStop=/usr/bin/docker compose down
[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable --now rag_lab_pro.service
    success "Servicio systemd 'rag_lab_pro' habilitado."

    info "Configurando cron para ingesta multi-tenant..."
    rm -f /etc/cron.d/rag_pro_ingest
    source "${CONFIG_DIR}/.env"
    IFS=',' read -ra TENANTS_ARRAY <<< "$TENANTS"
    for tenant in "${TENANTS_ARRAY[@]}"; do
        echo "0 3 * * * root ${VENV_DIR}/bin/python ${SCRIPTS_DIR}/ingestion_script.py --tenant ${tenant} >> /var/log/rag_pro_ingest_${tenant}.log 2>&1" >> /etc/cron.d/rag_pro_ingest
    done
    success "Trabajos de cron configurados."
}

run_smoke_tests_pro() {
    info "--- Ejecutando Smoke Tests (Pro) ---"
    source "${CONFIG_DIR}/.env"
    # 1. Control Center
    if curl -fsS http://127.0.0.1:${CONTROL_CENTER_PORT} > /dev/null; then success "Test 1: Control Center está respondiendo."; else error "Test 1: FAILED. Control Center no responde."; fi
    # 2. Ingesta de prueba
    info "Ejecutando ingesta de prueba para tenant 'default'..."
    if sudo "${VENV_DIR}/bin/python" "${SCRIPTS_DIR}/ingestion_script.py" --tenant default; then success "Test 2: Ingesta de prueba completada."; else error "Test 2: FAILED. La ingesta de prueba falló."; fi
}

# --- Flujo de Instalación Principal ---
main() {
    check_root
    check_distro

    info "--- Iniciando Instalación de RGIA MASTER (Pro) ---"

    mkdir -p "${RAG_LAB_DIR}" "${DOCS_DIR_BASE}" "${LOGS_DIR}" "${BACKUP_DIR}"

    generate_env_file
    source "${CONFIG_DIR}/.env"
    IFS=',' read -ra TENANTS_ARRAY <<< "$TENANTS"
    for tenant in "${TENANTS_ARRAY[@]}"; do
        mkdir -p "${DOCS_DIR_BASE}/${tenant}"
        touch "${DOCS_DIR_BASE}/${tenant}/ejemplo.txt" && echo "Doc para ${tenant}" > "${DOCS_DIR_BASE}/${tenant}/ejemplo.txt"
    done

    generate_docker_compose
    generate_control_center_files
    generate_python_scripts_pro
    generate_helper_scripts_pro

    install_dependencies_pro
    install_docker
    install_ollama_pro
    setup_python_env_pro
    setup_automation_pro

    run_smoke_tests_pro

    success "--- Instalación de RGIA MASTER (Pro) finalizada ---"
    IP_ADDR=$(hostname -I | awk '{print $1}')
    echo -e "\n${C_GREEN}Plataforma Pro lista. Endpoints:${C_NC}"
    echo -e "- Open WebUI (Chat):      ${C_YELLOW}http://${IP_ADDR}:${OPENWEBUI_PORT}${C_NC}"
    echo -e "- RGIA Control Center:    ${C_YELLOW}http://127.0.0.1:${CONTROL_CENTER_PORT}${C_NC}"
    echo -e "- Filebrowser (Archivos): ${C_YELLOW}http://127.0.0.1:8081${C_NC}"
    echo -e "- Portainer (Docker):     ${C_YELLOW}http://127.0.0.1:9000${C_NC}"
}

main "$@"
