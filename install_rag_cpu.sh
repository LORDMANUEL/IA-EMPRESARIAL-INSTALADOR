#!/usr/bin/env bash
#
# RGIA Master - RAG CPU Lab Installer
# Mision: Simplificar y democratizar la adopción de IA empresarial en las organizaciones.
# Vision: Ser el estándar abierto de referencia para laboratorios de IA empresarial en Latinoamérica.
#

# -----------------------------------------------------------------------------
# Seccion 1: Configuracion inicial y seguridad del script
# -----------------------------------------------------------------------------
set -Eeuo pipefail

LOG_FILE="/var/log/rag_install.log"
exec > >(tee -a "${LOG_FILE}") 2>&1

ERROR_LOG_FILE="/var/log/rag_install_errors.log"

# -----------------------------------------------------------------------------
# Seccion 2: Funciones de logging y manejo de errores
# -----------------------------------------------------------------------------
RESET="\033[0m"
BOLD="\033[1m"
RED="\033[0;31m"
GREEN="\033[0;32m"
YELLOW="\033[0;33m"
BLUE="\033[0;34m"

log_info() { echo -e "${BLUE}[INFO] $(date '+%Y-%m-%d %H:%M:%S') - ${1}${RESET}"; }
log_ok() { echo -e "${GREEN}[OK] $(date '+%Y-%m-%d %H:%M:%S') - ${1}${RESET}"; }
log_warn() { echo -e "${YELLOW}[WARN] $(date '+%Y-%m-%d %H:%M:%S') - ${1}${RESET}"; }
log_error() { echo -e "${RED}[ERROR] $(date '+%Y-%m-%d %H:%M:%S') - ${1}${RESET}"; }

fail_with() {
    local error_code="$1"
    local message="$2"
    log_error "${error_code} - ${message}"
    echo "$(date '+%Y-%m-%d %H:%M:%S') - ${error_code} - ${message}" >> "${ERROR_LOG_FILE}"
    echo -e "\n${BOLD}${RED}Instalación fallida. Código de error: ${error_code}.${RESET}"
    echo -e "${YELLOW}Por favor, revise los logs en ${LOG_FILE} y la sección 'Errores comunes' en el README.md para solucionar el problema.${RESET}"
    exit 1
}

trap 'fail_with "E999_UNEXPECTED_ERROR" "El script terminó inesperadamente en la línea ${LINENO}."' ERR

# -----------------------------------------------------------------------------
# Seccion 3: Verificación inicial del sistema (Preflight)
# -----------------------------------------------------------------------------
log_info "Iniciando la instalación de RGIA Master - RAG CPU Lab..."

if [[ "${EUID}" -ne 0 ]]; then
    fail_with "E000_NOT_ROOT" "Este script debe ser ejecutado con privilegios de root (sudo)."
fi

if ! command -v lsb_release &> /dev/null || ! lsb_release -is | grep -qE 'Ubuntu|Debian'; then
    fail_with "E000_UNSUPPORTED_OS" "Este script está diseñado para Ubuntu o Debian."
fi

export DEBIAN_FRONTEND=noninteractive

# -----------------------------------------------------------------------------
# Seccion 4: Definición de variables globales y de configuración
# -----------------------------------------------------------------------------
RAG_LAB_DIR="/opt/rag_lab"

OPENWEBUI_PORT=${OPENWEBUI_PORT:-3000}
EXPOSE_OLLAMA=${EXPOSE_OLLAMA:-false}
RAG_COLLECTION=${RAG_COLLECTION:-corporativo_rag}
EMBEDDING_MODEL=${EMBEDDING_MODEL:-"intfloat/multilingual-e5-small"}
OLLAMA_MODEL=${OLLAMA_MODEL:-"phi3:3.8b-mini-4k-instruct-q4_K_M"}
FILEBROWSER_USER=${FILEBROWSER_USER:-"admin"}
FILEBROWSER_PASS=${FILEBROWSER_PASS:-"admin"}
OLLAMA_BIND="127.0.0.1"
if [[ "${EXPOSE_OLLAMA}" == "true" ]]; then
    OLLAMA_BIND="0.0.0.0"
fi

# -----------------------------------------------------------------------------
# Seccion 5: Instalación de dependencias del sistema
# -----------------------------------------------------------------------------
log_info "Actualizando lista de paquetes del sistema..."
if ! apt-get update -y; then
    log_warn "Falló el primer intento de 'apt-get update'. Reintentando..."
    sleep 5
    if ! apt-get update -y; then
        fail_with "E000_APT_UPDATE_FAILED" "No se pudo actualizar la lista de paquetes."
    fi
fi
log_ok "Lista de paquetes actualizada."

log_info "Instalando dependencias básicas (curl, git, python, etc.)..."
apt-get install -y curl ca-certificates htop python3 python3-venv python3-pip git jq
log_ok "Dependencias básicas instaladas."

# -----------------------------------------------------------------------------
# Seccion 6: Instalación y configuración de Docker y Docker Compose
# -----------------------------------------------------------------------------
if ! command -v docker &> /dev/null; then
    log_info "Docker no está instalado. Instalando Docker Engine..."
    install -m 0755 -d /etc/apt/keyrings
    if ! curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc; then
        fail_with "E001_DOCKER_INSTALL_FAILED" "No se pudo descargar la clave GPG de Docker."
    fi
    chmod a+r /etc/apt/keyrings/docker.asc
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
    apt-get update -y
    if ! apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin; then
        fail_with "E001_DOCKER_INSTALL_FAILED" "No se pudieron instalar los paquetes de Docker."
    fi
    log_ok "Docker Engine instalado correctamente."
else
    log_info "Docker ya está instalado. Omitiendo instalación."
fi

log_info "Iniciando y habilitando el servicio Docker..."
systemctl start docker
systemctl enable docker
log_ok "Servicio Docker iniciado y habilitado."

# -----------------------------------------------------------------------------
# Seccion 7: Configuración del Firewall (UFW)
# -----------------------------------------------------------------------------
if command -v ufw &> /dev/null; then
    log_info "UFW detectado. Configurando reglas de firewall..."
    ufw allow ssh
    ufw allow "${OPENWEBUI_PORT}/tcp"
    if [[ "${EXPOSE_OLLAMA}" == "true" ]]; then
        ufw allow 11434/tcp
    fi
    echo "y" | ufw enable
    log_ok "Reglas de firewall para Open WebUI y SSH aplicadas."
else
    log_warn "UFW no está instalado. Se recomienda configurar un firewall."
fi

# -----------------------------------------------------------------------------
# Seccion 8: Instalación y configuración de Ollama
# -----------------------------------------------------------------------------
if ! command -v ollama &> /dev/null; then
    log_info "Ollama no está instalado. Instalando Ollama..."
    if ! (curl -fsSL https://ollama.ai/install.sh | sh); then
        fail_with "E002_OLLAMA_INSTALL_FAILED" "El script de instalación de Ollama falló."
    fi
    log_ok "Ollama instalado correctamente."
else
    log_info "Ollama ya está instalado. Omitiendo instalación."
fi

log_info "Configurando Ollama para escuchar en ${OLLAMA_BIND}..."
mkdir -p /etc/systemd/system/ollama.service.d
cat <<EOF > /etc/systemd/system/ollama.service.d/override.conf
[Service]
Environment="OLLAMA_HOST=${OLLAMA_BIND}:11434"
EOF

systemctl daemon-reload
systemctl restart ollama
log_ok "Ollama configurado y reiniciado."

log_info "Descargando el modelo LLM: ${OLLAMA_MODEL}. Esto puede tardar varios minutos..."
ollama pull "${OLLAMA_MODEL}" || \
(log_warn "Falló la descarga del modelo. Reintentando en 15 segundos..." && sleep 15 && ollama pull "${OLLAMA_MODEL}") || \
(log_warn "Falló la descarga del modelo por segunda vez. Reintentando en 30 segundos..." && sleep 30 && ollama pull "${OLLAMA_MODEL}") || \
fail_with "E003_MODEL_PULL_FAILED" "No se pudo descargar el modelo ${OLLAMA_MODEL} después de 3 intentos."
log_ok "Modelo ${OLLAMA_MODEL} descargado con éxito."

# -----------------------------------------------------------------------------
# Seccion 9: Creación de la estructura de directorios de la plataforma
# -----------------------------------------------------------------------------
log_info "Creando la estructura de directorios en ${RAG_LAB_DIR}..."
mkdir -p "${RAG_LAB_DIR}/documents"
mkdir -p "${RAG_LAB_DIR}/qdrant_storage"
mkdir -p "${RAG_LAB_DIR}/open_webui_data"
mkdir -p "${RAG_LAB_DIR}/scripts"
mkdir -p "${RAG_LAB_DIR}/logs"
mkdir -p "${RAG_LAB_DIR}/config"
mkdir -p "${RAG_LAB_DIR}/portainer"
mkdir -p "${RAG_LAB_DIR}/web_internal"
log_ok "Estructura de directorios creada."

# -----------------------------------------------------------------------------
# Seccion 10: Generación de archivos de configuración
# -----------------------------------------------------------------------------
log_info "Generando archivo de configuración .env..."
cat <<EOF > "${RAG_LAB_DIR}/config/.env"
# Archivo de configuración para RGIA Master RAG CPU Lab
OPENWEBUI_PORT=${OPENWEBUI_PORT}
EXPOSE_OLLAMA=${EXPOSE_OLLAMA}
OLLAMA_BIND=${OLLAMA_BIND}
RAG_COLLECTION=${RAG_COLLECTION}
RAG_DOCS_DIR=${RAG_LAB_DIR}/documents
EMBEDDING_MODEL=${EMBEDDING_MODEL}
OLLAMA_MODEL=${OLLAMA_MODEL}
FILEBROWSER_USER=${FILEBROWSER_USER}
FILEBROWSER_PASS=${FILEBROWSER_PASS}
EOF
log_ok "Archivo .env creado en ${RAG_LAB_DIR}/config/.env."


log_info "Generando archivo docker-compose.yml..."
cat <<'EOF' > "${RAG_LAB_DIR}/docker-compose.yml"
version: '3.8'

services:
  qdrant:
    image: qdrant/qdrant:latest
    container_name: rag_qdrant
    restart: unless-stopped
    ports:
      - "127.0.0.1:6333:6333"
    volumes:
      - ./qdrant_storage:/qdrant/storage
    networks:
      - rag_net
    healthcheck: {test: ["CMD", "curl", "-f", "http://localhost:6333/ready"], interval: 10s, timeout: 5s, retries: 5}

  filebrowser:
    image: filebrowser/filebrowser:latest
    container_name: rag_filebrowser
    restart: unless-stopped
    ports:
      - "127.0.0.1:8080:80"
    volumes:
      - ./documents:/srv
    environment:
      - FB_USERNAME=${FILEBROWSER_USER}
      - FB_PASSWORD=${FILEBROWSER_PASS}
    networks:
      - rag_net
    healthcheck: {test: ["CMD", "wget", "--spider", "-q", "http://localhost:80/health"], interval: 10s, timeout: 5s, retries: 5}

  open-webui:
    image: ghcr.io/open-webui/open-webui:latest
    container_name: rag_open_webui
    restart: unless-stopped
    ports:
      - "${OPENWEBUI_PORT}:8080"
    volumes:
      - ./open_webui_data:/app/backend/data
    environment:
      - OLLAMA_BASE_URL=http://host.docker.internal:11434
    extra_hosts:
      - "host.docker.internal:host-gateway"
    depends_on:
      qdrant: {condition: service_healthy}
    networks:
      - rag_net
    healthcheck: {test: ["CMD", "curl", "-f", "http://localhost:8080/health"], interval: 15s, timeout: 10s, retries: 5}

  portainer:
    image: portainer/portainer-ce:latest
    container_name: rag_portainer
    restart: unless-stopped
    ports:
      - "127.0.0.1:9000:9000"
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
      - ./portainer:/data
    networks:
      - rag_net
    healthcheck: {test: ["CMD", "curl", "-f", "http://localhost:9000/api/status"], interval: 10s, timeout: 5s, retries: 5}

networks:
  rag_net:
    driver: bridge
EOF
log_ok "Archivo docker-compose.yml creado."

# -----------------------------------------------------------------------------
# Seccion 11: Entorno Python para RAG
# -----------------------------------------------------------------------------
log_info "Creando entorno virtual de Python en ${RAG_LAB_DIR}/venv..."
if [ ! -d "${RAG_LAB_DIR}/venv" ]; then
    python3 -m venv "${RAG_LAB_DIR}/venv" || fail_with "E004_VENV_CREATION_FAILED" "No se pudo crear el entorno virtual."
fi
log_ok "Entorno virtual creado."

log_info "Generando archivo requirements.txt..."
cat <<'EOF' > "${RAG_LAB_DIR}/config/requirements.txt"
llama-index==0.10.34
qdrant-client==1.9.0
pypdf==4.2.0
sentence-transformers==2.7.0
urllib3<2.0.0
tenacity==8.2.3
tqdm==4.66.4
requests==2.31.0
ollama==0.2.0
python-dotenv==1.0.1
EOF
log_ok "Archivo requirements.txt creado."

log_info "Instalando dependencias de Python..."
source "${RAG_LAB_DIR}/venv/bin/activate"
pip install --upgrade pip
if ! pip install -r "${RAG_LAB_DIR}/config/requirements.txt"; then
    fail_with "E005_PIP_INSTALL_FAILED" "No se pudieron instalar las dependencias de Python."
fi
deactivate
log_ok "Dependencias de Python instaladas."

# -----------------------------------------------------------------------------
# Seccion 12: Generación de scripts Python para RAG
# -----------------------------------------------------------------------------
log_info "Generando script de ingesta: ingestion_script.py..."
cat <<'EOF' > "${RAG_LAB_DIR}/scripts/ingestion_script.py"
import os, hashlib, time
from pathlib import Path
from dotenv import load_dotenv
from tqdm import tqdm
import qdrant_client
from llama_index.core import SimpleDirectoryReader, Document
from llama_index.core.node_parser import SentenceSplitter
from llama_index.core.embeddings import resolve_embed_model
from llama_index.vector_stores.qdrant import QdrantVectorStore

# Configuración
load_dotenv(dotenv_path=Path(__file__).parent.parent / 'config' / '.env')
RAG_DOCS_DIR = os.getenv("RAG_DOCS_DIR")
EMBEDDING_MODEL = os.getenv("EMBEDDING_MODEL")
RAG_COLLECTION = os.getenv("RAG_COLLECTION")
QDRANT_HOST, QDRANT_PORT = "127.0.0.1", 6333

def get_processed_files_tracker(collection_name):
    tracker_dir = Path(os.getenv("RAG_LAB_DIR", "/opt/rag_lab")) / "logs"
    tracker_dir.mkdir(exist_ok=True)
    return tracker_dir / f"processed_{collection_name}.log"

def main():
    client = qdrant_client.QdrantClient(host=QDRANT_HOST, port=QDRANT_PORT)
    try: client.get_collection(collection_name=RAG_COLLECTION)
    except Exception: client.create_collection(collection_name=RAG_COLLECTION, vectors_config=qdrant_client.http.models.VectorParams(size=384, distance=qdrant_client.http.models.Distance.COSINE))
    vector_store = QdrantVectorStore(client=client, collection_name=RAG_COLLECTION)

    docs = SimpleDirectoryReader(RAG_DOCS_DIR, recursive=True).load_data()
    if not docs:
        print("No se encontraron nuevos documentos.")
        return

    embed_model = resolve_embed_model(f"local:{EMBEDDING_MODEL}")
    node_parser = SentenceSplitter(chunk_size=512, chunk_overlap=50)

    tracker_file = get_processed_files_tracker(RAG_COLLECTION)
    processed_hashes = set(f.read().splitlines()) if tracker_file.exists() else set()

    new_nodes = []
    for doc in tqdm(docs, desc="Procesando documentos"):
        doc_hash = hashlib.md5(doc.text.encode()).hexdigest()
        if doc_hash not in processed_hashes:
            nodes = node_parser.get_nodes_from_documents([doc])
            for node in nodes:
                node.embedding = embed_model.get_text_embedding(node.get_content(metadata_mode="all"))
            new_nodes.extend(nodes)
            processed_hashes.add(doc_hash)

    if new_nodes:
        vector_store.add(new_nodes)
        with open(tracker_file, 'a') as f:
            for h in processed_hashes: f.write(f"{h}\n")
        print(f"Ingesta de {len(new_nodes)} nuevos chunks completada.")
    else:
        print("No hay nuevos chunks para ingestar.")

if __name__ == "__main__": main()
EOF
log_ok "Script de ingesta generado."

log_info "Generando script de consulta: query_agent.py..."
cat <<'EOF' > "${RAG_LAB_DIR}/scripts/query_agent.py"
import os, sys, textwrap
from pathlib import Path
from dotenv import load_dotenv
import qdrant_client, ollama
from llama_index.core.vector_stores import VectorStoreQuery
from llama_index.core.embeddings import resolve_embed_model
from llama_index.vector_stores.qdrant import QdrantVectorStore

# Configuración
load_dotenv(dotenv_path=Path(__file__).parent.parent / 'config' / '.env')
RAG_COLLECTION = os.getenv("RAG_COLLECTION")
EMBEDDING_MODEL = os.getenv("EMBEDDING_MODEL")
OLLAMA_MODEL = os.getenv("OLLAMA_MODEL")
OLLAMA_URL = f"http://{os.getenv('OLLAMA_BIND')}:11434"

def main(query_text):
    embed_model = resolve_embed_model(f"local:{EMBEDDING_MODEL}")
    query_embedding = embed_model.get_text_embedding(query_text)

    client = qdrant_client.QdrantClient(host="127.0.0.1", port=6333)
    vector_store = QdrantVectorStore(client=client, collection_name=RAG_COLLECTION)
    retrieval_results = vector_store.query(VectorStoreQuery(query_embedding=query_embedding, similarity_top_k=5))

    context_str = "\n\n".join([node.get_content() for node in retrieval_results.nodes]) if retrieval_results.nodes else "No se encontró información relevante."

    prompt = f"Basándote únicamente en el siguiente contexto, responde la pregunta.\n\nContexto:\n---\n{context_str}\n---\n\nPregunta: {query_text}\nRespuesta:"

    response = ollama.chat(model=OLLAMA_MODEL, messages=[{'role': 'user', 'content': prompt}])

    print("\n--- Respuesta del Asistente IA ---\n")
    print(textwrap.fill(response['message']['content'], width=100))
    print("\n-----------------------------------\n")

if __name__ == "__main__":
    main(" ".join(sys.argv[1:]) if len(sys.argv) > 1 else "¿Qué es RGIA Master?")
EOF
log_ok "Script de consulta generado."

# -----------------------------------------------------------------------------
# Seccion 13: Automatización (Cron job)
# -----------------------------------------------------------------------------
log_info "Configurando tarea cron para la ingesta diaria..."
CRON_JOB_FILE="/etc/cron.d/rag_ingest"
CRON_JOB_CONTENT="0 3 * * * root ${RAG_LAB_DIR}/venv/bin/python ${RAG_LAB_DIR}/scripts/ingestion_script.py >> /var/log/rag_ingest.log 2>&1"
echo "${CRON_JOB_CONTENT}" > "${CRON_JOB_FILE}"
chmod 0644 "${CRON_JOB_FILE}"
log_ok "Tarea cron creada."

# -----------------------------------------------------------------------------
# Seccion 14: Despliegue de la pila Docker
# -----------------------------------------------------------------------------
log_info "Iniciando la pila de servicios con Docker Compose..."
if ! docker compose -f "${RAG_LAB_DIR}/docker-compose.yml" up -d --wait; then
    fail_with "E006_DOCKER_COMPOSE_FAILED" "No se pudo iniciar la pila de Docker."
fi
log_ok "Pila de servicios Docker desplegada."

# -----------------------------------------------------------------------------
# Seccion 15: Pruebas de humo (Smoke Tests)
# -----------------------------------------------------------------------------
log_info "Ejecutando pruebas de humo..."
docker compose -f "${RAG_LAB_DIR}/docker-compose.yml" ps
if ! curl -fsS http://127.0.0.1:6333/ready > /dev/null; then fail_with "E007_QDRANT_HEALTHCHECK_FAILED"; fi
log_ok "Qdrant está operativo."
if ! curl -fsS "http://127.0.0.1:${OPENWEBUI_PORT}/health" > /dev/null; then fail_with "E008_OPENWEBUI_HEALTHCHECK_FAILED"; fi
log_ok "Open WebUI está operativo."

cat <<EOF > "${RAG_LAB_DIR}/documents/ejemplo.txt"
Bienvenido a RGIA Master. Su misión es simplificar la IA empresarial.
EOF
log_ok "Documento de prueba creado."

if ! "${RAG_LAB_DIR}/venv/bin/python" "${RAG_LAB_DIR}/scripts/ingestion_script.py"; then fail_with "E009_INGEST_FAILED"; fi
log_ok "Ingesta de prueba completada."

if ! "${RAG_LAB_DIR}/venv/bin/python" "${RAG_LAB_DIR}/scripts/query_agent.py" "¿Cuál es la misión de RGIA Master?"; then fail_with "E010_QUERY_FAILED"; fi
log_ok "Consulta de prueba completada."

# -----------------------------------------------------------------------------
# Seccion 16: Generación de archivos finales
# -----------------------------------------------------------------------------
log_info "Generando dashboard web interno estático..."
cat <<'EOF' > "${RAG_LAB_DIR}/web_internal/index.html"
<!DOCTYPE html>
<html lang="es" class="h-full bg-gray-900">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>RGIA Master - WebAdmin AI</title>
    <script src="https://cdn.tailwindcss.com"></script>
    <style>body { font-family: 'Inter', sans-serif; }</style>
</head>
<body class="h-full">
    <div class="min-h-full flex flex-col items-center justify-center p-6">
        <div class="w-full max-w-4xl text-center">
            <h1 class="text-4xl sm:text-5xl font-bold text-indigo-400 mb-4">RGIA Master - WebAdmin AI (Base)</h1>
            <p class="text-lg text-gray-400 mb-10">Tu centro de control para la plataforma de IA empresarial.</p>
            <div class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-6">
                <a href="http://localhost:3000" target="_blank" class="bg-gray-800 hover:bg-indigo-500 rounded-lg p-6 transition-transform transform hover:-translate-y-1">
                    <h2 class="text-xl font-semibold mb-2">Chat (Open WebUI)</h2>
                    <p class="text-gray-400">Acceso público para interactuar con el LLM.</p>
                </a>
                <a href="http://127.0.0.1:8080" target="_blank" class="bg-gray-800 hover:bg-green-500 rounded-lg p-6 transition-transform transform hover:-translate-y-1">
                    <h2 class="text-xl font-semibold mb-2">Gestor de Archivos</h2>
                    <p class="text-gray-400">Acceso vía túnel SSH.</p>
                </a>
                <a href="http://127.0.0.1:9000" target="_blank" class="bg-gray-800 hover:bg-sky-500 rounded-lg p-6 transition-transform transform hover:-translate-y-1">
                    <h2 class="text-xl font-semibold mb-2">Docker (Portainer)</h2>
                    <p class="text-gray-400">Acceso vía túnel SSH.</p>
                </a>
            </div>
        </div>
    </div>
</body>
</html>
EOF
log_ok "Dashboard web interno generado."

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
if [ -f "${SCRIPT_DIR}/README.md" ]; then
    cp "${SCRIPT_DIR}/README.md" "${RAG_LAB_DIR}/README.md"
    log_ok "README.md copiado al directorio de instalación."
fi

# -----------------------------------------------------------------------------
# Seccion 17: Resumen final de la instalación
# -----------------------------------------------------------------------------
echo -e "\n\n${BOLD}${GREEN}====================================================="
echo -e "  RGIA Master - RAG CPU Lab Instalado con Éxito"
echo -e "=====================================================${RESET}\n"
echo -e "Endpoints de Acceso:"
echo -e "  - Chat (Open WebUI): http://<IP_DEL_SERVIDOR>:${OPENWEBUI_PORT}"
echo -e "  - Gestor de Archivos (Filebrowser): http://127.0.0.1:8080 (requiere túnel SSH)"
echo -e "    - Usuario/Pass: ${FILEBROWSER_USER}/${FILEBROWSER_PASS}"
echo -e "  - Gestión de Docker (Portainer): http://127.0.0.1:9000 (requiere túnel SSH)"
echo -e "\nComando SSH recomendado para túnel:"
echo -e "  ssh -L 8080:127.0.0.1:8080 -L 9000:127.0.0.1:9000 usuario@<IP_DEL_SERVIDOR>"
echo -e "\nLogs:"
echo -e "  - Instalación: ${LOG_FILE}"
echo -e "  - Errores: ${ERROR_LOG_FILE}"
echo -e "  - Ingesta diaria: /var/log/rag_ingest.log"
exit 0
