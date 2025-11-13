#!/usr/bin/env bash
set -Eeuo pipefail

#
# RGIA MASTER - BASE VERSION INSTALLER
# ==================================
#
# Descripción:
# Este script instala y configura una plataforma RAG (Retrieval-Augmented Generation)
# esencial sobre sistemas Ubuntu/Debian. Incluye el motor RAG,
# una interfaz de chat y paneles de monitoreo.
#
# Idempotente, seguro y diseñado para funcionar en un entorno de CPU.
#
# Autor: Jules, Agente DevOps Senior
# Versión: 1.0 (Base)
#

# --- Configuración de Logging y Entorno ---
LOG_FILE="/var/log/rag_base_install.log"
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
export RAG_LAB_DIR="/opt/rag_lab_base"
export CONFIG_DIR="${RAG_LAB_DIR}/config"
export SCRIPTS_DIR="${RAG_LAB_DIR}/scripts"
export VENV_DIR="${RAG_LAB_DIR}/venv"
export LOGS_DIR="${RAG_LAB_DIR}/logs"
export DOCS_DIR="${RAG_LAB_DIR}/documents"

# --- Definición de Archivos con Heredocs ---

generate_env_file() {
    info "Generando archivo de configuración .env..."
    mkdir -p "${CONFIG_DIR}"
    cat <<'EOF' > "${CONFIG_DIR}/.env"
# === Red y Puertos ===
OPENWEBUI_PORT=3000
EXPOSE_OLLAMA=false
OLLAMA_BIND=127.0.0.1

# === Modelos y RAG ===
OLLAMA_MODEL=phi3:3.8b-mini-4k-instruct-q4_K_M
EMBEDDING_MODEL=intfloat/multilingual-e5-small
RAG_COLLECTION=rag_base_collection

# === Configuración de Servicios ===
FILEBROWSER_USER=admin
FILEBROWSER_PASS=admin
ENABLE_NETDATA=true
EOF
    success "Archivo .env generado."
}

generate_docker_compose() {
    info "Generando archivo docker-compose.yml..."
    # Cargar variables para usarlas en el heredoc
    source "${CONFIG_DIR}/.env"

    cat <<EOF > "${RAG_LAB_DIR}/docker-compose.yml"
version: '3.8'

services:
  qdrant:
    image: qdrant/qdrant:v1.9.2
    container_name: rag_base_qdrant
    restart: unless-stopped
    ports:
      - "127.0.0.1:6333:6333"
    volumes:
      - "${RAG_LAB_DIR}/qdrant_storage:/qdrant/storage"
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:6333/ready"]
      interval: 10s
      timeout: 5s
      retries: 5
    networks:
      - rag_net

  open-webui:
    image: ghcr.io/open-webui/open-webui:main
    container_name: rag_base_open_webui
    restart: unless-stopped
    ports:
      - "${OPENWEBUI_PORT}:8080"
    volumes:
      - "${RAG_LAB_DIR}/open_webui_data:/app/backend/data"
    environment:
      - 'OLLAMA_BASE_URL=http://host.docker.internal:11434'
    extra_hosts:
      - "host.docker.internal:host-gateway"
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8080/"]
      interval: 30s
      timeout: 10s
      retries: 3
    networks:
      - rag_net

  filebrowser:
    image: filebrowser/filebrowser:v2
    container_name: rag_base_filebrowser
    restart: unless-stopped
    ports:
      - "127.0.0.1:8081:80"
    volumes:
      - "${DOCS_DIR}:/srv"
    environment:
      - FB_USERNAME=${FILEBROWSER_USER}
      - FB_PASSWORD=${FILEBROWSER_PASS}
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost/health"]
      interval: 30s
      timeout: 10s
      retries: 3
    networks:
      - rag_net

  portainer:
    image: portainer/portainer-ce:latest
    container_name: rag_base_portainer
    restart: unless-stopped
    ports:
      - "127.0.0.1:9000:9000"
    volumes:
      - "/var/run/docker.sock:/var/run/docker.sock"
      - "${RAG_LAB_DIR}/portainer_data:/data"
    networks:
      - rag_net
EOF

    if [[ "${ENABLE_NETDATA}" == "true" ]]; then
        info "Añadiendo Netdata al docker-compose..."
        cat <<'EOF' >> "${RAG_LAB_DIR}/docker-compose.yml"

  netdata:
    image: netdata/netdata:latest
    container_name: rag_base_netdata
    hostname: ${HOSTNAME}
    ports:
      - "127.0.0.1:19999:19999"
    cap_add:
      - SYS_PTRACE
    security_opt:
      - apparmor:unconfined
    volumes:
      - /proc:/host/proc:ro
      - /sys:/host/sys:ro
      - /var/run/docker.sock:/var/run/docker.sock:ro
    restart: unless-stopped
    networks:
      - rag_net
EOF
    fi

    cat <<'EOF' >> "${RAG_LAB_DIR}/docker-compose.yml"

networks:
  rag_net:
    driver: bridge
EOF
    success "Archivo docker-compose.yml generado."
}

generate_python_scripts() {
    info "Generando scripts Python..."
    mkdir -p "${SCRIPTS_DIR}"

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
EOF

    cat <<'EOF' > "${SCRIPTS_DIR}/ingestion_script.py"
import os
import hashlib
import logging
from datetime import datetime
from pathlib import Path

from llama_index.core import SimpleDirectoryReader, Document
from llama_index.core.node_parser import SentenceSplitter
from llama_index.embeddings.huggingface import HuggingFaceEmbedding
from qdrant_client import QdrantClient, models
from tenacity import retry, stop_after_attempt, wait_fixed
from dotenv import load_dotenv
from tqdm import tqdm

logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
load_dotenv(dotenv_path=Path(__file__).parent.parent / 'config' / '.env')

RAG_LAB_DIR = Path(os.getenv("RAG_LAB_DIR", "/opt/rag_lab_base"))
DOCS_DIR = RAG_LAB_DIR / "documents"
EMBEDDING_MODEL = os.getenv("EMBEDDING_MODEL")
RAG_COLLECTION = os.getenv("RAG_COLLECTION")

def generate_deterministic_id(content: str) -> str:
    return hashlib.sha256(content.encode('utf-8')).hexdigest()

@retry(stop=stop_after_attempt(5), wait=wait_fixed(10))
def get_qdrant_client():
    client = QdrantClient(host="127.0.0.1", port=6333)
    client.get_collections()
    return client

def main():
    logging.info(f"--- Iniciando ingesta desde {DOCS_DIR} ---")
    client = get_qdrant_client()

    try:
        client.get_collection(collection_name=RAG_COLLECTION)
    except Exception:
        client.create_collection(
            collection_name=RAG_COLLECTION,
            vectors_config=models.VectorParams(size=384, distance=models.Distance.COSINE),
        )

    documents = SimpleDirectoryReader(input_dir=DOCS_DIR, recursive=True).load_data()
    if not documents:
        logging.info("No se encontraron nuevos documentos.")
        return

    node_parser = SentenceSplitter(chunk_size=512, chunk_overlap=50)
    nodes = node_parser.get_nodes_from_documents(documents, show_progress=True)

    embed_model = HuggingFaceEmbedding(model_name=EMBEDDING_MODEL)
    for node in tqdm(nodes, desc="Generando embeddings"):
        node.embedding = embed_model.get_text_embedding(node.get_content())

    points = [
        models.PointStruct(
            id=generate_deterministic_id(node.get_content()),
            vector=node.embedding,
            payload={ "text": node.get_content(), "metadata": { "source_path": node.metadata.get("file_path", "N/A") } }
        )
        for node in nodes
    ]

    client.upsert(collection_name=RAG_COLLECTION, points=points, wait=True)
    logging.info(f"Ingesta completada. {len(documents)} documentos procesados, {len(points)} chunks generados.")

if __name__ == "__main__":
    main()
EOF

    cat <<'EOF' > "${SCRIPTS_DIR}/query_agent.py"
import os
import argparse
import ollama
from qdrant_client import QdrantClient
from llama_index.embeddings.huggingface import HuggingFaceEmbedding
from dotenv import load_dotenv
from pathlib import Path

load_dotenv(dotenv_path=Path(__file__).parent.parent / 'config' / '.env')

EMBEDDING_MODEL = os.getenv("EMBEDDING_MODEL")
OLLAMA_BIND = os.getenv("OLLAMA_BIND")
OLLAMA_MODEL = os.getenv("OLLAMA_MODEL")
RAG_COLLECTION = os.getenv("RAG_COLLECTION")

def main(query: str):
    client = QdrantClient(host="127.0.0.1", port=6333)
    embed_model = HuggingFaceEmbedding(model_name=EMBEDDING_MODEL)
    query_embedding = embed_model.get_query_embedding(query)

    search_result = client.search(collection_name=RAG_COLLECTION, query_vector=query_embedding, limit=5)
    context = "\n---\n".join([hit.payload["text"] for hit in search_result])

    prompt = f"Contexto: {context}\n\nPregunta: {query}\n\nRespuesta:"
    ollama_client = ollama.Client(host=f"http://{OLLAMA_BIND}:11434")

    print("\n--- Respuesta del Agente RAG ---")
    response = ollama_client.generate(model=OLLAMA_MODEL, prompt=prompt, stream=True)
    for chunk in response:
        print(chunk['response'], end='', flush=True)
    print("\n------------------------------\n")

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Agente de consulta RAG.")
    parser.add_argument("query", type=str, help="La pregunta a realizar.")
    args = parser.parse_args()
    main(args.query)
EOF
    success "Scripts Python generados."
}

generate_helper_scripts() {
    info "Generando scripts de ayuda..."
    cat <<'EOF' > "${SCRIPTS_DIR}/diag_rag.sh"
#!/usr/bin/env bash
echo "--- Estado de los Contenedores Docker ---"
docker compose -f /opt/rag_lab_base/docker-compose.yml ps
echo -e "\n--- Estado del Servicio systemd ---"
systemctl status rag_lab_base --no-pager || echo "Servicio no encontrado."
echo -e "\n--- Endpoints Principales ---"
curl -s -o /dev/null -w "Qdrant Ready: %{http_code}\n" http://127.0.0.1:6333/ready || echo "Qdrant no responde."
EOF
    chmod +x "${SCRIPTS_DIR}/diag_rag.sh"
    success "Scripts de ayuda generados."
}

# --- Lógica de Instalación ---
install_dependencies() {
    info "Instalando dependencias del sistema..."
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -y
    apt-get install -y ca-certificates curl gnupg lsb-release htop python3 python3-venv python3-pip git
    success "Dependencias instaladas."
}

install_docker() {
    if command -v docker &> /dev/null; then
        info "Docker ya está instalado."
        return
    fi
    info "Instalando Docker Engine..."
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    chmod a+r /etc/apt/keyrings/docker.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" > /etc/apt/sources.list.d/docker.list
    apt-get update -y
    apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    systemctl enable --now docker
    success "Docker Engine instalado y habilitado."
}

install_ollama() {
    if command -v ollama &> /dev/null; then
        info "Ollama ya está instalado."
    else
        info "Instalando Ollama..."
        curl -fsSL https://ollama.com/install.sh | sh
        success "Ollama instalado."
    fi

    source "${CONFIG_DIR}/.env"
    info "Configurando Ollama para escuchar en ${OLLAMA_BIND}..."
    mkdir -p /etc/systemd/system/ollama.service.d
    cat <<EOF > /etc/systemd/system/ollama.service.d/override.conf
[Service]
ExecStart=
ExecStart=/usr/local/bin/ollama serve
Environment="OLLAMA_HOST=${OLLAMA_BIND}"
EOF
    systemctl daemon-reload
    systemctl restart ollama

    info "Descargando el modelo LLM: ${OLLAMA_MODEL} (puede tardar)..."
    ollama pull "${OLLAMA_MODEL}"
    success "Modelo LLM descargado."
}

setup_python_env() {
    info "Configurando entorno virtual Python..."
    python3 -m venv "${VENV_DIR}"
    source "${VENV_DIR}/bin/activate"
    pip install -r "${CONFIG_DIR}/requirements.txt"
    deactivate
    success "Entorno virtual Python configurado."
}

setup_automation() {
    info "Configurando servicio systemd..."
    cat <<EOF > /etc/systemd/system/rag_lab_base.service
[Unit]
Description=RGIA Base RAG Stack
After=docker.service network-online.target ollama.service
Requires=docker.service ollama.service

[Service]
Type=oneshot
RemainAfterExit=yes
User=root
WorkingDirectory=${RAG_LAB_DIR}
ExecStart=/usr/bin/docker compose up -d
ExecStop=/usr/bin/docker compose down
TimeoutStartSec=0

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable --now rag_lab_base.service
    success "Servicio systemd 'rag_lab_base' habilitado."

    info "Configurando cron para ingesta diaria..."
    cat <<EOF > /etc/cron.d/rag_base_ingest
0 3 * * * root ${VENV_DIR}/bin/python ${SCRIPTS_DIR}/ingestion_script.py >> /var/log/rag_base_ingest.log 2>&1
EOF
    success "Trabajo de cron configurado."
}

run_smoke_tests() {
    info "--- Ejecutando Smoke Tests ---"
    source "${CONFIG_DIR}/.env"
    local all_ok=true

    # 1. Docker containers
    if docker compose -f "${RAG_LAB_DIR}/docker-compose.yml" ps | grep -q "Up"; then success "Test 1: Contenedores Docker están corriendo."; else error "Test 1: FAILED. Algunos contenedores no están corriendo."; all_ok=false; fi
    # 2. Qdrant
    if curl -fsS http://127.0.0.1:6333/ready > /dev/null; then success "Test 2: Qdrant está listo."; else error "Test 2: FAILED. Qdrant no responde."; all_ok=false; fi
    # 3. Ollama model
    if ollama list | grep -q "${OLLAMA_MODEL}"; then success "Test 3: Modelo Ollama está presente."; else error "Test 3: FAILED. Modelo Ollama no encontrado."; all_ok=false; fi

    if $all_ok; then success "Todos los smoke tests pasaron!"; else error "Algunos smoke tests fallaron. Revisa el log."; fi
}

# --- Flujo de Instalación Principal ---
main() {
    check_root
    check_distro

    info "--- Iniciando Instalación de RGIA MASTER (Base) ---"

    mkdir -p "${RAG_LAB_DIR}" "${DOCS_DIR}" "${LOGS_DIR}"
    touch "${DOCS_DIR}/ejemplo.txt" && echo "Este es un documento de ejemplo." > "${DOCS_DIR}/ejemplo.txt"

    generate_env_file
    generate_docker_compose
    generate_python_scripts
    generate_helper_scripts

    install_dependencies
    install_docker
    install_ollama
    setup_python_env
    setup_automation

    run_smoke_tests

    success "--- Instalación de RGIA MASTER (Base) finalizada ---"
    info "El log completo está en: ${LOG_FILE}"

    source "${CONFIG_DIR}/.env"
    IP_ADDR=$(hostname -I | awk '{print $1}')
    echo -e "\n${C_GREEN}Plataforma lista. Endpoints disponibles:${C_NC}"
    echo -e "- Open WebUI (Chat):      ${C_YELLOW}http://${IP_ADDR}:${OPENWEBUI_PORT}${C_NC}"
    echo -e "- Filebrowser (Archivos): ${C_YELLOW}http://127.0.0.1:8081${C_NC} (user: ${FILEBROWSER_USER})"
    echo -e "- Portainer (Docker):     ${C_YELLOW}http://127.0.0.1:9000${C_NC}"
    if [[ "${ENABLE_NETDATA}" == "true" ]]; then
    echo -e "- Netdata (Host):         ${C_YELLOW}http://127.0.0.1:19999${C_NC}"
    fi
    echo -e "\nPara acceder a los paneles 'localhost', usa un túnel SSH si es necesario."
}

main "$@"
