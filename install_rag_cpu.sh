#!/usr/bin/env bash
#
# RGIA Master - RAG CPU Lab Installer
# Mision: Simplificar y democratizar la adopción de IA empresarial en las organizaciones.
# Vision: Ser el estándar abierto de referencia para laboratorios de IA empresarial en Latinoamérica.
#

# -----------------------------------------------------------------------------
# Seccion 1: Configuracion inicial y seguridad del script
# -----------------------------------------------------------------------------
# - `set -Eeuo pipefail`: Salir inmediatamente si un comando falla (`e`), si una
#   variable no está definida (`u`), o si un comando en una tubería falla (`pipefail`).
#   La opción `E` asegura que las trampas de error se hereden en funciones y subshells.
set -Eeuo pipefail

# - Redirección de toda la salida (stdout y stderr) a un archivo de log global.
#   `tee` se usa para que la salida también se muestre en la terminal.
LOG_FILE="/var/log/rag_install.log"
exec > >(tee -a "${LOG_FILE}") 2>&1

# - Archivo de log específico para errores fatales.
ERROR_LOG_FILE="/var/log/rag_install_errors.log"

# -----------------------------------------------------------------------------
# Seccion 2: Funciones de logging y manejo de errores
# -----------------------------------------------------------------------------
# Estas funciones proporcionan un sistema de logging consistente y un manejo
# de errores centralizado, facilitando el diagnóstico y la depuración.

# Códigos de color para los mensajes en la terminal
RESET="\033[0m"
BOLD="\033[1m"
RED="\033[0;31m"
GREEN="\033[0;32m"
YELLOW="\033[0;33m"
BLUE="\033[0;34m"

log_info() {
    echo -e "${BLUE}[INFO] $(date '+%Y-%m-%d %H:%M:%S') - ${1}${RESET}"
}

log_ok() {
    echo -e "${GREEN}[OK] $(date '+%Y-%m-%d %H:%M:%S') - ${1}${RESET}"
}

log_warn() {
    echo -e "${YELLOW}[WARN] $(date '+%Y-%m-%d %H:%M:%S') - ${1}${RESET}"
}

log_error() {
    echo -e "${RED}[ERROR] $(date '+%Y-%m-%d %H:%M:%S') - ${1}${RESET}"
}

# La función `fail_with` termina el script de forma controlada.
# Recibe un código de error y un mensaje descriptivo.
fail_with() {
    local error_code="$1"
    local message="$2"
    log_error "${error_code} - ${message}"
    echo "$(date '+%Y-%m-%d %H:%M:%S') - ${error_code} - ${message}" >> "${ERROR_LOG_FILE}"
    echo -e "\n${BOLD}${RED}Instalación fallida. Código de error: ${error_code}.${RESET}"
    echo -e "${YELLOW}Por favor, revise los logs en ${LOG_FILE} y la sección 'Errores comunes' en el README.md para solucionar el problema.${RESET}"
    exit 1
}

# Trampa de errores: se ejecuta si cualquier comando falla y el script termina.
trap 'fail_with "E999_UNEXPECTED_ERROR" "El script terminó inesperadamente en la línea ${LINENO}."' ERR

# -----------------------------------------------------------------------------
# Seccion 3: Verificación inicial del sistema (Preflight)
# -----------------------------------------------------------------------------
# Antes de realizar cualquier cambio, se comprueba que el entorno es adecuado.

log_info "Iniciando la instalación de RGIA Master - RAG CPU Lab..."

# 3.1. Comprobar si se ejecuta como root
if [[ "${EUID}" -ne 0 ]]; then
    fail_with "E000_NOT_ROOT" "Este script debe ser ejecutado con privilegios de root (sudo)."
fi

# 3.2. Detección de la distribución (solo Ubuntu/Debian)
if ! command -v lsb_release &> /dev/null || ! lsb_release -is | grep -qE 'Ubuntu|Debian'; then
    fail_with "E000_UNSUPPORTED_OS" "Este script está diseñado para Ubuntu o Debian."
fi

# 3.3. Configurar entorno no interactivo para `apt`
export DEBIAN_FRONTEND=noninteractive

# -----------------------------------------------------------------------------
# Seccion 4: Definición de variables globales y de configuración
# -----------------------------------------------------------------------------
# Centralizar la configuración facilita la personalización y el mantenimiento.

# Directorio base de la plataforma RAG
RAG_LAB_DIR="/opt/rag_lab"

# Variables de configuración para el archivo .env
# Estas se pueden sobreescribir si ya existe un .env y queremos ser idempotentes.
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
    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
      $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
      tee /etc/apt/sources.list.d/docker.list > /dev/null
    apt-get update -y
    if ! apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin; then
        fail_with "E001_DOCKER_INSTALL_FAILED" "No se pudieron instalar los paquetes de Docker."
    fi
    log_ok "Docker Engine instalado correctamente."
else
    log_info "Docker ya está instalado. Omitiendo instalación."
fi

# Asegurarse de que el servicio Docker esté activo y habilitado
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
    # Habilitar UFW de forma no interactiva
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
# Crear un override para el servicio systemd de Ollama
mkdir -p /etc/systemd/system/ollama.service.d
cat <<EOF > /etc/systemd/system/ollama.service.d/override.conf
[Service]
Environment="OLLAMA_HOST=${OLLAMA_BIND}:11434"
EOF

systemctl daemon-reload
systemctl restart ollama
log_ok "Ollama configurado y reiniciado."

log_info "Descargando el modelo LLM: ${OLLAMA_MODEL}. Esto puede tardar varios minutos..."
# Intentar descargar el modelo con reintentos
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
# Este archivo es leído por docker-compose y los scripts de Python.

# Puerto para Open WebUI (accesible desde el exterior)
OPENWEBUI_PORT=${OPENWEBUI_PORT}

# Exponer la API de Ollama a la red local (true/false)
EXPOSE_OLLAMA=${EXPOSE_OLLAMA}

# IP en la que Ollama debe escuchar (0.0.0.0 para exponer, 127.0.0.1 para local)
OLLAMA_BIND=${OLLAMA_BIND}

# Nombre de la colección en la base de datos vectorial Qdrant
RAG_COLLECTION=${RAG_COLLECTION}

# Directorio donde se almacenan los documentos para ingesta
RAG_DOCS_DIR=${RAG_LAB_DIR}/documents

# Modelo de embedding a utilizar (compatible con Sentence-Transformers)
EMBEDDING_MODEL=${EMBEDDING_MODEL}

# Modelo de lenguaje a utilizar con Ollama
OLLAMA_MODEL=${OLLAMA_MODEL}

# Credenciales para el gestor de archivos Filebrowser
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
      - "127.0.0.1:6334:6334"
    volumes:
      - ./qdrant_storage:/qdrant/storage
    networks:
      - rag_net
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:6333/ready"]
      interval: 10s
      timeout: 5s
      retries: 5

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
    healthcheck:
      test: ["CMD", "wget", "--spider", "-q", "http://localhost:80/health"]
      interval: 10s
      timeout: 5s
      retries: 5

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
      qdrant:
        condition: service_healthy
    networks:
      - rag_net
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8080/health"]
      interval: 15s
      timeout: 10s
      retries: 5

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
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:9000/api/status"]
      interval: 10s
      timeout: 5s
      retries: 5

networks:
  rag_net:
    driver: bridge
EOF
log_ok "Archivo docker-compose.yml creado en ${RAG_LAB_DIR}/docker-compose.yml."

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

log_info "Instalando dependencias de Python. Esto puede tardar unos minutos..."
# shellcheck source=/dev/null
source "${RAG_LAB_DIR}/venv/bin/activate"
pip install --upgrade pip
if ! pip install -r "${RAG_LAB_DIR}/config/requirements.txt"; then
    fail_with "E005_PIP_INSTALL_FAILED" "No se pudieron instalar las dependencias de Python."
fi
deactivate
log_ok "Dependencias de Python instaladas en el entorno virtual."

# -----------------------------------------------------------------------------
# Seccion 12: Generación de scripts Python para RAG
# -----------------------------------------------------------------------------

log_info "Generando script de ingesta: ingestion_script.py..."
cat <<'EOF' > "${RAG_LAB_DIR}/scripts/ingestion_script.py"
import os
import hashlib
import time
from pathlib import Path
from dotenv import load_dotenv
from tqdm import tqdm
import qdrant_client
from llama_index.core import SimpleDirectoryReader, Document
from llama_index.core.node_parser import SentenceSplitter
from llama_index.core.embeddings import resolve_embed_model
from llama_index.vector_stores.qdrant import QdrantVectorStore

# --- Configuración y Carga de Entorno ---
print("Iniciando script de ingesta de documentos...")

# Cargar variables de entorno desde el archivo .env en el directorio de configuración
config_dir = Path(__file__).parent.parent / 'config'
dotenv_path = config_dir / '.env'
load_dotenv(dotenv_path=dotenv_path)

RAG_DOCS_DIR = os.getenv("RAG_DOCS_DIR", "/opt/rag_lab/documents")
EMBEDDING_MODEL = os.getenv("EMBEDDING_MODEL", "local:intfloat/multilingual-e5-small")
RAG_COLLECTION = os.getenv("RAG_COLLECTION", "corporativo_rag")
QDRANT_HOST = "127.0.0.1"
QDRANT_PORT = 6333

print(f"Directorio de documentos: {RAG_DOCS_DIR}")
print(f"Modelo de embedding: {EMBEDDING_MODEL}")
print(f"Colección Qdrant: {RAG_COLLECTION}")

# --- Funciones Auxiliares ---

def generate_doc_id(file_path, content):
    """Genera un ID único para un documento basado en su ruta y contenido."""
    return hashlib.md5(f"{file_path}{content}".encode()).hexdigest()

def get_processed_files_tracker(collection_name):
    """Crea un archivo para rastrear documentos ya procesados y evitar duplicados."""
    tracker_dir = Path("/opt/rag_lab/logs")
    tracker_dir.mkdir(exist_ok=True)
    return tracker_dir / f"processed_{collection_name}.log"

# --- Script Principal ---

def main():
    try:
        # 1. Conexión a Qdrant
        print("\nConectando al cliente Qdrant...")
        client = qdrant_client.QdrantClient(host=QDRANT_HOST, port=QDRANT_PORT)
        print("Conexión a Qdrant exitosa.")

        # Comprobar si la colección ya existe, si no, crearla.
        try:
            client.get_collection(collection_name=RAG_COLLECTION)
            print(f"La colección '{RAG_COLLECTION}' ya existe.")
        except Exception:
            print(f"La colección '{RAG_COLLECTION}' no existe. Creando...")
            # El tamaño del vector depende del modelo de embedding.
            # `multilingual-e5-small` tiene una dimensionalidad de 384.
            client.create_collection(
                collection_name=RAG_COLLECTION,
                vectors_config=qdrant_client.http.models.VectorParams(size=384, distance=qdrant_client.http.models.Distance.COSINE)
            )
            print("Colección creada.")

        vector_store = QdrantVectorStore(client=client, collection_name=RAG_COLLECTION)

        # 2. Cargar documentos del directorio
        print(f"\nCargando documentos desde {RAG_DOCS_DIR}...")
        reader = SimpleDirectoryReader(RAG_DOCS_DIR, recursive=True)
        docs = reader.load_data()

        if not docs:
            print("No se encontraron nuevos documentos para procesar. Finalizando.")
            return

        print(f"Se encontraron {len(docs)} documentos.")

        # 3. Preparar el modelo de embedding
        print(f"Cargando modelo de embedding '{EMBEDDING_MODEL}'...")
        # El prefijo 'local:' indica a LlamaIndex que use un modelo local de sentence-transformers
        embed_model = resolve_embed_model(EMBEDDING_MODEL)
        print("Modelo de embedding cargado.")

        # 4. Procesamiento de documentos (chunking y embedding)
        print("\nProcesando documentos (chunking y embedding)...")
        # El 'node_parser' se encarga de dividir los documentos en fragmentos (chunks)
        node_parser = SentenceSplitter(chunk_size=512, chunk_overlap=50)

        # Archivo para rastrear documentos ya procesados
        tracker_file = get_processed_files_tracker(RAG_COLLECTION)
        processed_hashes = set()
        if tracker_file.exists():
            with open(tracker_file, 'r') as f:
                processed_hashes = set(line.strip() for line in f)
        print(f"Se encontraron {len(processed_hashes)} documentos previamente procesados.")

        new_nodes_to_ingest = []
        for doc in tqdm(docs, desc="Procesando documentos"):
            doc_hash = generate_doc_id(doc.metadata.get('file_path'), doc.text)

            if doc_hash in processed_hashes:
                continue

            # Obtener los "nodos" (chunks) del documento
            nodes = node_parser.get_nodes_from_documents([doc])

            # Generar embeddings para cada nodo
            for i, node in enumerate(nodes):
                node.embedding = embed_model.get_text_embedding(node.get_content(metadata_mode="all"))
                node.metadata["document_hash"] = doc_hash
                node.metadata["chunk_id"] = f"{doc_hash}_{i}"

            new_nodes_to_ingest.extend(nodes)
            processed_hashes.add(doc_hash)

        # 5. Ingesta en Qdrant
        if new_nodes_to_ingest:
            print(f"\nIngestando {len(new_nodes_to_ingest)} nuevos chunks en Qdrant...")
            vector_store.add(new_nodes_to_ingest)
            print("Ingesta completada.")

            # Actualizar el archivo de seguimiento
            with open(tracker_file, 'a') as f:
                for doc in docs:
                    doc_hash = generate_doc_id(doc.metadata.get('file_path'), doc.text)
                    if doc_hash in processed_hashes:
                         # Escribir solo los nuevos hashes
                         f.write(f"{doc_hash}\n")
        else:
            print("\nNo hay nuevos chunks para ingestar.")

    except Exception as e:
        print(f"\n[ERROR] Ocurrió un error durante la ingesta: {e}")
        exit(1)

    print("\n--- Script de ingesta finalizado ---")

if __name__ == "__main__":
    start_time = time.time()
    main()
    end_time = time.time()
    print(f"Tiempo total de ejecución: {end_time - start_time:.2f} segundos.")
EOF
log_ok "Script de ingesta generado."

log_info "Generando script de consulta: query_agent.py..."
cat <<'EOF' > "${RAG_LAB_DIR}/scripts/query_agent.py"
import os
import sys
import textwrap
from pathlib import Path
from dotenv import load_dotenv
import qdrant_client
from llama_index.core.vector_stores import VectorStoreQuery
from llama_index.core.embeddings import resolve_embed_model
from llama_index.vector_stores.qdrant import QdrantVectorStore
import ollama

# --- Configuración y Carga de Entorno ---
print("Iniciando agente de consulta RAG...")

# Cargar variables de entorno
config_dir = Path(__file__).parent.parent / 'config'
dotenv_path = config_dir / '.env'
load_dotenv(dotenv_path=dotenv_path)

RAG_COLLECTION = os.getenv("RAG_COLLECTION", "corporativo_rag")
EMBEDDING_MODEL = os.getenv("EMBEDDING_MODEL", "local:intfloat/multilingual-e5-small")
OLLAMA_MODEL = os.getenv("OLLAMA_MODEL", "phi3:3.8b-mini-4k-instruct-q4_K_M")
OLLAMA_BIND = os.getenv("OLLAMA_BIND", "127.0.0.1")
OLLAMA_URL = f"http://{OLLAMA_BIND}:11434"
QDRANT_HOST = "127.0.0.1"
QDRANT_PORT = 6333

print(f"Usando modelo LLM: {OLLAMA_MODEL} en {OLLAMA_URL}")
print(f"Usando colección Qdrant: {RAG_COLLECTION}")

# --- Funciones Auxiliares ---

def format_prompt(query, context_str):
    """Formatea el prompt para el modelo de lenguaje, incluyendo el contexto recuperado."""
    prompt = f"""
    Eres un asistente experto que responde preguntas basándose únicamente en el contexto proporcionado.
    Si la respuesta no se encuentra en el contexto, indica que no tienes suficiente información.
    No inventes respuestas. Sé conciso y directo.

    Contexto recuperado:
    --------------------
    {context_str}
    --------------------

    Pregunta del usuario:
    {query}

    Respuesta:
    """
    return textwrap.dedent(prompt)

# --- Script Principal ---

def main(query_text):
    try:
        # 1. Conexión a Qdrant y al modelo de embedding
        print("\nConectando a Qdrant y cargando modelo de embedding...")
        client = qdrant_client.QdrantClient(host=QDRANT_HOST, port=QDRANT_PORT)
        embed_model = resolve_embed_model(EMBEDDING_MODEL)
        vector_store = QdrantVectorStore(client=client, collection_name=RAG_COLLECTION)
        print("Conexión exitosa.")

        # 2. Generar embedding para la consulta del usuario
        print("Generando embedding para la consulta...")
        query_embedding = embed_model.get_text_embedding(query_text)

        # 3. Realizar la búsqueda de similitud en Qdrant
        print("Buscando contexto relevante en la base de datos vectorial...")
        query_obj = VectorStoreQuery(query_embedding=query_embedding, similarity_top_k=5)
        retrieval_results = vector_store.query(query_obj)

        if not retrieval_results.nodes:
            print("\n[ADVERTENCIA] No se encontró contexto relevante para la consulta.")
            # Aún así, intentaremos responder con el conocimiento general del modelo.
            context_str = "No se encontró información relevante en los documentos."
        else:
            print(f"Se recuperaron {len(retrieval_results.nodes)} fragmentos de contexto.")
            # Imprimir información sobre los fragmentos recuperados para depuración
            print("\n--- Contexto Recuperado (para depuración) ---")
            for i, node in enumerate(retrieval_results.nodes):
                print(f"  Fragmento {i+1} (Score: {retrieval_results.similarities[i]:.4f}):")
                print(f"    Fuente: {node.metadata.get('file_name', 'N/A')}")
                print(f"    Contenido: '{textwrap.shorten(node.get_content(), width=100, placeholder='...')}'")
            print("------------------------------------------")

            context_str = "\n\n".join([node.get_content() for node in retrieval_results.nodes])

        # 4. Construir el prompt y llamar a Ollama
        prompt = format_prompt(query_text, context_str)
        print("\nGenerando respuesta con el modelo LLM...")

        # Conectar al cliente de Ollama
        ollama_client = ollama.Client(host=OLLAMA_URL)

        response = ollama_client.chat(
            model=OLLAMA_MODEL,
            messages=[{'role': 'user', 'content': prompt}]
        )

        # 5. Imprimir la respuesta final
        print("\n========= Respuesta del Asistente IA =========\n")
        print(textwrap.fill(response['message']['content'], width=100))
        print("\n============================================\n")

    except Exception as e:
        print(f"\n[ERROR] Ocurrió un error durante la consulta: {e}")
        exit(1)

if __name__ == "__main__":
    if len(sys.argv) > 1:
        user_query = " ".join(sys.argv[1:])
    else:
        user_query = "¿Qué es RGIA Master?"
        print(f"No se proporcionó una consulta. Usando consulta de ejemplo: '{user_query}'")

    main(user_query)
EOF
log_ok "Script de consulta generado."


# -----------------------------------------------------------------------------
# Seccion 13: Automatización (Cron job)
# -----------------------------------------------------------------------------
log_info "Configurando tarea cron para la ingesta diaria de documentos..."
CRON_JOB_FILE="/etc/cron.d/rag_ingest"
CRON_JOB_CONTENT="0 3 * * * root ${RAG_LAB_DIR}/venv/bin/python ${RAG_LAB_DIR}/scripts/ingestion_script.py >> /var/log/rag_ingest.log 2>&1"

echo "${CRON_JOB_CONTENT}" > "${CRON_JOB_FILE}"
chmod 0644 "${CRON_JOB_FILE}"
log_ok "Tarea cron creada en ${CRON_JOB_FILE}."

# -----------------------------------------------------------------------------
# Seccion 14: Despliegue de la pila Docker
# -----------------------------------------------------------------------------
log_info "Iniciando la pila de servicios con Docker Compose..."
if ! docker compose -f "${RAG_LAB_DIR}/docker-compose.yml" up -d --wait; then
    fail_with "E006_DOCKER_COMPOSE_FAILED" "No se pudo iniciar la pila de Docker. Revisa los logs con 'docker compose -f ${RAG_LAB_DIR}/docker-compose.yml logs'."
fi
log_ok "Pila de servicios Docker desplegada correctamente."

# -----------------------------------------------------------------------------
# Seccion 15: Pruebas de humo (Smoke Tests)
# -----------------------------------------------------------------------------
log_info "Ejecutando pruebas de humo para verificar la instalación..."

# 15.1. Verificar estado de los contenedores
log_info "Comprobando estado de los contenedores Docker..."
docker compose -f "${RAG_LAB_DIR}/docker-compose.yml" ps
if ! docker compose -f "${RAG_LAB_DIR}/docker-compose.yml" ps | grep -q "running"; then
    log_warn "Algunos contenedores podrían no estar en estado 'running'."
fi

# 15.2. Healthcheck de Qdrant
log_info "Verificando salud de Qdrant..."
if ! curl -fsS http://127.0.0.1:6333/ready > /dev/null; then
    fail_with "E007_QDRANT_HEALTHCHECK_FAILED" "El healthcheck de Qdrant falló."
fi
log_ok "Qdrant está operativo."

# 15.3. Healthcheck de Open WebUI
log_info "Verificando salud de Open WebUI..."
if ! curl -fsS "http://127.0.0.1:${OPENWEBUI_PORT}/health" > /dev/null; then
     fail_with "E008_OPENWEBUI_HEALTHCHECK_FAILED" "El healthcheck de Open WebUI falló."
fi
log_ok "Open WebUI está operativo."

# 15.4. Prueba de ingesta y consulta
log_info "Ejecutando prueba de ingesta y consulta de extremo a extremo..."
# Crear un documento de prueba
log_info "Creando documento de prueba..."
cat <<EOF > "${RAG_LAB_DIR}/documents/ejemplo.txt"
Bienvenido a RGIA Master.
La misión de RGIA Master es simplificar y democratizar la adopción de IA empresarial.
Esta plataforma es un laboratorio RAG que funciona 100% en CPU.
EOF
log_ok "Documento de prueba creado."

# Ejecutar script de ingesta
log_info "Ejecutando ingesta de prueba..."
if ! "${RAG_LAB_DIR}/venv/bin/python" "${RAG_LAB_DIR}/scripts/ingestion_script.py"; then
    fail_with "E009_INGEST_FAILED" "La prueba de ingesta falló."
fi
log_ok "Ingesta de prueba completada."

# Ejecutar script de consulta
log_info "Ejecutando consulta de prueba..."
QUERY="¿Cuál es la misión de RGIA Master?"
if ! "${RAG_LAB_DIR}/venv/bin/python" "${RAG_LAB_DIR}/scripts/query_agent.py" "${QUERY}"; then
    fail_with "E010_QUERY_FAILED" "La prueba de consulta falló."
fi
log_ok "Consulta de prueba completada."

# -----------------------------------------------------------------------------
# Seccion 16: Generación de archivos finales (Web Interna y README)
# -----------------------------------------------------------------------------
log_info "Generando dashboard web interno..."
cat <<'EOF' > "${RAG_LAB_DIR}/web_internal/index.html"
<!DOCTYPE html>
<html lang="es" class="h-full bg-gray-900">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>RGIA Master - WebAdmin AI</title>
    <script src="https://cdn.tailwindcss.com"></script>
    <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.5.1/css/all.min.css">
    <style>
        body { font-family: 'Inter', sans-serif; }
    </style>
</head>
<body class="h-full">
    <div class="min-h-full flex flex-col items-center justify-center bg-gray-900 text-white p-4 sm:p-6 lg:p-8">
        <div class="w-full max-w-4xl text-center">
            <h1 id="main-heading" class="text-4xl sm:text-5xl font-bold text-indigo-400 mb-4">RGIA Master - WebAdmin AI</h1>
            <p class="text-lg text-gray-400 mb-10">Tu centro de control para la plataforma de IA empresarial.</p>

            <div class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-6">
                <!-- Open WebUI -->
                <a href="http://localhost:3000" target="_blank" class="bg-gray-800 hover:bg-indigo-500 hover:shadow-lg hover:shadow-indigo-500/50 rounded-lg p-6 transition-all duration-300 transform hover:-translate-y-1">
                    <i class="fas fa-comments text-4xl text-indigo-400 mb-4"></i>
                    <h2 class="text-xl font-semibold mb-2">Chat (Open WebUI)</h2>
                    <p class="text-gray-400">Interactúa con tus documentos y el LLM. (Acceso público)</p>
                </a>

                <!-- Filebrowser -->
                <a href="http://127.0.0.1:8080" target="_blank" class="bg-gray-800 hover:bg-green-500 hover:shadow-lg hover:shadow-green-500/50 rounded-lg p-6 transition-all duration-300 transform hover:-translate-y-1">
                    <i class="fas fa-folder-open text-4xl text-green-400 mb-4"></i>
                    <h2 class="text-xl font-semibold mb-2">Gestor de Archivos</h2>
                    <p class="text-gray-400">Sube y gestiona tus documentos. (Acceso vía túnel SSH)</p>
                </a>

                <!-- Portainer -->
                <a href="http://127.0.0.1:9000" target="_blank" class="bg-gray-800 hover:bg-sky-500 hover:shadow-lg hover:shadow-sky-500/50 rounded-lg p-6 transition-all duration-300 transform hover:-translate-y-1">
                    <i class="fas fa-docker text-4xl text-sky-400 mb-4"></i>
                    <h2 class="text-xl font-semibold mb-2">Docker (Portainer)</h2>
                    <p class="text-gray-400">Administra tus contenedores. (Acceso vía túnel SSH)</p>
                </a>
            </div>
        </div>
    </div>
</body>
</html>
EOF
log_ok "Dashboard web interno generado en ${RAG_LAB_DIR}/web_internal/index.html"

# Copiar el README.md desde el directorio del script
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
if [ -f "${SCRIPT_DIR}/README.md" ]; then
    log_info "Copiando README.md a ${RAG_LAB_DIR}/..."
    cp "${SCRIPT_DIR}/README.md" "${RAG_LAB_DIR}/README.md"
    log_ok "README.md copiado."
else
    log_warn "No se encontró 'README.md' en el directorio del script. Omitiendo copia."
fi


# -----------------------------------------------------------------------------
# Seccion 17: Resumen final de la instalación
# -----------------------------------------------------------------------------
echo -e "\n\n${BOLD}${GREEN}====================================================="
echo -e "  RGIA Master - RAG CPU Lab Instalado con Éxito"
echo -e "=====================================================${RESET}\n"
echo -e "${BOLD}¡Felicidades! Tu laboratorio de IA empresarial está listo.${RESET}\n"
echo -e "Aquí tienes la información clave para empezar:\n"
echo -e "${BLUE}--- Endpoints de Acceso ---${RESET}"
echo -e "  - ${BOLD}Chat con el LLM (Open WebUI):${RESET} http://<IP_DEL_SERVIDOR>:${OPENWEBUI_PORT}"
echo -e "  - ${BOLD}Gestor de Archivos (Filebrowser):${RESET} http://127.0.0.1:8080 (requiere túnel SSH)"
echo -e "    - Usuario: ${FILEBROWSER_USER}"
echo -e "    - Contraseña: ${FILEBROWSER_PASS}"
echo -e "  - ${BOLD}Gestión de Docker (Portainer):${RESET} http://127.0.0.1:9000 (requiere túnel SSH)"
echo -e "  - ${BOLD}API de Ollama:${RESET} ${OLLAMA_URL} (accesible desde el servidor o LAN si está expuesta)\n"
echo -e "${BLUE}--- Comando SSH Recomendado para Túnel ---${RESET}"
echo -e "  ${BOLD}ssh -L 8080:127.0.0.1:8080 -L 9000:127.0.0.1:9000 usuario@<IP_DEL_SERVIDOR>${RESET}\n"
echo -e "${BLUE}--- Rutas Importantes en el Servidor ---${RESET}"
echo -e "  - Directorio principal: ${RAG_LAB_DIR}"
echo -e "  - Documentos para ingesta: ${RAG_LAB_DIR}/documents"
echo -e "  - Scripts de RAG (para editar): ${RAG_LAB_DIR}/scripts"
echo -e "  - Web Interna (Dashboard): ${RAG_LAB_DIR}/web_internal/index.html\n"
echo -e "${BLUE}--- Logs ---${RESET}"
echo -e "  - Log de esta instalación: ${LOG_FILE}"
echo -e "  - Resumen de errores: ${ERROR_LOG_FILE}"
echo -e "  - Log de ingesta diaria (cron): /var/log/rag_ingest.log\n"
echo -e "${YELLOW}Próximos pasos recomendados:${RESET}"
echo -e "  1. Accede a Filebrowser para subir tus propios documentos a la carpeta 'documents'."
echo -e "  2. La ingesta se realizará automáticamente cada noche, o puedes ejecutarla manualmente con:"
echo -e "     ${BOLD}sudo ${RAG_LAB_DIR}/venv/bin/python ${RAG_LAB_DIR}/scripts/ingestion_script.py${RESET}"
echo -e "  3. ¡Empieza a chatear con tus documentos a través de Open WebUI!\n"

exit 0
