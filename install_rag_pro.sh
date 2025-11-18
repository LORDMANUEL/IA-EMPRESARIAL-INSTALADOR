#!/usr/bin/env bash
#
# RGIA Master - RAG Pro Installer
# Mision: Simplificar y democratizar la adopción de IA empresarial en las organizaciones.
# Vision: Ser el estándar abierto de referencia para laboratorios de IA empresarial en Latinoamérica.
#

# -----------------------------------------------------------------------------
# Seccion 1: Configuracion inicial y seguridad del script
# -----------------------------------------------------------------------------
set -Eeuo pipefail

LOG_FILE="/var/log/rag_pro_install.log"
exec > >(tee -a "${LOG_FILE}") 2>&1

ERROR_LOG_FILE="/var/log/rag_pro_install_errors.log"

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
log_info "Iniciando la instalación de RGIA Master - RAG Pro..."

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
RAG_PRO_DIR="/opt/rag_pro"

OPENWEBUI_PORT=${OPENWEBUI_PORT:-3000}
EXPOSE_OLLAMA=${EXPOSE_OLLAMA:-false}
RAG_COLLECTION=${RAG_COLLECTION:-corporativo_pro_rag}
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
apt-get update -y || (sleep 5 && apt-get update -y) || fail_with "E000_APT_UPDATE_FAILED" "No se pudo actualizar la lista de paquetes."
log_ok "Lista de paquetes actualizada."

log_info "Instalando dependencias básicas..."
apt-get install -y curl ca-certificates htop python3 python3-venv python3-pip git jq
log_ok "Dependencias básicas instaladas."

log_info "Instalando dependencias Pro (Tesseract OCR)..."
apt-get install -y tesseract-ocr
log_ok "Tesseract OCR instalado."

# -----------------------------------------------------------------------------
# Seccion 6: Instalación y configuración de Docker y Docker Compose
# -----------------------------------------------------------------------------
if ! command -v docker &> /dev/null; then
    log_info "Instalando Docker Engine..."
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc || fail_with "E001_DOCKER_INSTALL_FAILED"
    chmod a+r /etc/apt/keyrings/docker.asc
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
    apt-get update -y
    apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin || fail_with "E001_DOCKER_INSTALL_FAILED"
    log_ok "Docker Engine instalado."
else
    log_info "Docker ya está instalado."
fi

systemctl start docker && systemctl enable docker
log_ok "Servicio Docker iniciado y habilitado."

# -----------------------------------------------------------------------------
# Seccion 7: Configuración del Firewall (UFW)
# -----------------------------------------------------------------------------
if command -v ufw &> /dev/null; then
    log_info "Configurando reglas de firewall..."
    ufw allow ssh && ufw allow "${OPENWEBUI_PORT}/tcp"
    [[ "${EXPOSE_OLLAMA}" == "true" ]] && ufw allow 11434/tcp
    echo "y" | ufw enable
    log_ok "Reglas de firewall aplicadas."
else
    log_warn "UFW no está instalado."
fi

# -----------------------------------------------------------------------------
# Seccion 8: Instalación y configuración de Ollama
# -----------------------------------------------------------------------------
if ! command -v ollama &> /dev/null; then
    log_info "Instalando Ollama..."
    curl -fsSL https://ollama.ai/install.sh | sh || fail_with "E002_OLLAMA_INSTALL_FAILED"
    log_ok "Ollama instalado."
else
    log_info "Ollama ya está instalado."
fi

log_info "Configurando Ollama para escuchar en ${OLLAMA_BIND}..."
mkdir -p /etc/systemd/system/ollama.service.d
cat <<EOF > /etc/systemd/system/ollama.service.d/override.conf
[Service]
Environment="OLLAMA_HOST=${OLLAMA_BIND}:11434"
EOF
systemctl daemon-reload && systemctl restart ollama
log_ok "Ollama configurado y reiniciado."

log_info "Descargando el modelo LLM: ${OLLAMA_MODEL}..."
ollama pull "${OLLAMA_MODEL}" || (sleep 15 && ollama pull "${OLLAMA_MODEL}") || (sleep 30 && ollama pull "${OLLAMA_MODEL}") || fail_with "E003_MODEL_PULL_FAILED"
log_ok "Modelo ${OLLAMA_MODEL} descargado."

# -----------------------------------------------------------------------------
# Seccion 9: Creación de la estructura de directorios
# -----------------------------------------------------------------------------
log_info "Creando estructura de directorios en ${RAG_PRO_DIR}..."
mkdir -p "${RAG_PRO_DIR}"/{documents,qdrant_storage,open_webui_data,scripts,logs,config,portainer,control_center}
log_ok "Estructura de directorios creada."

# -----------------------------------------------------------------------------
# Seccion 10: Generación de archivos de configuración y Docker
# -----------------------------------------------------------------------------
log_info "Generando archivo de configuración .env..."
cat <<EOF > "${RAG_PRO_DIR}/config/.env"
# Configuración para RGIA Master RAG Pro Lab
OPENWEBUI_PORT=${OPENWEBUI_PORT}
EXPOSE_OLLAMA=${EXPOSE_OLLAMA}
OLLAMA_BIND=${OLLAMA_BIND}
RAG_COLLECTION=${RAG_COLlection}
RAG_DOCS_DIR=${RAG_PRO_DIR}/documents
EMBEDDING_MODEL=${EMBEDDING_MODEL}
OLLAMA_MODEL=${OLLAMA_MODEL}
FILEBROWSER_USER=${FILEBROWSER_USER}
FILEBROWSER_PASS=${FILEBROWSER_PASS}
EOF
log_ok "Archivo .env creado."

log_info "Generando Dockerfile para el RGIA Control Center..."
cat <<'EOF' > "${RAG_PRO_DIR}/control_center/Dockerfile"
FROM python:3.11-slim
WORKDIR /app
RUN apt-get update && apt-get install -y --no-install-recommends build-essential && rm -rf /var/lib/apt/lists/*
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY . .
EXPOSE 8000
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000"]
EOF
log_ok "Dockerfile para Control Center generado."

log_info "Generando requirements.txt para el Control Center..."
cat <<'EOF' > "${RAG_PRO_DIR}/control_center/requirements.txt"
fastapi==0.111.0
uvicorn[standard]==0.29.0
python-dotenv==1.0.1
EOF
log_ok "requirements.txt para Control Center generado."

log_info "Generando aplicación FastAPI (main.py) para el Control Center..."
cat <<'EOF' > "${RAG_PRO_DIR}/control_center/main.py"
from fastapi import FastAPI, HTTPException
import subprocess, os
app = FastAPI(title="RGIA Master Pro - Control Center API")

@app.get("/")
def read_root(): return {"status": "ok", "message": "Bienvenido al RGIA Control Center API"}

@app.post("/ingest")
def trigger_ingestion():
    try:
        script_path = "/app/scripts/ingestion_script.py"
        if not os.path.exists(script_path): raise HTTPException(status_code=404, detail="Script no encontrado.")
        subprocess.Popen(["python", script_path], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        return {"status": "ok", "message": "Proceso de ingesta iniciado."}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))
EOF
log_ok "Aplicación FastAPI (main.py) generada."

log_info "Generando archivo docker-compose.yml..."
cat <<'EOF' > "${RAG_PRO_DIR}/docker-compose.yml"
version: '3.8'
services:
  qdrant:
    image: qdrant/qdrant:latest
    container_name: rag_pro_qdrant
    restart: unless-stopped
    ports: ["127.0.0.1:6333:6333"]
    volumes: ["./qdrant_storage:/qdrant/storage"]
    networks: [rag_pro_net]
    healthcheck: {test: ["CMD", "curl", "-f", "http://localhost:6333/ready"], interval: 10s, timeout: 5s, retries: 5}
  filebrowser:
    image: filebrowser/filebrowser:latest
    container_name: rag_pro_filebrowser
    restart: unless-stopped
    ports: ["127.0.0.1:8080:80"]
    volumes: ["./documents:/srv"]
    environment: {FB_USERNAME: '${FILEBROWSER_USER}', FB_PASSWORD: '${FILEBROWSER_PASS}'}
    networks: [rag_pro_net]
    healthcheck: {test: ["CMD", "wget", "--spider", "-q", "http://localhost:80/health"], interval: 10s, timeout: 5s, retries: 5}
  open-webui:
    image: ghcr.io/open-webui/open-webui:latest
    container_name: rag_pro_open_webui
    restart: unless-stopped
    ports: ["${OPENWEBUI_PORT}:8080"]
    volumes: ["./open_webui_data:/app/backend/data"]
    environment: {OLLAMA_BASE_URL: 'http://host.docker.internal:11434'}
    extra_hosts: ["host.docker.internal:host-gateway"]
    depends_on: {qdrant: {condition: service_healthy}}
    networks: [rag_pro_net]
    healthcheck: {test: ["CMD", "curl", "-f", "http://localhost:8080/health"], interval: 15s, timeout: 10s, retries: 5}
  portainer:
    image: portainer/portainer-ce:latest
    container_name: rag_pro_portainer
    restart: unless-stopped
    ports: ["127.0.0.1:9000:9000"]
    volumes: ["/var/run/docker.sock:/var/run/docker.sock", "./portainer:/data"]
    networks: [rag_pro_net]
    healthcheck: {test: ["CMD", "curl", "-f", "http://localhost:9000/api/status"], interval: 10s, timeout: 5s, retries: 5}
  control-center:
    build: {context: ./control_center}
    container_name: rag_pro_control_center
    restart: unless-stopped
    ports: ["127.0.0.1:8000:8000"]
    volumes: ["./scripts:/app/scripts", "./documents:/app/documents"]
    networks: [rag_pro_net]
    depends_on: [qdrant]
networks:
  rag_pro_net:
    driver: bridge
EOF
log_ok "Archivo docker-compose.yml creado."

# -----------------------------------------------------------------------------
# Seccion 11: Entorno Python para RAG
# -----------------------------------------------------------------------------
log_info "Creando entorno virtual de Python en ${RAG_PRO_DIR}/venv..."
python3 -m venv "${RAG_PRO_DIR}/venv" || fail_with "E004_VENV_CREATION_FAILED"
log_ok "Entorno virtual creado."

log_info "Generando archivo requirements.txt para ingesta..."
cat <<'EOF' > "${RAG_PRO_DIR}/config/requirements.txt"
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
pytesseract==0.3.10
pdf2image==1.17.0
Pillow==10.3.0
EOF
log_ok "Archivo requirements.txt creado."

log_info "Instalando dependencias de Python para ingesta..."
source "${RAG_PRO_DIR}/venv/bin/activate"
pip install --upgrade pip
pip install -r "${RAG_PRO_DIR}/config/requirements.txt" || fail_with "E005_PIP_INSTALL_FAILED"
deactivate
log_ok "Dependencias de Python instaladas."

# -----------------------------------------------------------------------------
# Seccion 12: Generación de scripts Python para RAG (Versión Pro)
# -----------------------------------------------------------------------------
log_info "Generando script de ingesta Multi-Modal (OCR)..."
cat <<'EOF' > "${RAG_PRO_DIR}/scripts/ingestion_script.py"
import os, hashlib, time
from pathlib import Path
from dotenv import load_dotenv
from tqdm import tqdm
import qdrant_client, pytesseract, pypdf
from pdf2image import convert_from_path
from llama_index.core import Document
from llama_index.core.node_parser import SentenceSplitter
from llama_index.core.embeddings import resolve_embed_model
from llama_index.vector_stores.qdrant import QdrantVectorStore

load_dotenv(dotenv_path=Path(__file__).parent.parent / 'config' / '.env')
RAG_DOCS_DIR = os.getenv("RAG_DOCS_DIR")
EMBEDDING_MODEL = os.getenv("EMBEDDING_MODEL")
RAG_COLLECTION = os.getenv("RAG_COLLECTION")

def extract_text_from_pdf(file_path):
    text = ""
    try:
        reader = pypdf.PdfReader(file_path)
        for page in reader.pages: text += page.extract_text() or ""
    except Exception as e: print(f"  [WARN] pypdf falló: {e}")
    try:
        images = convert_from_path(file_path)
        for image in images: text += pytesseract.image_to_string(image, lang='eng+spa')
    except Exception as e: print(f"  [WARN] OCR falló: {e}")
    return text

def process_documents():
    docs = []
    for root, _, files in os.walk(RAG_DOCS_DIR):
        for file in files:
            file_path = Path(root) / file
            if file_path.suffix.lower() not in {".pdf", ".txt", ".md"}: continue
            content = extract_text_from_pdf(str(file_path)) if file_path.suffix.lower() == ".pdf" else file_path.read_text(encoding='utf-8')
            if content.strip(): docs.append(Document(text=content, metadata={"file_path": str(file_path)}))
    return docs

def main():
    client = qdrant_client.QdrantClient(host="127.0.0.1", port=6333)
    try: client.get_collection(collection_name=RAG_COLLECTION)
    except Exception: client.create_collection(collection_name=RAG_COLLECTION, vectors_config=qdrant_client.http.models.VectorParams(size=384, distance=qdrant_client.http.models.Distance.COSINE))
    vector_store = QdrantVectorStore(client=client, collection_name=RAG_COLLECTION)

    docs = process_documents()
    if not docs: return print("No se encontraron nuevos documentos.")

    tracker_file = Path(os.getenv("RAG_PRO_DIR", "/opt/rag_pro")) / "logs" / f"processed_{RAG_COLLECTION}.log"
    processed_hashes = set(tracker_file.read_text().splitlines()) if tracker_file.exists() else set()

    new_docs = [doc for doc in docs if (doc_hash := hashlib.md5(doc.text.encode()).hexdigest()) not in processed_hashes and doc.metadata.update({"doc_hash": doc_hash})]

    if not new_docs: return print("No hay documentos nuevos para ingestar.")

    embed_model = resolve_embed_model(f"local:{EMBEDDING_MODEL}")
    nodes = SentenceSplitter(chunk_size=1024, chunk_overlap=100).get_nodes_from_documents(new_docs, show_progress=True)
    for node in nodes: node.embedding = embed_model.get_text_embedding(node.get_content(metadata_mode="all"))

    vector_store.add(nodes)
    with open(tracker_file, 'a') as f:
        for doc in new_docs: f.write(f"{doc.metadata['doc_hash']}\n")
    print(f"Ingesta de {len(nodes)} nuevos chunks completada.")

if __name__ == "__main__": main()
EOF
log_ok "Script de ingesta Pro (OCR) generado."

log_info "Generando script de consulta: query_agent.py..."
cat <<'EOF' > "${RAG_PRO_DIR}/scripts/query_agent.py"
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
log_info "Configurando tarea cron para la ingesta diaria Pro..."
CRON_JOB_FILE="/etc/cron.d/rag_pro_ingest"
CRON_JOB_CONTENT="0 3 * * * root ${RAG_PRO_DIR}/venv/bin/python ${RAG_PRO_DIR}/scripts/ingestion_script.py >> /var/log/rag_pro_ingest.log 2>&1"
echo "${CRON_JOB_CONTENT}" > "${CRON_JOB_FILE}"
chmod 0644 "${CRON_JOB_FILE}"
log_ok "Tarea cron Pro creada."

# -----------------------------------------------------------------------------
# Seccion 14: Despliegue de la pila Docker
# -----------------------------------------------------------------------------
log_info "Iniciando la pila de servicios Pro con Docker Compose..."
if ! docker compose -f "${RAG_PRO_DIR}/docker-compose.yml" up -d --build --wait; then
    fail_with "E006_DOCKER_COMPOSE_FAILED" "No se pudo iniciar la pila de Docker Pro."
fi
log_ok "Pila de servicios Docker Pro desplegada."

# -----------------------------------------------------------------------------
# Seccion 15: Pruebas de humo (Smoke Tests)
# -----------------------------------------------------------------------------
log_info "Ejecutando pruebas de humo para la versión Pro..."

docker compose -f "${RAG_PRO_DIR}/docker-compose.yml" ps

if ! curl -fsS http://127.0.0.1:6333/ready > /dev/null; then fail_with "E007_QDRANT_HEALTHCHECK_FAILED"; fi
log_ok "Qdrant (Pro) está operativo."

if ! curl -fsS "http://127.0.0.1:${OPENWEBUI_PORT}/health" > /dev/null; then fail_with "E008_OPENWEBUI_HEALTHCHECK_FAILED"; fi
log_ok "Open WebUI (Pro) está operativo."

if ! curl -fsS http://127.0.0.1:8000/ > /dev/null; then fail_with "E011_CONTROL_CENTER_HEALTHCHECK_FAILED"; fi
log_ok "RGIA Control Center está operativo."

cat <<EOF > "${RAG_PRO_DIR}/documents/ejemplo_pro.txt"
Bienvenido a RGIA Master Pro. La misión es potenciar la IA empresarial con OCR.
EOF
log_ok "Documento de prueba (Pro) creado."

if ! "${RAG_PRO_DIR}/venv/bin/python" "${RAG_PRO_DIR}/scripts/ingestion_script.py"; then fail_with "E009_INGEST_FAILED"; fi
log_ok "Ingesta de prueba (Pro) completada."

if ! "${RAG_PRO_DIR}/venv/bin/python" "${RAG_PRO_DIR}/scripts/query_agent.py" "¿Cuál es la misión de RGIA Master Pro?"; then fail_with "E010_QUERY_FAILED"; fi
log_ok "Consulta de prueba (Pro) completada."

# -----------------------------------------------------------------------------
# Seccion 16: Copia de archivos finales
# -----------------------------------------------------------------------------
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
if [ -f "${SCRIPT_DIR}/README.md" ]; then
    cp "${SCRIPT_DIR}/README.md" "${RAG_PRO_DIR}/README.md"
    log_ok "README.md copiado al directorio de instalación."
fi

# -----------------------------------------------------------------------------
# Seccion 17: Resumen final de la instalación
# -----------------------------------------------------------------------------
echo -e "\n\n${BOLD}${GREEN}====================================================="
echo -e "  RGIA Master - RAG Pro Lab Instalado con Éxito"
echo -e "=====================================================${RESET}\n"
echo -e "Endpoints de Acceso:"
echo -e "  - Chat (Open WebUI): http://<IP_DEL_SERVIDOR>:${OPENWEBUI_PORT}"
echo -e "  - Gestor de Archivos (Filebrowser): http://127.0.0.1:8080 (requiere túnel SSH)"
echo -e "  - Gestión de Docker (Portainer): http://127.0.0.1:9000 (requiere túnel SSH)"
echo -e "  - RGIA Control Center: http://127.0.0.1:8000 (requiere túnel SSH)"
echo -e "\nComando SSH recomendado para túnel:"
echo -e "  ssh -L 8080:127.0.0.1:8080 -L 9000:127.0.0.1:9000 -L 8000:127.0.0.1:8000 usuario@<IP_DEL_SERVIDOR>"
echo -e "\nLogs:"
echo -e "  - Instalación: ${LOG_FILE}"
echo -e "  - Errores: ${ERROR_LOG_FILE}"
echo -e "  - Ingesta diaria: /var/log/rag_pro_ingest.log"
exit 0
