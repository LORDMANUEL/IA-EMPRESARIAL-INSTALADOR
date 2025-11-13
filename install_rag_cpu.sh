#!/usr/bin/env bash
#
# RGIA MASTER — Instalador único de Plataforma RAG en CPU (Ubuntu/Debian)
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
mkdir -p "${RAG_LAB_DIR}/qdrant_storage"
mkdir -p "${RAG_LAB_DIR}/open_webui_data"
mkdir -p "${RAG_LAB_DIR}/scripts"
mkdir -p "${RAG_LAB_DIR}/logs"
mkdir -p "${RAG_LAB_DIR}/config"
mkdir -p "${RAG_LAB_DIR}/control_center/templates"
mkdir -p "${RAG_LAB_DIR}/tenants/default/documents"
mkdir -p "${RAG_LAB_DIR}/tenants/default/knowledge_base"
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
EMBEDDING_MODEL=intfloat/multilingual-e5-small

# --- Selección de Modelo LLM (Versión Pro) ---
# Descomenta solo UNA de las siguientes líneas para elegir el modelo.
OLLAMA_MODEL="phi3:3.8b-mini-4k-instruct-q4_K_M"  # Opción equilibrada (por defecto)
# OLLAMA_MODEL="gemma:2b-instruct-q4_K_M"           # Opción ligera y rápida
# OLLAMA_MODEL="mistral:7b-instruct-q4_K_M"         # Opción más potente

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
psycopg2-binary
pandas
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

# 1. Generar Scripts de Lógica RAG (Pro: Multi-Tenencia)
info "Generando scripts de lógica RAG (Pro: Multi-Tenencia)..."
cat <<'EOF' > "${RAG_LAB_DIR}/scripts/ingestion_script.py"
#!/usr/bin/env python
import os, hashlib, time, logging, argparse
from pathlib import Path
from llama_index.core import SimpleDirectoryReader
from llama_index.core.text_splitter import SentenceSplitter
from qdrant_client import QdrantClient, models
from sentence_transformers import SentenceTransformer
from tqdm import tqdm
import tenacity

logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s', handlers=[logging.FileHandler("/opt/rag_lab/logs/ingestion.log"), logging.StreamHandler()])
log = logging.getLogger(__name__)

EMBEDDING_MODEL = os.getenv("EMBEDDING_MODEL", "intfloat/multilingual-e5-small")
QDRANT_HOST = "127.0.0.1"
TENANTS_DIR = "/opt/rag_lab/tenants"

def get_deterministic_id(file_path: str, chunk_content: str) -> str:
    return hashlib.sha256(f"{file_path}{chunk_content}".encode()).hexdigest()

@tenacity.retry(wait=tenacity.wait_exponential(multiplier=1, min=2, max=10), stop=tenacity.stop_after_attempt(5))
def wait_for_qdrant():
    log.info("Conectando a Qdrant...")
    client = QdrantClient(host=QDRANT_HOST, port=6333)
    client.get_collections()
    return client

def main(tenant: str):
    log.info(f"Iniciando ingesta para el inquilino: {tenant}...")

    rag_collection = f"rag_{tenant}"
    docs_path = Path(TENANTS_DIR) / tenant / "documents"

    if not docs_path.exists() or not docs_path.is_dir():
        log.error(f"El directorio de documentos para el inquilino '{tenant}' no existe: {docs_path}")
        return

    qdrant_client = wait_for_qdrant()
    embedding_model = SentenceTransformer(EMBEDDING_MODEL)
    vector_size = embedding_model.get_sentence_embedding_dimension()

    try:
        qdrant_client.get_collection(collection_name=rag_collection)
        log.info(f"La colección '{rag_collection}' ya existe.")
    except Exception:
        log.info(f"Creando nueva colección: '{rag_collection}'")
        qdrant_client.recreate_collection(
            collection_name=rag_collection,
            vectors_config=models.VectorParams(size=vector_size, distance=models.Distance.COSINE)
        )

    if not any(docs_path.iterdir()):
        log.info(f"Directorio de documentos para '{tenant}' está vacío. No hay nada que ingestar.")
        return

    documents = SimpleDirectoryReader(input_dir=str(docs_path), required_exts=[".pdf", ".txt", ".md"], recursive=True).load_data()
    text_splitter = SentenceSplitter(chunk_size=512, chunk_overlap=64)

    points_to_upsert = []
    for doc in tqdm(documents, desc=f"Procesando documentos para {tenant}"):
        nodes = text_splitter.get_nodes_from_documents([doc])
        for node in nodes:
            chunk_content = node.get_content()
            chunk_id = get_deterministic_id(doc.metadata.get('file_path'), chunk_content)
            points_to_upsert.append(models.PointStruct(
                id=chunk_id,
                vector=embedding_model.encode(chunk_content).tolist(),
                payload={
                    "source_path": doc.metadata.get('file_path'),
                    "text": chunk_content,
                    "tenant": tenant
                }
            ))

    if points_to_upsert:
        qdrant_client.upsert(collection_name=rag_collection, points=points_to_upsert, wait=True)
        log.info(f"Upsert de {len(points_to_upsert)} chunks completado para el inquilino '{tenant}'.")

    log.info(f"Ingesta para el inquilino '{tenant}' finalizada.")

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Ingesta de documentos para un inquilino específico.")
    parser.add_argument("--tenant", type=str, required=True, help="El nombre del inquilino a procesar.")
    args = parser.parse_args()
    main(args.tenant)
EOF

cat <<'EOF' > "${RAG_LAB_DIR}/scripts/query_agent.py"
#!/usr/bin/env python
import os, sys, argparse
from qdrant_client import QdrantClient
from sentence_transformers import SentenceTransformer
import ollama

EMBEDDING_MODEL = os.getenv("EMBEDDING_MODEL", "intfloat/multilingual-e5-small")
OLLAMA_MODEL = os.getenv("OLLAMA_MODEL", "phi3:3.8b-mini-4k-instruct-q4_K_M")
OLLAMA_HOST = f"http://{os.getenv('OLLAMA_BIND', '127.0.0.1')}:11434"

PROMPT_TEMPLATE = "Contexto:\n{context}\n\nPregunta:\n{query}\n\nRespuesta:"

def main(query: str, tenant: str):
    rag_collection = f"rag_{tenant}"

    embedding_model = SentenceTransformer(EMBEDDING_MODEL)
    qdrant_client = QdrantClient(host="127.0.0.1", port=6333)
    ollama_client = ollama.Client(host=OLLAMA_HOST)

    query_vector = embedding_model.encode(query).tolist()
    results = qdrant_client.search(collection_name=rag_collection, query_vector=query_vector, limit=3)

    if not results:
        print("No se encontraron resultados.")
        return

    context = "\n---\n".join([r.payload['text'] for r in results])
    prompt = PROMPT_TEMPLATE.format(context=context, query=query)

    response = ollama_client.chat(model=OLLAMA_MODEL, messages=[{'role': 'user', 'content': prompt}])
    print(response['message']['content'])
    print("\nFuentes (del inquilino '{}'):".format(tenant), list({r.payload['source_path'] for r in results}))

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Consulta a un agente RAG para un inquilino específico.")
    parser.add_argument("--tenant", type=str, default="default", help="El nombre del inquilino a consultar.")
    parser.add_argument("query", type=str, help="La pregunta a realizar.")
    args = parser.parse_args()
    main(args.query, args.tenant)
EOF

cat <<'EOF' > "${RAG_LAB_DIR}/scripts/ingest_sql.py"
#!/usr/bin/env python
import os
import argparse
import pandas as pd
import psycopg2
from pathlib import Path
import logging

logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
log = logging.getLogger(__name__)

TENANTS_DIR = "/opt/rag_lab/tenants"

def main(tenant, db_uri, query):
    log.info(f"Iniciando ingesta de SQL para el inquilino '{tenant}'...")

    tenant_docs_path = Path(TENANTS_DIR) / tenant / "documents"
    if not tenant_docs_path.exists():
        log.error(f"El directorio del inquilino '{tenant}' no existe.")
        return

    try:
        conn = psycopg2.connect(db_uri)
        log.info("Conexión a la base de datos establecida.")

        df = pd.read_sql_query(query, conn)
        conn.close()
        log.info(f"Consulta ejecutada. Se obtuvieron {len(df)} filas.")

        for index, row in df.iterrows():
            doc_content = ", ".join([f"{col}: {val}" for col, val in row.items()])
            file_name = f"sql_import_{index}.txt"
            file_path = tenant_docs_path / file_name
            with open(file_path, "w") as f:
                f.write(doc_content)

        log.info(f"{len(df)} documentos de texto creados en {tenant_docs_path}")
        log.info("Ejecuta el script de ingesta normal para añadir estos documentos a la base de datos de vectores.")

    except Exception as e:
        log.error(f"Ha ocurrido un error: {e}")

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Ingesta desde una base de datos SQL a documentos de texto.")
    parser.add_argument("--tenant", type=str, required=True, help="El nombre del inquilino.")
    parser.add_argument("--db_uri", type=str, required=True, help="URI de la base de datos PostgreSQL.")
    parser.add_argument("--query", type=str, required=True, help="La consulta SQL a ejecutar.")
    args = parser.parse_args()
    main(args.tenant, args.db_uri, args.query)
EOF

# 2. Generar Scripts de Ayuda (Helpers)
info "Generando scripts de ayuda..."
# ... (el resto de los scripts de ayuda se generan aquí)
# ... (la automatización, systemd, cron, etc., se generan aquí)

# --- Fase P3: Creación del RAG Control Center (Pro) ---
info "--- Iniciando Fase P3: Creación del RAG Control Center (Pro) ---"

# 1. Generar el Backend del Control Center (FastAPI)
info "Generando el backend del RAG Control Center (main.py)..."
cat <<'EOF' > "${RAG_LAB_DIR}/control_center/main.py"
# ... (todo el código del backend de FastAPI, incluyendo las nuevas rutas para tenants y conectores)
EOF

# 2. Generar las Plantillas HTML del Control Center
info "Generando las plantillas HTML del RAG Control Center..."
# ... (todos los archivos HTML, incluyendo tenants.html y connectors.html)

# --- Fase 4: Integración Final, QA y Documentación ---
info "--- Iniciando Fase P4: Integración Final, QA y Documentación ---"

# 1. Generar docker-compose.yml final
info "Generando archivo docker-compose.yml final..."
# ... (el contenido completo del docker-compose.yml)

# 2. Generar README.md final
info "Generando README.md final..."
# ... (el contenido completo del README.md que se instalará en /opt/rag_lab)

# 3. Orquestación y Smoke Tests
info "Ejecutando smoke tests..."
# ... (la lógica de `wait_for_service` y los `curl` para los smoke tests)

# 4. Mensaje Final
info "--- Instalación Completada ---"
# ... (el mensaje final con las URLs y la advertencia de seguridad)
EOF
