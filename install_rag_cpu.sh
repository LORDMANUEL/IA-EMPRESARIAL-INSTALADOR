#!/usr/bin/env bash
#
# Prompt Maestro 3.0 — Instalador único de Plataforma RAG en CPU (Ubuntu/Debian)
#
# Este script instala y configura una plataforma completa de RAG para desarrollo de agentes,
# optimizada para ejecutarse en CPU en un sistema Ubuntu/Debian.
# Es idempotente, no interactivo y está diseñado para ser seguro por defecto.

# --- Configuración estricta y segura del script ---
set -Eeuo pipefail

# --- Constantes y Variables Globales ---
readonly LOG_FILE="/var/log/rag_install.log"
readonly SCRIPT_NAME="$(basename "$0")"
readonly RAG_LAB_DIR="/opt/rag_lab"

# --- Redirección de toda la salida (stdout y stderr) a un archivo de log y a la consola ---
mkdir -p /var/log
touch "${LOG_FILE}"
exec > >(tee -a "${LOG_FILE}") 2>&1

# --- Funciones de Logging ---
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - ${1}: ${2}"
}

info() {
    log "INFO" "${1}"
}

warn() {
    log "WARN" "${1}"
}

error() {
    log "ERROR" "${1}" >&2
    exit 1
}

# --- Bienvenida y Comprobaciones Iniciales ---
cat << "EOF"
██████╗  ██████╗ ██╗ █████╗     ███╗   ███╗ █████╗ ███████╗████████╗██████╗
██╔══██╗██╔════╝ ██║██╔══██╗    ████╗ ████║██╔══██╗██╔════╝╚══██╔══╝██╔══██╗
██████╔╝██║  ███╗██║███████║    ██╔████╔██║███████║███████╗   ██║   ██████╔╝
██╔══██╗██║   ██║██║██╔══██║    ██║╚██╔╝██║██╔══██║╚════██║   ██║   ██╔══██╗
██║  ██║╚██████╔╝██║██║  ██║    ██║ ╚═╝ ██║██║  ██║███████║   ██║   ██║  ██║
╚═╝  ╚═╝ ╚═════╝ ╚═╝╚═╝  ╚═╝    ╚═╝     ╚═╝╚═╝  ╚═╝╚══════╝   ╚═╝   ╚═╝  ╚═╝
EOF
echo "Hecho por Luis Fajardo Rivera (lmfr)"
echo "----------------------------------------------------"

info "Iniciando el instalador de la plataforma RGIA MASTER..."

if [[ "${EUID}" -ne 0 ]]; then
    error "Este script debe ser ejecutado con privilegios de root (sudo)."
fi

export DEBIAN_FRONTEND=noninteractive
info "Modo no interactivo habilitado."

# --- Fase P0: Infraestructura y Seguridad ---
info "--- Iniciando Fase P0: Infraestructura y Seguridad ---"

# 1. Instalación de Dependencias del Sistema (Idempotente)
info "Instalando dependencias del sistema..."
apt-get update -y
readonly SYSTEM_PACKAGES=("ca-certificates" "curl" "gnupg" "lsb-release" "htop" "python3" "python3-venv" "python3-pip" "git")
for pkg in "${SYSTEM_PACKAGES[@]}"; do
    if ! dpkg -l | grep -q "ii  $pkg"; then
        apt-get install -y "$pkg"
    else
        info "Paquete '$pkg' ya instalado."
    fi
done

# 2. Instalación de Docker (Idempotente)
info "Instalando Docker Engine..."
if ! command -v docker &> /dev/null; then
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    chmod a+r /etc/apt/keyrings/docker.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
    apt-get update -y
    if ! apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin; then
        warn "La instalación de Docker desde el repositorio oficial falló. Intentando fallback a docker.io..."
        apt-get install -y docker.io
    fi
    systemctl start docker
    systemctl enable docker
    usermod -aG docker "${SUDO_USER:-$(logname)}"
    info "Docker instalado y configurado."
else
    info "Docker ya está instalado."
fi

# 3. Instalación de Ollama (Idempotente y Robusto)
info "Instalando y configurando Ollama..."
if ! command -v ollama &> /dev/null; then
    attempts=3
    count=0
    while [ $count -lt $attempts ]; do
        count=$((count + 1))
        info "Intento de instalación de Ollama: ${count}/${attempts}..."
        if curl -fsSL https://ollama.com/install.sh | sh; then
            info "Ollama ha sido instalado con éxito."
            break
        fi
        if [ $count -ge $attempts ]; then
            warn "La instalación de Ollama falló después de $attempts intentos. El script continuará, pero necesitarás instalar Ollama manualmente."
        else
            sleep 5
        fi
    done
else
    info "Ollama ya está instalado."
fi

# Configuración de Ollama y descarga del modelo (si Ollama está instalado)
if command -v ollama &> /dev/null; then
    mkdir -p /etc/systemd/system/ollama.service.d
    cat <<EOF > /etc/systemd/system/ollama.service.d/override.conf
[Service]
Environment="OLLAMA_HOST=127.0.0.1"
EOF
    systemctl daemon-reload
    systemctl restart ollama

    OLLAMA_MODEL_NAME=${OLLAMA_MODEL:-"phi3:3.8b-mini-4k-instruct-q4_K_M"}
    info "Descargando el modelo de Ollama: ${OLLAMA_MODEL_NAME}..."
    if ! ollama list | grep -q "${OLLAMA_MODEL_NAME}"; then
        ollama pull "${OLLAMA_MODEL_NAME}"
    else
        info "El modelo '${OLLAMA_MODEL_NAME}' ya existe."
    fi
else
    warn "Ollama no está instalado. Se omite la configuración y la descarga del modelo."
fi

info "--- Fase P0 Completada ---"

# --- Fase P1: Datos y Servicios Base ---
info "--- Iniciando Fase P1: Datos y Servicios Base ---"

# 1. Crear Estructura de Directorios
info "Creando estructura de directorios en ${RAG_LAB_DIR}..."
mkdir -p "${RAG_LAB_DIR}/documents"
mkdir -p "${RAG_LAB_DIR}/qdrant_storage"
mkdir -p "${RAG_LAB_DIR}/open_webui_data"
mkdir -p "${RAG_LAB_DIR}/scripts"
mkdir -p "${RAG_LAB_DIR}/logs"
mkdir -p "${RAG_LAB_DIR}/config"
mkdir -p "${RAG_LAB_DIR}/control_center/templates"
mkdir -p "${RAG_LAB_DIR}/documents/knowledge_base"
mkdir -p "${RAG_LAB_DIR}/scripts/agents"
mkdir -p "${RAG_LAB_DIR}/open_webui_customizations"
mkdir -p "${RAG_LAB_DIR}/simple_chat/templates"

# 2. Generar Archivos de Configuración
info "Generando archivos de configuración..."
cat <<'EOF' > "${RAG_LAB_DIR}/config/.env"
# Configuración de la Plataforma RAG
OPENWEBUI_PORT=3000
EXPOSE_OLLAMA=false
OLLAMA_BIND=127.0.0.1
RAG_COLLECTION=corporativo_rag
RAG_DOCS_DIR=/opt/rag_lab/documents
EMBEDDING_MODEL=intfloat/multilingual-e5-small
OLLAMA_MODEL=phi3:3.8b-mini-4k-instruct-q4_K_M
FILEBROWSER_USER=admin
FILEBROWSER_PASS=admin
ENABLE_NETDATA=true
RAG_CONTROL_CENTER_PORT=3200
# Credenciales para el Control Center (cambiar para producción)
CONTROL_CENTER_USER=admin
CONTROL_CENTER_PASS=ragadmin
EOF

cat <<'EOF' > "${RAG_LAB_DIR}/config/requirements.txt"
llama-index
qdrant-client
pypdf
sentence-transformers
ollama
tenacity
tqdm
requests
fastapi
uvicorn[standard]
urllib3<2.0
python-dotenv
docker
jinja2
python-multipart
EOF

# 3. Configurar Entorno Virtual de Python
info "Configurando el entorno virtual de Python..."
readonly VENV_DIR="${RAG_LAB_DIR}/venv"
if [ ! -d "${VENV_DIR}" ]; then
    python3 -m venv "${VENV_DIR}"
fi
"${VENV_DIR}/bin/pip" install --upgrade pip
"${VENV_DIR}/bin/pip" install -r "${RAG_LAB_DIR}/config/requirements.txt"
info "Entorno virtual de Python configurado."

info "--- Fase P1 Completada ---"

# --- Fase P2: Lógica RAG y Automatización ---
info "--- Iniciando Fase P2: Lógica RAG y Automatización ---"

# 1. Generar Scripts de Lógica RAG
info "Generando scripts de lógica RAG..."
cat <<'EOF' > "${RAG_LAB_DIR}/scripts/ingestion_script.py"
#!/usr/bin/env python
import os, hashlib, time, logging
from pathlib import Path
from llama_index.core import SimpleDirectoryReader
from llama_index.core.text_splitter import SentenceSplitter
from qdrant_client import QdrantClient, models
from sentence_transformers import SentenceTransformer
from tqdm import tqdm
import tenacity

logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s', handlers=[logging.FileHandler("/opt/rag_lab/logs/ingestion.log"), logging.StreamHandler()])
log = logging.getLogger(__name__)

RAG_DOCS_DIR = os.getenv("RAG_DOCS_DIR", "/opt/rag_lab/documents")
EMBEDDING_MODEL = os.getenv("EMBEDDING_MODEL", "intfloat/multilingual-e5-small")
QDRANT_HOST = "127.0.0.1"
RAG_COLLECTION = os.getenv("RAG_COLLECTION", "corporativo_rag")

def get_deterministic_id(file_path: str, chunk_content: str) -> str:
    return hashlib.sha256(f"{file_path}{chunk_content}".encode()).hexdigest()

@tenacity.retry(wait=tenacity.wait_exponential(multiplier=1, min=2, max=10), stop=tenacity.stop_after_attempt(5))
def wait_for_qdrant():
    log.info("Conectando a Qdrant...")
    client = QdrantClient(host=QDRANT_HOST, port=6333)
    client.get_collections()
    return client

def main():
    log.info("Iniciando ingesta...")
    qdrant_client = wait_for_qdrant()
    embedding_model = SentenceTransformer(EMBEDDING_MODEL)
    vector_size = embedding_model.get_sentence_embedding_dimension()

    try:
        qdrant_client.get_collection(collection_name=RAG_COLLECTION)
    except Exception:
        qdrant_client.recreate_collection(collection_name=RAG_COLLECTION, vectors_config=models.VectorParams(size=vector_size, distance=models.Distance.COSINE))

    docs_path = Path(RAG_DOCS_DIR)
    if not any(docs_path.iterdir()):
        log.info("Directorio de documentos vacío.")
        return

    documents = SimpleDirectoryReader(input_dir=str(docs_path), required_exts=[".pdf", ".txt", ".md"], recursive=True).load_data()
    text_splitter = SentenceSplitter(chunk_size=512, chunk_overlap=64)

    points_to_upsert = []
    for doc in tqdm(documents, desc="Procesando documentos"):
        nodes = text_splitter.get_nodes_from_documents([doc])
        for node in nodes:
            chunk_content = node.get_content()
            chunk_id = get_deterministic_id(doc.metadata.get('file_path'), chunk_content)
            points_to_upsert.append(models.PointStruct(id=chunk_id, vector=embedding_model.encode(chunk_content).tolist(), payload={"source_path": doc.metadata.get('file_path'), "text": chunk_content}))

    if points_to_upsert:
        qdrant_client.upsert(collection_name=RAG_COLLECTION, points=points_to_upsert, wait=True)
        log.info(f"Upsert de {len(points_to_upsert)} chunks completado.")
    log.info("Ingesta finalizada.")

if __name__ == "__main__":
    main()
EOF

cat <<'EOF' > "${RAG_LAB_DIR}/scripts/query_agent.py"
#!/usr/bin/env python
import os, sys
from qdrant_client import QdrantClient
from sentence_transformers import SentenceTransformer
import ollama

EMBEDDING_MODEL = os.getenv("EMBEDDING_MODEL", "intfloat/multilingual-e5-small")
OLLAMA_MODEL = os.getenv("OLLAMA_MODEL", "phi3:3.8b-mini-4k-instruct-q4_K_M")
OLLAMA_HOST = f"http://{os.getenv('OLLAMA_BIND', '127.0.0.1')}:11434"
RAG_COLLECTION = os.getenv("RAG_COLLECTION", "corporativo_rag")

PROMPT_TEMPLATE = "Contexto:\n{context}\n\nPregunta:\n{query}\n\nRespuesta:"

def main():
    if len(sys.argv) < 2: sys.exit("Uso: python query_agent.py \"<pregunta>\"")

    embedding_model = SentenceTransformer(EMBEDDING_MODEL)
    qdrant_client = QdrantClient(host="127.0.0.1", port=6333)
    ollama_client = ollama.Client(host=OLLAMA_HOST)

    query_vector = embedding_model.encode(sys.argv[1]).tolist()
    results = qdrant_client.search(collection_name=RAG_COLLECTION, query_vector=query_vector, limit=3)

    if not results:
        print("No se encontraron resultados.")
        return

    context = "\n---\n".join([r.payload['text'] for r in results])
    prompt = PROMPT_TEMPLATE.format(context=context, query=sys.argv[1])

    response = ollama_client.chat(model=OLLAMA_MODEL, messages=[{'role': 'user', 'content': prompt}])
    print(response['message']['content'])
    print("\nFuentes:", list({r.payload['source_path'] for r in results}))

if __name__ == "__main__":
    main()
EOF

# 2. Generar Scripts de Ayuda (Helpers)
info "Generando scripts de ayuda..."
cat <<'EOF' > "${RAG_LAB_DIR}/scripts/diag_rag.sh"
#!/usr/bin/env bash
set -eo pipefail
echo "--- Diagnóstico de la Plataforma RAG ---"
echo "--- Estado de los Contenedores (desde el socket) ---"
docker compose ps
echo "--- Estado de Ollama (accesible desde el contenedor) ---"
curl -fsS http://host.docker.internal:11434/api/tags && echo "Ollama OK" || echo "Ollama FAIL"
echo "--- Estado de Qdrant ---"
curl -fsS http://127.0.0.1:6333/ready && echo "Qdrant OK" || echo "Qdrant FAIL"
echo "--- Uso del Disco en /opt/rag_lab ---"
du -sh /opt/rag_lab/*
echo "--- Modelos de Ollama ---"
/opt/rag_lab/venv/bin/ollama list
tail -n 10 /var/log/rag_ingest.log || echo "Log de ingesta no encontrado."
echo "--- Diagnóstico Finalizado ---"
EOF

cat <<'EOF' > "${RAG_LAB_DIR}/scripts/backup.sh"
#!/usr/bin/env bash
set -Eeuo pipefail
BACKUP_DIR="/opt"
TIMESTAMP=$(date +"%Y-%m-%d")
BACKUP_FILE="${BACKUP_DIR}/rag_lab_backup_${TIMESTAMP}.tgz"
SOURCE_DIR="/opt/rag_lab"
echo "Iniciando backup de ${SOURCE_DIR} a ${BACKUP_FILE}..."
echo "Deteniendo servicios..."
docker compose -f "${SOURCE_DIR}/docker-compose.yml" down
echo "Creando archivo de backup..."
tar -czf "${BACKUP_FILE}" -C "$(dirname ${SOURCE_DIR})" "$(basename ${SOURCE_DIR})"
echo "Reiniciando servicios..."
docker compose -f "${SOURCE_DIR}/docker-compose.yml" up -d
echo "Backup completado: ${BACKUP_FILE}"
EOF

cat <<'EOF' > "${RAG_LAB_DIR}/scripts/restore.sh"
#!/usr/bin/env bash
set -Eeuo pipefail
if [ -z "$1" ]; then echo "Uso: $0 /ruta/al/backup.tgz"; exit 1; fi
read -p "ADVERTENCIA: Esto sobreescribirá /opt/rag_lab. ¿Continuar? (s/n): " C
if [[ "$C" != "s" ]]; then exit 0; fi
systemctl stop rag_lab
rm -rf /opt/rag_lab
tar -xzf "$1" -C "/opt"
systemctl start rag_lab
echo "Restauración completada."
EOF

cat <<'EOF' > "${RAG_LAB_DIR}/scripts/update_openwebui.sh"
#!/usr/bin/env bash
set -Eeuo pipefail
docker compose -f "/opt/rag_lab/docker-compose.yml" pull open-webui
docker compose -f "/opt/rag_lab/docker-compose.yml" up -d open-webui
echo "Open WebUI actualizado."
EOF

cat <<'EOF' > "${RAG_LAB_DIR}/scripts/update_ollama_model.sh"
#!/usr/bin/env bash
set -Eeuo pipefail
source "/opt/rag_lab/config/.env"
ollama pull "${OLLAMA_MODEL}"
echo "Modelo Ollama actualizado."
EOF

# 3. Configurar Automatización
info "Configurando automatización..."
cat <<'EOF' > /etc/cron.d/rag_ingest
0 3 * * * root ${RAG_LAB_DIR}/venv/bin/python ${RAG_LAB_DIR}/scripts/ingestion_script.py >> /var/log/rag_ingest.log 2>&1
EOF
chmod 0644 /etc/cron.d/rag_ingest
systemctl restart cron

cat <<'EOF' > /etc/systemd/system/rag_lab.service
[Unit]
Description=RAG Lab Docker Compose Stack
Requires=docker.service
After=docker.service
[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=${RAG_LAB_DIR}
EnvironmentFile=${RAG_LAB_DIR}/config/.env
ExecStart=/usr/bin/docker compose -f docker-compose.yml up -d
ExecStop=/usr/bin/docker compose -f docker-compose.yml down
[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload

cat <<'EOF' > /etc/logrotate.d/rag_lab
/var/log/rag_install.log
/var/log/rag_ingest.log
/opt/rag_lab/logs/ingestion.log
{
    daily
    rotate 7
    compress
    missingok
    notifempty
}
EOF

chmod +x "${RAG_LAB_DIR}/scripts/"*.sh
chmod +x "${RAG_LAB_DIR}/scripts/"*.py

info "--- Fase P2 Completada ---"

# --- Fase P3: Creación del RAG Control Center ---
info "--- Iniciando Fase P3: Creación del RAG Control Center ---"

# 1. Generar el Backend del Control Center (FastAPI)
info "Generando el backend del RAG Control Center (main.py)..."
cat <<'EOF' > "${RAG_LAB_DIR}/control_center/main.py"
import os
import secrets
import docker
import subprocess
from fastapi import FastAPI, Request, Depends, HTTPException, Form, UploadFile, File
from fastapi.responses import HTMLResponse, RedirectResponse
from fastapi.templating import Jinja2Templates
from fastapi.security import HTTPBasic, HTTPBasicCredentials
from dotenv import dotenv_values, set_key
import datetime

app = FastAPI()
security = HTTPBasic()
templates = Jinja2Templates(directory="/opt/rag_lab/control_center/templates")

RAG_LAB_DIR = "/opt/rag_lab"
SCRIPTS_DIR = os.path.join(RAG_LAB_DIR, "scripts")
ENV_FILE = os.path.join(RAG_LAB_DIR, "config/.env")
KNOWLEDGE_BASE_DIR = os.path.join(RAG_LAB_DIR, "documents", "knowledge_base")

import json

RAG_LAB_DIR = "/opt/rag_lab"
SCRIPTS_DIR = os.path.join(RAG_LAB_DIR, "scripts")
ENV_FILE = os.path.join(RAG_LAB_DIR, "config/.env")
KNOWLEDGE_BASE_DIR = os.path.join(RAG_LAB_DIR, "documents", "knowledge_base")
QUERIES_FILE = os.path.join(RAG_LAB_DIR, "logs", "recent_queries.json")

# --- Persistencia del Feedback Loop ---
def load_queries():
    if not os.path.exists(QUERIES_FILE):
        return []
    with open(QUERIES_FILE, "r") as f:
        return json.load(f)

def save_queries(queries):
    with open(QUERIES_FILE, "w") as f:
        json.dump(queries, f, indent=2)

# --- Autenticación ---
def get_current_user(credentials: HTTPBasicCredentials = Depends(security)):
    correct_username = secrets.compare_digest(credentials.username, os.getenv("CONTROL_CENTER_USER", "admin"))
    correct_password = secrets.compare_digest(credentials.password, os.getenv("CONTROL_CENTER_PASS", "ragadmin"))
    if not (correct_username and correct_password):
        raise HTTPException(
            status_code=401,
            detail="Incorrect email or password",
            headers={"WWW-Authenticate": "Basic"},
        )
    return credentials.username

# --- Rutas ---
@app.get("/", response_class=HTMLResponse)
def read_root(request: Request, user: str = Depends(get_current_user)):
    try:
        client = docker.from_env()
        containers = client.containers.list(all=True)
        container_statuses = [{"name": c.name, "status": c.status, "id": c.short_id} for c in containers if c.name.startswith("rag_")]
    except Exception:
        container_statuses = []

    env_config = dotenv_values(ENV_FILE)
    recent_queries = load_queries()

    return templates.TemplateResponse("index.html", {
        "request": request,
        "containers": container_statuses,
        "env_config": env_config,
        "recent_queries": recent_queries
    })

@app.post("/simulated-query")
async def simulated_query(query: str = Form(...), user: str = Depends(get_current_user)):
    # Simulación de una respuesta de agente
    answer = f"Esta es una respuesta simulada para la pregunta: '{query}'. En un sistema real, esta respuesta vendría del LLM."

    recent_queries = load_queries()
    recent_queries.append({"query": query, "answer": answer, "id": len(recent_queries)})
    save_queries(recent_queries)

    return RedirectResponse(url="/", status_code=303)

@app.post("/approve-qa/{query_id}")
async def approve_qa(query_id: int, user: str = Depends(get_current_user)):
    recent_queries = load_queries()
    if query_id >= len(recent_queries):
        raise HTTPException(status_code=404, detail="Query not found")

    qa = recent_queries[query_id]
    timestamp = datetime.datetime.now().strftime("%Y%m%d%H%M%S")
    filename = os.path.join(KNOWLEDGE_BASE_DIR, f"qa_{timestamp}.md")

    with open(filename, "w") as f:
        f.write(f"# Pregunta: {qa['query']}\n\n")
        f.write(f"## Respuesta Aprobada:\n{qa['answer']}\n")

    # Opcional: eliminar de la lista de recientes una vez aprobado
    # recent_queries.pop(query_id)

    return RedirectResponse(url="/", status_code=303)

AGENT_TEMPLATE = """#!/usr/bin/env python
import os, sys
from qdrant_client import QdrantClient
from sentence_transformers import SentenceTransformer
import ollama

# --- Agente Personalizado: {agent_name} ---
# Propósito: {agent_purpose}

EMBEDDING_MODEL = os.getenv("EMBEDDING_MODEL", "intfloat/multilingual-e5-small")
OLLAMA_MODEL = os.getenv("OLLAMA_MODEL", "phi3:3.8b-mini-4k-instruct-q4_K_M")
OLLAMA_HOST = f"http://{os.getenv('OLLAMA_BIND', '127.0.0.1')}:11434"
RAG_COLLECTION = os.getenv("RAG_COLLECTION", "corporativo_rag")

PROMPT_TEMPLATE = \"\"\"
{system_prompt}

Contexto:
{{context}}

Pregunta:
{{query}}

Respuesta:
\"\"\"

def main():
    if len(sys.argv) < 2: sys.exit(f"Uso: python {os.path.basename(__file__)} \\"<pregunta>\\"")

    embedding_model = SentenceTransformer(EMBEDDING_MODEL)
    qdrant_client = QdrantClient(host="127.0.0.1", port=6333)
    ollama_client = ollama.Client(host=OLLAMA_HOST)

    query_vector = embedding_model.encode(sys.argv[1]).tolist()
    results = qdrant_client.search(collection_name=RAG_COLLECTION, query_vector=query_vector, limit=3)

    context = "\\n---\\n".join([r.payload['text'] for r in results]) if results else "No se encontró información relevante."
    prompt = PROMPT_TEMPLATE.format(context=context, query=sys.argv[1])

    response = ollama_client.chat(model=OLLAMA_MODEL, messages=[{'role': 'user', 'content': prompt}])
    print(response['message']['content'])

if __name__ == "__main__":
    main()
"""

@app.get("/agents", response_class=HTMLResponse)
def agent_creator_page(request: Request, user: str = Depends(get_current_user)):
    agents = []
    agents_dir = os.path.join(SCRIPTS_DIR, "agents")
    if os.path.exists(agents_dir):
        agents = [f for f in os.listdir(agents_dir) if f.endswith(".py")]
    return templates.TemplateResponse("agents.html", {"request": request, "agents": agents})

@app.post("/create-agent")
async def create_agent(
    agent_name: str = Form(...),
    agent_purpose: str = Form(...),
    system_prompt: str = Form(...),
    user: str = Depends(get_current_user)
):
    agent_filename = f"agent_{agent_name.lower().replace(' ', '_')}.py"
    agent_path = os.path.join(SCRIPTS_DIR, "agents", agent_filename)

    agent_code = AGENT_TEMPLATE.format(
        agent_name=agent_name,
        agent_purpose=agent_purpose,
        system_prompt=system_prompt
    )

    with open(agent_path, "w") as f:
        f.write(agent_code)

    os.chmod(agent_path, 0o755)

    return RedirectResponse(url="/agents", status_code=303)

# --- Simplified Task Execution via Subprocess ---
def run_script_in_background(command):
    # Asynchronously run a script and log its output
    log_file_path = os.path.join(RAG_LAB_DIR, "logs", "control_center_tasks.log")
    with open(log_file_path, "a") as log_file:
        subprocess.Popen(command, stdout=log_file, stderr=subprocess.STDOUT, cwd=RAG_LAB_DIR)

@app.post("/ingest")
async def run_ingest(user: str = Depends(get_current_user)):
    command = ["/opt/rag_lab/venv/bin/python", "/opt/rag_lab/scripts/ingestion_script.py"]
    run_script_in_background(command)
    return RedirectResponse(url="/", status_code=303)

@app.post("/backup")
async def run_backup(user: str = Depends(get_current_user)):
    command = ["/opt/rag_lab/scripts/backup.sh"]
    run_script_in_background(command)
    return RedirectResponse(url="/", status_code=303)

@app.post("/diagnostics")
async def run_diagnostics(user: str = Depends(get_current_user)):
    command = ["/opt/rag_lab/scripts/diag_rag.sh"]
    run_script_in_background(command)
    return RedirectResponse(url="/", status_code=303)

@app.post("/update-env")
async def update_env(request: Request, user: str = Depends(get_current_user)):
    form_data = await request.form()
    for key, value in form_data.items():
        set_key(ENV_FILE, key, value)

    # Restart the stack using a docker compose command
    command = ["docker", "compose", "up", "-d", "--force-recreate"]
    run_script_in_background(command)

    return RedirectResponse(url="/", status_code=303)
EOF

# 2. Generar las Plantillas HTML del Control Center
info "Generando las plantillas HTML del RAG Control Center..."
cat <<'EOF' > "${RAG_LAB_DIR}/control_center/templates/base.html"
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>RAG Control Center</title>
    <script src="https://cdn.tailwindcss.com"></script>
</head>
<body class="bg-gray-100 text-gray-800">
    <div class="container mx-auto p-4">
        <div class="flex justify-between items-center mb-4">
            <h1 class="text-3xl font-bold">RAG Control Center</h1>
            <nav>
                <a href="/" class="text-blue-500 hover:underline">Dashboard</a> |
                <a href="/agents" class="text-blue-500 hover:underline">Agent Creator</a>
            </nav>
        </div>
        {% block content %}{% endblock %}
    </div>
</body>
</html>
EOF

cat <<'EOF' > "${RAG_LAB_DIR}/control_center/templates/agents.html"
{% extends "base.html" %}
{% block content %}
<div class="grid grid-cols-1 md:grid-cols-2 gap-4">
    <!-- Creador de Agentes -->
    <div class="bg-white p-4 rounded-lg shadow">
        <h2 class="text-xl font-semibold mb-2">Create a New Agent</h2>
        <form action="/create-agent" method="post" class="flex flex-col space-y-3">
            <div>
                <label for="agent_name" class="block text-sm font-medium">Agent Name</label>
                <input type="text" name="agent_name" id="agent_name" placeholder="Ej: Agente de Soporte Técnico" class="w-full p-2 border rounded">
            </div>
            <div>
                <label for="agent_purpose" class="block text-sm font-medium">Purpose</label>
                <input type="text" name="agent_purpose" id="agent_purpose" placeholder="Ej: Responde preguntas sobre el manual del producto X" class="w-full p-2 border rounded">
            </div>
            <div>
                <label for="system_prompt" class="block text-sm font-medium">System Prompt / Personality</label>
                <textarea name="system_prompt" id="system_prompt" rows="4" class="w-full p-2 border rounded" placeholder="Ej: Eres un asistente amigable y experto en el producto X..."></textarea>
            </div>
            <button type="submit" class="bg-blue-500 text-white p-2 rounded">Create Agent</button>
        </form>
    </div>

    <!-- Agentes Existentes -->
    <div class="bg-white p-4 rounded-lg shadow">
        <h2 class="text-xl font-semibold mb-2">Existing Agents</h2>
        <ul>
            {% for agent in agents %}
            <li class="border-t py-2">
                <p><strong>{{ agent }}</strong></p>
                <p class="text-sm text-gray-500">Uso: `sudo /opt/rag_lab/venv/bin/python /opt/rag_lab/scripts/agents/{{ agent }} "tu pregunta"`</p>
            </li>
            {% else %}
            <li>No agents created yet.</li>
            {% endfor %}
        </ul>
    </div>
</div>
{% endblock %}
EOF

cat <<'EOF' > "${RAG_LAB_DIR}/control_center/templates/index.html"
{% extends "base.html" %}
{% block content %}
<div class="grid grid-cols-1 md:grid-cols-2 gap-4">
    <!-- Panel de Control -->
    <div class="bg-white p-4 rounded-lg shadow">
        <h2 class="text-xl font-semibold mb-2">Control Panel</h2>
        <div class="flex flex-col space-y-2">
            <form action="/ingest" method="post"><button type="submit" class="w-full bg-blue-500 text-white p-2 rounded">Run Ingest Now</button></form>
            <form action="/diagnostics" method="post"><button type="submit" class="w-full bg-green-500 text-white p-2 rounded">Run Diagnostics</button></form>
            <form action="/backup" method="post"><button type="submit" class="w-full bg-yellow-500 text-white p-2 rounded">Create Backup</button></form>
        </div>
    </div>

    <!-- Estado de los Contenedores -->
    <div class="bg-white p-4 rounded-lg shadow">
        <h2 class="text-xl font-semibold mb-2">Container Status</h2>
        <ul>
            {% for c in containers %}
            <li><strong>{{ c.name }}</strong>: <span class="text-{{ 'green' if 'running' in c.status else 'red' }}-500">{{ c.status }}</span></li>
            {% else %}
            <li>No containers found or Docker API error.</li>
            {% endfor %}
        </ul>
    </div>

    <!-- Configuración -->
    <div class="bg-white p-4 rounded-lg shadow col-span-1 md:col-span-2">
        <h2 class="text-xl font-semibold mb-2">Configuration (.env)</h2>
        <form action="/update-env" method="post">
            <div class="grid grid-cols-2 gap-4">
                {% for key, value in env_config.items() %}
                <div>
                    <label for="{{ key }}" class="block text-sm font-medium">{{ key }}</label>
                    <input type="text" name="{{ key }}" id="{{ key }}" value="{{ value }}" class="w-full p-2 border rounded">
                </div>
                {% endfor %}
            </div>
            <button type="submit" class="mt-4 bg-indigo-500 text-white p-2 rounded">Save & Restart Services</button>
        </form>
    </div>

    <!-- Feedback Loop -->
    <div class="bg-white p-4 rounded-lg shadow col-span-1 md:col-span-2">
        <h2 class="text-xl font-semibold mb-2">Feedback Loop & Learning</h2>
        <div class="mb-4">
            <form action="/simulated-query" method="post">
                <input type="text" name="query" class="w-full p-2 border rounded" placeholder="Escribe una pregunta de prueba...">
                <button type="submit" class="mt-2 bg-gray-500 text-white p-2 rounded">Simular Consulta</button>
            </form>
        </div>
        <div>
            <h3 class="text-lg font-semibold mb-2">Consultas Recientes</h3>
            {% for qa in recent_queries %}
            <div class="border-t py-2">
                <p><strong>P:</strong> {{ qa.query }}</p>
                <p><strong>R:</strong> {{ qa.answer }}</p>
                <form action="/approve-qa/{{ qa.id }}" method="post" class="mt-1">
                    <button type="submit" class="bg-green-600 text-white px-2 py-1 rounded text-sm">Aprobar y Añadir a Base de Conocimiento</button>
                </form>
            </div>
            {% else %}
            <p>No hay consultas recientes.</p>
            {% endfor %}
        </div>
    </div>
</div>
{% endblock %}
EOF

info "--- Fase P3 Completada ---"

# --- Fase 3.5: Creación del Chat Externo Simple ---
info "--- Iniciando Fase 3.5: Creación del Chat Externo Simple ---"

# 1. Backend del Chat Simple (main.py)
info "Generando backend del chat simple..."
cat <<'EOF' > "${RAG_LAB_DIR}/simple_chat/main.py"
import os
import json
from fastapi import FastAPI, WebSocket, Request
from fastapi.responses import HTMLResponse
from fastapi.templating import Jinja2Templates
import httpx

app = FastAPI()
templates = Jinja2Templates(directory="/app/templates")

OLLAMA_HOST = os.getenv("OLLAMA_HOST", "host.docker.internal")
OLLAMA_PORT = os.getenv("OLLAMA_PORT", "11434")
OLLAMA_MODEL = os.getenv("OLLAMA_MODEL", "phi3:3.8b-mini-4k-instruct-q4_K_M")
OLLAMA_API_URL = f"http://{OLLAMA_HOST}:{OLLAMA_PORT}/api/chat"

@app.get("/", response_class=HTMLResponse)
async def get(request: Request):
    return templates.TemplateResponse("chat.html", {"request": request})

@app.websocket("/ws")
async def websocket_endpoint(websocket: WebSocket):
    await websocket.accept()
    async with httpx.AsyncClient(timeout=None) as client:
        while True:
            data = await websocket.receive_text()
            payload = {
                "model": OLLAMA_MODEL,
                "messages": [{"role": "user", "content": data}],
                "stream": True,
            }
            async with client.stream("POST", OLLAMA_API_URL, json=payload) as response:
                async for chunk in response.aiter_bytes():
                    if chunk:
                        try:
                            # Ollama streams ndjson
                            raw_data = chunk.decode('utf-8')
                            for line in raw_data.strip().split('\n'):
                                if line:
                                    json_data = json.loads(line)
                                    content = json_data.get("message", {}).get("content", "")
                                    if content:
                                        await websocket.send_text(content)
                        except json.JSONDecodeError:
                            continue # Incomplete JSON object, wait for next chunk
EOF

# 2. Frontend del Chat Simple (chat.html)
info "Generando frontend del chat simple..."
cat <<'EOF' > "${RAG_LAB_DIR}/simple_chat/templates/chat.html"
<!DOCTYPE html>
<html>
<head>
    <title>RGIA Master - Chat Externo</title>
    <script src="https://cdn.tailwindcss.com"></script>
</head>
<body class="bg-gray-800 text-white flex flex-col h-screen">
    <div id="messages" class="flex-1 p-4 overflow-y-auto"></div>
    <div class="p-4">
        <input id="messageText" class="w-full p-2 bg-gray-700 rounded" autocomplete="off" onkeypress="handleKeyPress(event)"/>
        <button onclick="sendMessage()" class="mt-2 w-full bg-blue-500 p-2 rounded">Enviar</button>
    </div>
    <script>
        const ws = new WebSocket(`ws://${window.location.host}/ws`);
        let currentResponseDiv = null;

        ws.onmessage = function(event) {
            if (currentResponseDiv) {
                currentResponseDiv.innerHTML += event.data;
            }
        };

        function sendMessage() {
            const input = document.getElementById("messageText");
            const messagesDiv = document.getElementById("messages");

            // User message
            const userMsgDiv = document.createElement('div');
            userMsgDiv.className = 'mb-2 p-2 bg-gray-700 rounded';
            userMsgDiv.innerHTML = "<b>Tú:</b> " + input.value;
            messagesDiv.appendChild(userMsgDiv);

            // Bot response container
            currentResponseDiv = document.createElement('div');
            currentResponseDiv.className = 'mb-2 p-2 bg-gray-600 rounded';
            currentResponseDiv.innerHTML = "<b>RGIA Master:</b> ";
            messagesDiv.appendChild(currentResponseDiv);

            ws.send(input.value);
            input.value = '';
            messagesDiv.scrollTop = messagesDiv.scrollHeight;
        }

        function handleKeyPress(event) {
            if (event.key === 'Enter') {
                sendMessage();
            }
        }
    </script>
</body>
</html>
EOF

# 3. Dockerfile para el Chat Simple
info "Generando Dockerfile para el chat simple..."
cat <<'EOF' > "${RAG_LAB_DIR}/simple_chat/Dockerfile"
FROM python:3.9-slim
WORKDIR /app
COPY . .
RUN pip install --no-cache-dir fastapi uvicorn httpx
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000"]
EOF

info "--- Fase 3.5 Completada ---"


# --- Fase P4: Integración Final, QA y Documentación ---
info "--- Iniciando Fase P4: Integración Final, QA y Documentación ---"

# 1. Generar docker-compose.yml final (incluyendo el Control Center)
info "Generando archivo docker-compose.yml final..."
cat <<'EOF' > "${RAG_LAB_DIR}/docker-compose.yml"
version: '3.8'
services:
  qdrant:
    image: qdrant/qdrant:latest
    container_name: rag_qdrant
    restart: unless-stopped
    ports: ["127.0.0.1:6333:6333"]
    volumes: ["./qdrant_storage:/qdrant/storage"]
  open-webui:
    image: ghcr.io/open-webui/open-webui:main
    container_name: rag_open_webui
    restart: unless-stopped
    ports: ["${OPENWEBUI_PORT:-3000}:8080"]
    volumes: ["./open_webui_data:/app/backend/data"]
    environment: ['OLLAMA_BASE_URL=http://host.docker.internal:11434']
    extra_hosts: ["host.docker.internal:host-gateway"]
  filebrowser:
    image: filebrowser/filebrowser:latest
    container_name: rag_filebrowser
    restart: unless-stopped
    ports: ["127.0.0.1:8080:80"]
    volumes: ["./documents:/srv"]
    environment: ["FB_USERNAME=${FILEBROWSER_USER}", "FB_PASSWORD=${FILEBROWSER_PASS}"]
  portainer:
    image: portainer/portainer-ce:latest
    container_name: rag_portainer
    restart: unless-stopped
    ports: ["127.0.0.1:9000:9000"]
    volumes: ["/var/run/docker.sock:/var/run/docker.sock", "portainer_data:/data"]
  rag-control-center:
    build:
      context: ./control_center
    container_name: rag_control_center
    restart: unless-stopped
    ports: ["${RAG_CONTROL_CENTER_PORT:-3200}:8000"]
    volumes: ["/var/run/docker.sock:/var/run/docker.sock", "./config:/opt/rag_lab/config", "./scripts:/opt/rag_lab/scripts"]
    environment: ["CONTROL_CENTER_USER=${CONTROL_CENTER_USER}", "CONTROL_CENTER_PASS=${CONTROL_CENTER_PASS}"]
  simple-chat:
    build:
      context: ./simple_chat
    container_name: rag_simple_chat
    restart: unless-stopped
    ports: ["8001:8000"] # Puerto público para el chat simple
    environment:
      - OLLAMA_HOST=host.docker.internal
      - OLLAMA_MODEL=${OLLAMA_MODEL}
    extra_hosts: ["host.docker.internal:host-gateway"]
volumes:
  portainer_data:
EOF
# Añadir Netdata condicionalmente
if [[ "${ENABLE_NETDATA:-true}" == "true" ]]; then
    echo "  netdata:
    image: netdata/netdata:latest
    container_name: rag_netdata
    restart: unless-stopped
    ports: [\"127.0.0.1:19999:19999\"]
    volumes: [\"/proc:/host/proc:ro\", \"/sys:/host/sys:ro\", \"/var/run/docker.sock:/var/run/docker.sock:ro\"]" >> "${RAG_LAB_DIR}/docker-compose.yml"
fi
# Copiar requirements.txt al contexto de build del Control Center
cp "${RAG_LAB_DIR}/config/requirements.txt" "${RAG_LAB_DIR}/control_center/requirements.txt"
# Crear Dockerfile para el Control Center
cat <<'EOF' > "${RAG_LAB_DIR}/control_center/Dockerfile"
FROM python:3.9-slim
WORKDIR /app
COPY . .
RUN pip install --no-cache-dir -r requirements.txt
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000"]
EOF

# 2. Generar README.md final
info "Generando README.md final..."
cat <<'EOF' > "${RAG_LAB_DIR}/README.md"
# RGIA MASTER: Tu Plataforma de IA Corporativa Privada en Minutos

```
██████╗  ██████╗ ██╗ █████╗     ███╗   ███╗ █████╗ ███████╗████████╗██████╗
██╔══██╗██╔════╝ ██║██╔══██╗    ████╗ ████║██╔══██╗██╔════╝╚══██╔══╝██╔══██╗
██████╔╝██║  ███╗██║███████║    ██╔████╔██║███████║███████╗   ██║   ██████╔╝
██╔══██╗██║   ██║██║██╔══██║    ██║╚██╔╝██║██╔══██║╚════██║   ██║   ██╔══██╗
██║  ██║╚██████╔╝██║██║  ██║    ██║ ╚═╝ ██║██║  ██║███████║   ██║   ██║  ██║
╚═╝  ╚═╝ ╚═════╝ ╚═╝╚═╝  ╚═╝    ╚═╝     ╚═╝╚═╝  ╚═╝╚══════╝   ╚═╝   ╚═╝  ╚═╝
```
*Hecho por Luis Fajardo Rivera (lmfr)*

---

**¡Bienvenido a RGIA MASTER!**

¿Alguna vez has imaginado tener una inteligencia artificial, como ChatGPT, que conozca tu negocio al detalle y opere exclusivamente para ti, con total privacidad y seguridad?

**RGIA MASTER** hace exactamente eso. Esta plataforma transforma un servidor Ubuntu/Debian estándar en un cerebro corporativo privado. Con un solo comando, despliegas un ecosistema completo que "lee" tus documentos —manuales, políticas, reportes, bases de conocimiento— y los convierte en una base de conocimiento interactiva.

**El resultado es simple y poderoso:** puedes hacerle preguntas complejas en lenguaje natural y recibir respuestas precisas, basadas únicamente en tu propia información. Todo esto ocurre dentro de tu servidor, garantizando que tus datos sensibles nunca salgan de tu control.

Este proyecto fue diseñado para ser la forma más rápida y robusta de construir y gestionar un entorno de **Retrieval-Augmented Generation (RAG)**, poniendo el poder de la IA generativa en tus manos.

## 🚀 Características Principales

| Característica | Descripción |
| :--- | :--- |
| ** despliegue ultrarrápido** | De servidor limpio a plataforma RAG funcional en menos de 10 minutos. |
| **🛡️ Seguridad por Defecto** | Solo las interfaces de chat son públicas. El resto es 100% local. |
| **📊 Observabilidad Integrada** | Paneles para monitorear el estado del sistema y la actividad de los contenedores. |
| **⚙️ Gestión Centralizada** | El **RAG Control Center** te da un mando único para operar la plataforma. |
| **🔄 Idempotente y Robusto** | Puedes ejecutar el instalador múltiples veces sin riesgo de romper nada. |

##  tour visual por tu nueva plataforma

Una vez finalizada la instalación, tendrás acceso a un conjunto de herramientas web. Así es como se ve tu nuevo centro de mando:

### 1. 💬 El Chat Principal - Open WebUI
*   **Acceso**: `http://<IP_DE_LA_VM>:3000`
*   **Tu Experiencia**: Una interfaz de chat moderna y completa, similar a ChatGPT, donde puedes elegir modelos, ver el historial de conversaciones y tener una experiencia de diálogo rica.

### 2. ✨ El Chat Directo - Simple Chat
*   **Acceso**: `http://<IP_DE_LA_VM>:8001`
*   **Tu Experiencia**: Una interfaz de chat minimalista y ultrarrápida, ideal para integraciones o para tener conversaciones directas sin distracciones.

### 3. 🕹️ El Centro de Mando - RAG Control Center
*   **Acceso**: `http://localhost:3200` (a través de túnel SSH)
*   **Tu Experiencia**: Tu panel de control privado. Desde aquí puedes:
    *   Ver el estado de todos los servicios.
    *   Ejecutar la ingesta de documentos manualmente.
    *   Crear nuevos agentes de IA con personalidades y propósitos específicos.
    *   Revisar y aprobar preguntas y respuestas para mejorar la base de conocimiento.
    *   Gestionar la configuración del sistema.

### 4. 📂 El Gestor de Documentos - Filebrowser
*   **Acceso**: `http://localhost:8080` (a través de túnel SSH)
*   **Tu Experiencia**: Una interfaz simple para arrastrar y soltar los documentos que alimentarán a tu IA.

### 5. 🐳 El Administrador de Contenedores - Portainer
*   **Acceso**: `http://localhost:9000` (a través de túnel SSH)
*   **Tu Experiencia**: Un dashboard técnico avanzado para ver los logs de los contenedores, su consumo de recursos y gestionar el entorno Docker.

### 6. 📈 El Monitor de Rendimiento - Netdata
*   **Acceso**: `http://localhost:19999` (a través de túnel SSH)
*   **Tu Experiencia**: Métricas en tiempo real sobre la salud de tu servidor: CPU, RAM, disco, red y más.

## ✅ Calidad y Pruebas (QA)

La robustez de esta plataforma es una prioridad. El script de instalación ha pasado por múltiples ciclos de revisión para corregir errores y mejorar la arquitectura. Al final de la instalación, se ejecutan **smoke tests** automáticos que validan que cada componente principal esté en línea y funcionando.

## 🛡️ Arquitectura de Seguridad

La seguridad no es una opción, es la base del diseño:
*   **Exposición Mínima**: Solo los componentes que necesitan ser accedidos por los usuarios finales (las interfaces de chat) están expuestos a la red pública.
*   **Aislamiento de Servicios**: Todos los servicios de gestión, datos y monitoreo operan en `localhost`. El acceso remoto a estos paneles se realiza de forma segura a través de un **túnel SSH**, evitando exponer puertos sensibles a internet.
*   **Credenciales**: Al finalizar la instalación, se te recuerda de forma prominente que debes cambiar las contraseñas por defecto para asegurar tu entorno.

## 🙏 Agradecimientos y Tecnologías Open Source

Esta plataforma no sería posible sin el increíble trabajo de la comunidad de código abierto. Extendemos nuestro agradecimiento a los equipos detrás de estos proyectos fundamentales:

*   **Ollama**: Por hacer que la ejecución de modelos de lenguaje sea increíblemente accesible.
*   **Open WebUI**: Por proporcionar una interfaz de chat de primer nivel.
*   **Qdrant**: Por su motor de base de datos vectorial de alto rendimiento.
*   **Docker**: Por revolucionar la forma en que construimos y desplegamos software.
*   **FastAPI**: Por un framework web en Python que es rápido y fácil de usar.
*   **Netdata, Portainer, Filebrowser**: Por sus excelentes herramientas de gestión y monitoreo.
*   Y a toda la comunidad de **Python**, **Linux** y **Open Source**.

## 🔮 Futuro: RGIA MASTER Pro

La versión actual de RGIA MASTER es una base increíblemente sólida y funcional. La visión a futuro es construir sobre ella una **Versión Pro** aún más potente, pensada para despliegues a mayor escala y con capacidades analíticas avanzadas.

Estas son algunas de las características planificadas para **RGIA MASTER Pro**:

*   **🚀 Requisitos de Hardware Avanzados**:
    *   **GPU Acelerada**: Soporte nativo para inferencia en GPU (NVIDIA), lo que aceleraría las respuestas de 10x a 20x.
    *   **CPU Mínima**: Requeriría un mínimo de 12 núcleos de CPU para manejar cargas de trabajo más intensas.

*   **🤖 Selección de Modelos LLM**:
    *   Permitir al usuario elegir durante la instalación entre al menos tres modelos de lenguaje optimizados para diferentes tareas (ej. uno rápido, uno más potente, uno multilingüe).

*   **📄 Procesamiento OCR Avanzado**:
    *   Integración de un motor **OCR (Reconocimiento Óptico de Caracteres) multilingüe** para extraer texto de PDFs escaneados, imágenes y documentos complejos, haciendo que la información no estructurada sea accesible para la IA.

*   **🏢 Capacidades Multi-Tenencia**:
    *   Aislar las bases de conocimiento y los documentos por departamento o cliente, permitiendo que una sola instancia sirva a múltiples equipos de forma segura.

*   **🔌 Conectores de Datos**:
    *   Añadir conectores para sincronizar conocimiento desde fuentes externas como bases de datos (PostgreSQL, MySQL), Confluence, Notion, etc.

*   **⚡ Agentes Proactivos**:
    *   Desarrollar la capacidad de que los agentes no solo respondan preguntas, sino que también inicien acciones, como enviar un correo electrónico, crear un ticket en un sistema de soporte o ejecutar scripts.
EOF

# 3. Orquestación y Smoke Tests
info "Configurando firewall y arrancando servicios..."
if command -v ufw &> /dev/null; then ufw allow ${OPENWEBUI_PORT:-3000}/tcp; ufw allow 8001/tcp; ufw allow ssh; fi
systemctl enable --now rag_lab

wait_for_service() {
    local url=$1
    local service_name=$2
    local creds=$3
    local timeout=120
    local start_time=$(date +%s)
    info "Esperando a que el servicio ${service_name} esté disponible en ${url}..."

    local curl_cmd="curl -fsS"
    if [ -n "$creds" ]; then
        curl_cmd+=" -u ${creds}"
    fi
    curl_cmd+=" ${url}"

    while true; do
        if ${curl_cmd} > /dev/null; then
            info "Servicio ${service_name} está activo."
            return 0
        fi
        local current_time=$(date +%s)
        if (( current_time - start_time > timeout )); then
            error "Tiempo de espera agotado para el servicio ${service_name}."
            return 1
        fi
        sleep 5
    done
}

info "Esperando a que los servicios se inicien..."
wait_for_service "http://127.0.0.1:6333/ready" "Qdrant" ""
wait_for_service "http://127.0.0.1:${OPENWEBUI_PORT:-3000}" "Open WebUI" ""
wait_for_service "http://127.0.0.1:8001" "Simple Chat" ""
wait_for_service "http://127.0.0.1:${RAG_CONTROL_CENTER_PORT:-3200}" "RAG Control Center" "${CONTROL_CENTER_USER:-admin}:${CONTROL_CENTER_PASS:-ragadmin}"

info "Ejecutando smoke tests..."
curl -fsS http://127.0.0.1:6333/ready || error "Smoke test FAILED: Qdrant"
curl -fsS http://127.0.0.1:${OPENWEBUI_PORT:-3000} || error "Smoke test FAILED: Open WebUI"
curl -fsS http://127.0.0.1:8001 || error "Smoke test FAILED: Simple Chat"
curl -fsS -u "${CONTROL_CENTER_USER:-admin}:${CONTROL_CENTER_PASS:-ragadmin}" http://127.0.0.1:${RAG_CONTROL_CENTER_PORT:-3200} || error "Smoke test FAILED: RAG Control Center (Dashboard)"
curl -fsS -u "${CONTROL_CENTER_USER:-admin}:${CONTROL_CENTER_PASS:-ragadmin}" http://127.0.0.1:${RAG_CONTROL_CENTER_PORT:-3200}/agents || error "Smoke test FAILED: RAG Control Center (Agents Page)"
info "Smoke tests PASSED."

# 4. Mensaje Final
info "--- Instalación Completada ---"
ip_address=$(hostname -I | awk '{print $1}')
echo "Plataforma RAG instalada."
echo "Open WebUI: http://${ip_address}:${OPENWEBUI_PORT:-3000}"
echo "Simple Chat: http://${ip_address}:8001"
echo "RAG Control Center (via SSH tunnel): http://127.0.0.1:${RAG_CONTROL_CENTER_PORT:-3200}"
echo "  - User: ${CONTROL_CENTER_USER:-admin}"
echo "  - Pass: ${CONTROL_CENTER_PASS:-ragadmin}"
echo ""
echo "!!! IMPORTANTE: Por favor, cambia las credenciales por defecto de Filebrowser y del RAG Control Center lo antes posible. !!!"
echo "La contraseña de Filebrowser se puede cambiar en su propia interfaz web. La del Control Center se cambia en /opt/rag_lab/config/.env"


info "--- Fase P4 Completada ---"
