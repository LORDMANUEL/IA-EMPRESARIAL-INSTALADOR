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
# Se crea el directorio de logs si no existe, y se asegura de que el fichero de log exista.
mkdir -p /var/log
touch "${LOG_FILE}"
exec > >(tee -a "${LOG_FILE}") 2>&1

# --- Funciones de Logging ---
# Añade prefijos de timestamp y nivel de log a los mensajes.
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
info "Iniciando el instalador de la plataforma RAG..."
info "----------------------------------------------------"
info "Script: ${SCRIPT_NAME}"
info "Log de instalación: ${LOG_FILE}"
info "----------------------------------------------------"

# 1. Comprobar si el script se ejecuta como root
if [[ "${EUID}" -ne 0 ]]; then
    error "Este script debe ser ejecutado con privilegios de root (sudo)."
fi

# 2. Configurar el modo no interactivo para las instalaciones de apt
export DEBIAN_FRONTEND=noninteractive
info "Modo no interactivo habilitado para la instalación de paquetes."

info "Comprobaciones iniciales completadas con éxito."

# --- Paso 1: Instalación de Dependencias del Sistema ---
info "Iniciando la instalación de dependencias del sistema..."

# Lista de paquetes necesarios para la plataforma RAG
readonly SYSTEM_PACKAGES=(
    "ca-certificates"
    "curl"
    "gnupg"
    "lsb-release"
    "htop"
    "python3"
    "python3-venv"
    "python3-pip"
    "git"
)

# Función para comprobar si un paquete está instalado
is_package_installed() {
    dpkg -l "$1" &> /dev/null
}

# Actualizar la lista de paquetes de apt
info "Actualizando la lista de paquetes (apt-get update)..."
if ! apt-get update -y; then
    error "No se pudo actualizar la lista de paquetes. Verifica la conexión a internet y los repositorios."
fi
info "Lista de paquetes actualizada."

# Instalar cada paquete solo si no está ya presente
for pkg in "${SYSTEM_PACKAGES[@]}"; do
    if is_package_installed "$pkg"; then
        info "El paquete '${pkg}' ya está instalado. Saltando."
    else
        info "Instalando el paquete '${pkg}'..."
        if ! apt-get install -y "$pkg"; then
            error "No se pudo instalar el paquete '${pkg}'. Abortando."
        fi
        info "Paquete '${pkg}' instalado con éxito."
    fi
done

info "Todas las dependencias del sistema han sido instaladas."

# --- Paso 2: Instalación y Configuración de Docker ---
info "Iniciando la instalación y configuración de Docker..."

# Función para añadir el usuario al grupo de docker
add_user_to_docker_group() {
    # Detectar el usuario no-root que ejecutó el script con sudo
    local current_user="${SUDO_USER:-$(logname)}"
    if ! getent group docker > /dev/null; then
        warn "El grupo 'docker' no existe. Creándolo..."
        groupadd docker
    fi

    if id -nG "${current_user}" | grep -qw "docker"; then
        info "El usuario '${current_user}' ya pertenece al grupo 'docker'."
    else
        info "Añadiendo al usuario '${current_user}' al grupo 'docker'..."
        usermod -aG docker "${current_user}"
        info "¡Importante! El usuario '${current_user}' ha sido añadido al grupo 'docker'."
        warn "Para que los cambios surtan efecto, debes cerrar la sesión y volver a iniciarla, o ejecutar 'newgrp docker'."
    fi
}

# Comprobar si Docker ya está instalado y funcional
if command -v docker &> /dev/null && docker --version &> /dev/null; then
    info "Docker ya está instalado en el sistema."
    docker --version
    # Asegurarse de que el servicio esté activo
    if ! systemctl is-active --quiet docker; then
        info "El servicio Docker no está activo. Iniciándolo..."
        systemctl start docker
        systemctl enable docker
    fi
    add_user_to_docker_group
else
    info "Docker no encontrado. Procediendo con la instalación..."

    # Método 1: Instalación desde el repositorio oficial de Docker (preferido)
    install_docker_official() {
        info "Intentando instalar Docker desde el repositorio oficial..."

        # 1. Añadir la GPG key de Docker
        install -m 0755 -d /etc/apt/keyrings
        if [ ! -f /etc/apt/keyrings/docker.gpg ]; then
            curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
            chmod a+r /etc/apt/keyrings/docker.gpg
        else
            info "La GPG key de Docker ya existe."
        fi

        # 2. Añadir el repositorio de Docker
        if [ ! -f /etc/apt/sources.list.d/docker.list ]; then
            echo \
              "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
              $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
              tee /etc/apt/sources.list.d/docker.list > /dev/null
        else
            info "El repositorio de Docker ya está configurado."
        fi

        # 3. Actualizar e instalar
        apt-get update -y
        if apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin; then
            info "Docker Engine y Docker Compose plugin instalados con éxito desde el repo oficial."
            return 0 # Éxito
        else
            warn "Falló la instalación desde el repositorio oficial de Docker."
            return 1 # Fallo
        fi
    }

    # Método 2: Fallback a docker.io desde repositorios estándar
    install_docker_fallback() {
        warn "Intentando instalar Docker usando el paquete 'docker.io' como fallback..."
        if apt-get install -y docker.io; then
            info "Paquete 'docker.io' instalado con éxito."
            if ! command -v docker-compose &>/dev/null; then
                 warn "El plugin 'docker-compose' no está disponible con 'docker.io'. Se usará 'docker compose'."
                 warn "Asegúrate de que la versión de 'docker.io' sea compatible con 'docker compose'."
            fi
            return 0 # Éxito
        else
            error "Falló la instalación de 'docker.io'. No se puede continuar sin Docker."
            return 1 # Fallo
        fi
    }

    if ! install_docker_official; then
        install_docker_fallback
    fi

    info "Habilitando e iniciando el servicio de Docker..."
    systemctl start docker
    systemctl enable docker
    info "Servicio Docker iniciado y habilitado."

    add_user_to_docker_group
fi

info "La configuración de Docker ha finalizado."

# --- Paso 3: Creación de la Estructura de Archivos y Configuraciones ---
info "Creando la estructura de directorios y archivos de configuración en ${RAG_LAB_DIR}..."

# Crear la estructura de directorios principal
info "Creando subdirectorios..."
mkdir -p "${RAG_LAB_DIR}/documents"
mkdir -p "${RAG_LAB_DIR}/qdrant_storage"
mkdir -p "${RAG_LAB_DIR}/open_webui_data"
mkdir -p "${RAG_LAB_DIR}/scripts"
mkdir -p "${RAG_LAB_DIR}/logs"
mkdir -p "${RAG_LAB_DIR}/config"
info "Estructura de directorios creada."

# Generar el archivo de configuración .env
info "Generando el archivo de configuración .env..."
cat <<'EOF' > "${RAG_LAB_DIR}/config/.env"
# --- Configuración General de la Plataforma RAG ---

# Puerto para Open WebUI (accesible públicamente)
OPENWEBUI_PORT=3000

# Exponer Ollama fuera de localhost. Poner a 'true' para permitir acceso desde la red.
# ¡ADVERTENCIA! Exponer Ollama sin autenticación es un riesgo de seguridad.
EXPOSE_OLLAMA=false

# IP en la que Ollama debe escuchar. 127.0.0.1 para local, 0.0.0.0 para exponer.
OLLAMA_BIND=127.0.0.1

# Nombre de la colección por defecto en Qdrant
RAG_COLLECTION=corporativo_rag

# Directorio donde los scripts de ingesta buscarán documentos
RAG_DOCS_DIR=/opt/rag_lab/documents

# --- Configuración de Modelos ---

# Modelo de embeddings a utilizar (multilingüe, optimizado para CPU)
EMBEDDING_MODEL=intfloat/multilingual-e5-small

# Modelo LLM de Ollama a utilizar (optimizado para CPU)
OLLAMA_MODEL=phi3:3.8b-mini-4k-instruct-q4_K_M

# --- Credenciales y Servicios ---

# Credenciales para Filebrowser (cambiar en el primer login)
FILEBROWSER_USER=admin
FILEBROWSER_PASS=admin

# Habilitar/deshabilitar Netdata. Poner a 'false' si no se desea monitoreo.
ENABLE_NETDATA=true

# --- Límites de Recursos para Docker (opcional) ---
# Dejar en blanco para no establecer límites. Ejemplos: '2g', '512m'.
QDRANT_MEMORY_LIMIT=2g
OPENWEBUI_MEMORY_LIMIT=2g
NETDATA_MEMORY_LIMIT=512m
EOF
info "Archivo .env creado en ${RAG_LAB_DIR}/config/.env"

# Generar el archivo requirements.txt para el entorno Python
info "Generando el archivo requirements.txt..."
cat <<'EOF' > "${RAG_LAB_DIR}/config/requirements.txt"
# --- Dependencias de Python para los scripts RAG ---
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
# Fijar urllib3 a una versión compatible para evitar problemas con dependencias antiguas
urllib3<2.0
EOF
info "Archivo requirements.txt creado en ${RAG_LAB_DIR}/config/requirements.txt"

info "La estructura de archivos y configuraciones ha sido creada con éxito."

# --- Paso 4: Configuración del Entorno Virtual de Python ---
info "Configurando el entorno virtual de Python..."

readonly VENV_DIR="${RAG_LAB_DIR}/venv"
readonly REQUIREMENTS_FILE="${RAG_LAB_DIR}/config/requirements.txt"

# Crear el entorno virtual si no existe
if [ ! -d "${VENV_DIR}" ]; then
    info "Creando el entorno virtual de Python en ${VENV_DIR}..."
    if ! python3 -m venv "${VENV_DIR}"; then
        error "No se pudo crear el entorno virtual de Python."
    fi
    info "Entorno virtual creado con éxito."
else
    info "El entorno virtual de Python ya existe en ${VENV_DIR}."
fi

# Actualizar pip e instalar/actualizar las dependencias de Python desde requirements.txt
info "Instalando dependencias de Python desde ${REQUIREMENTS_FILE}..."
# Usamos el pip del venv para instalar los paquetes
if ! "${VENV_DIR}/bin/pip" install --upgrade pip; then
    warn "No se pudo actualizar pip. Continuando con la versión actual."
fi

if ! "${VENV_DIR}/bin/pip" install -r "${REQUIREMENTS_FILE}"; then
    error "No se pudieron instalar las dependencias de Python. Revisa el log para más detalles."
fi

info "Todas las dependencias de Python han sido instaladas en el entorno virtual."

# --- Paso 5: Instalación y Configuración de Ollama (Host) ---
info "Iniciando la instalación y configuración de Ollama..."

# Cargar las variables de configuración del archivo .env para usarlas en el script
if [ -f "${RAG_LAB_DIR}/config/.env" ]; then
    info "Cargando variables de configuración desde .env..."
    set -a # Exportar automáticamente las variables leídas
    source "${RAG_LAB_DIR}/config/.env"
    set +a # Detener la exportación automática
else
    error "El archivo de configuración .env no se encuentra. No se puede continuar."
fi

# Función para instalar Ollama con reintentos
install_ollama_with_retries() {
    local attempts=3
    local count=0
    info "Descargando e instalando Ollama..."
    while [ $count -lt $attempts ]; do
        count=$((count + 1))
        info "Intento de instalación de Ollama: ${count}/${attempts}..."
        if curl -fsSL https://ollama.com/install.sh | sh; then
            info "Ollama ha sido instalado con éxito."
            # El script de instalación de Ollama puede finalizar antes de que el binario esté en el PATH
            # Forzamos la disponibilidad del comando para el resto del script.
            if [ -x /usr/local/bin/ollama ]; then
                export PATH=$PATH:/usr/local/bin
            fi
            return 0
        fi
        warn "El intento ${count} de instalar Ollama ha fallado."
        if [ $count -lt $attempts ]; then
            sleep 5 # Esperar 5 segundos antes de reintentar
        fi
    done
    return 1
}

# Comprobar si Ollama ya está instalado
if command -v ollama &> /dev/null; then
    info "Ollama ya está instalado en el sistema."
    ollama --version
else
    if ! install_ollama_with_retries; then
        warn "--------------------------------------------------------------------------------"
        warn "¡ATENCIÓN! La instalación automática de Ollama ha fallado después de 3 intentos."
        warn "Por favor, instala Ollama manualmente ejecutando:"
        warn "  curl -fsSL https://ollama.com/install.sh | sh"
        warn "Después de la instalación manual, vuelve a ejecutar este script."
        warn "El script continuará, pero la plataforma no será funcional hasta que Ollama esté instalado."
        warn "--------------------------------------------------------------------------------"
    fi
fi

# Configurar Ollama para que escuche en la IP correcta (si el comando existe)
if command -v ollama &> /dev/null; then
    info "Configurando el servicio de Ollama para escuchar en ${OLLAMA_BIND}..."
    # Crear un override para el servicio de systemd de Ollama
    mkdir -p /etc/systemd/system/ollama.service.d
    cat <<EOF > /etc/systemd/system/ollama.service.d/override.conf
[Service]
Environment="OLLAMA_HOST=${OLLAMA_BIND}"
EOF

    info "Recargando systemd y reiniciando el servicio de Ollama..."
    systemctl daemon-reload
    systemctl restart ollama

    # Verificar que el servicio esté activo
    if ! systemctl is-active --quiet ollama; then
        error "El servicio de Ollama no pudo iniciarse. Revisa los logs con 'journalctl -u ollama'."
    fi
    info "Servicio de Ollama configurado y en ejecución."

    # Descargar el modelo de Ollama si no está presente
    info "Comprobando si el modelo '${OLLAMA_MODEL}' está disponible..."
    if ollama list | grep -q "${OLLAMA_MODEL}"; then
        info "El modelo '${OLLAMA_MODEL}' ya ha sido descargado."
    else
        info "Descargando el modelo '${OLLAMA_MODEL}'. Esto puede tardar varios minutos..."
        # Usar `ollama pull` con reintentos implícitos
        if ! ollama pull "${OLLAMA_MODEL}"; then
            error "No se pudo descargar el modelo de Ollama '${OLLAMA_MODEL}'. Abortando."
        fi
        info "Modelo '${OLLAMA_MODEL}' descargado con éxito."
    fi
else
    warn "Ollama no está instalado, se omite la configuración del servicio y la descarga del modelo."
fi

info "La configuración de Ollama ha finalizado."

# --- Paso 6: Generación del archivo docker-compose.yml ---
info "Generando el archivo docker-compose.yml..."

readonly COMPOSE_FILE="${RAG_LAB_DIR}/docker-compose.yml"

# Generar la base del docker-compose.yml
# Usamos un heredoc que permite la expansión de variables de shell (${VAR})
# pero escapamos las variables de docker-compose (\${VAR}) para que las procese el propio docker-compose.
info "Creando la base del archivo docker-compose..."
cat <<EOF > "${COMPOSE_FILE}"
# docker-compose.yml para la Plataforma RAG CPU
# Autogenerado por el script de instalación.

version: '3.8'

networks:
  rag_net:
    driver: bridge

services:
  qdrant:
    image: qdrant/qdrant:latest
    container_name: rag_qdrant
    restart: unless-stopped
    ports:
      - "127.0.0.1:6333:6333"
      - "127.0.0.1:6334:6334"
    volumes:
      - "${RAG_LAB_DIR}/qdrant_storage:/qdrant/storage"
    networks:
      - rag_net
    mem_limit: \${QDRANT_MEMORY_LIMIT:-2g}
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:6333/ready"]
      interval: 10s
      timeout: 5s
      retries: 5

  open-webui:
    image: ghcr.io/open-webui/open-webui:main
    container_name: rag_open_webui
    restart: unless-stopped
    ports:
      - "\${OPENWEBUI_PORT:-3000}:8080"
    volumes:
      - "${RAG_LAB_DIR}/open_webui_data:/app/backend/data"
    environment:
      - 'OLLAMA_BASE_URL=http://host.docker.internal:11434'
      - 'WEBUI_SECRET_KEY=' # Dejar vacío para que se genere uno aleatorio
    extra_hosts:
      - "host.docker.internal:host-gateway"
    networks:
      - rag_net
    mem_limit: \${OPENWEBUI_MEMORY_LIMIT:-2g}
    depends_on:
      qdrant:
        condition: service_healthy
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8080/health"]
      interval: 30s
      timeout: 10s
      retries: 3

  filebrowser:
    image: filebrowser/filebrowser:latest
    container_name: rag_filebrowser
    restart: unless-stopped
    ports:
      - "127.0.0.1:8080:80"
    volumes:
      - "${RAG_LAB_DIR}/documents:/srv"
      - "${RAG_LAB_DIR}/config/filebrowser.db:/database.db"
    environment:
      - FB_USERNAME=\${FILEBROWSER_USER:-admin}
      - FB_PASSWORD=\${FILEBROWSER_PASS:-admin}
    networks:
      - rag_net
    healthcheck:
      test: ["CMD", "wget", "--spider", "-q", "http://localhost/health"]
      interval: 30s
      timeout: 10s
      retries: 3

  portainer:
    image: portainer/portainer-ce:latest
    container_name: rag_portainer
    restart: unless-stopped
    ports:
      - "127.0.0.1:9000:9000"
      - "127.0.0.1:8000:8000" # Opcional, para el Portainer Edge Agent
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
      - portainer_data:/data
    networks:
      - rag_net
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:9000/api/health"]
      interval: 30s
      timeout: 10s
      retries: 3

volumes:
  portainer_data:
EOF

# Añadir Netdata condicionalmente
if [[ "${ENABLE_NETDATA:-true}" == "true" ]]; then
    info "Añadiendo el servicio Netdata al docker-compose.yml..."
    cat <<EOF >> "${COMPOSE_FILE}"

  netdata:
    image: netdata/netdata:latest
    container_name: rag_netdata
    hostname: \$(hostname)
    restart: unless-stopped
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
    networks:
      - rag_net
    mem_limit: \${NETDATA_MEMORY_LIMIT:-512m}
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:19999/api/v1/info"]
      interval: 30s
      timeout: 10s
      retries: 3
EOF
    info "Servicio Netdata añadido."
fi

info "Archivo docker-compose.yml generado en ${COMPOSE_FILE}"

# --- Paso 7: Generación de Scripts de Aplicación Python ---
info "Generando los scripts de aplicación Python en ${RAG_LAB_DIR}/scripts/..."

# 1. Script de Ingesta (ingestion_script.py)
info "Creando ingestion_script.py..."
cat <<'EOF' > "${RAG_LAB_DIR}/scripts/ingestion_script.py"
#!/usr/bin/env python
# -*- coding: utf-8 -*-

import os
import hashlib
import time
from pathlib import Path
import logging

from llama_index.core import SimpleDirectoryReader
from llama_index.core.text_splitter import SentenceSplitter
from qdrant_client import QdrantClient, models
from sentence_transformers import SentenceTransformer
from tqdm import tqdm
import tenacity

# --- Configuración de Logging ---
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler("/opt/rag_lab/logs/ingestion.log"),
        logging.StreamHandler()
    ]
)
log = logging.getLogger(__name__)

# --- Carga de Variables de Entorno ---
RAG_DOCS_DIR = os.getenv("RAG_DOCS_DIR", "/opt/rag_lab/documents")
EMBEDDING_MODEL = os.getenv("EMBEDDING_MODEL", "intfloat/multilingual-e5-small")
QDRANT_HOST = os.getenv("QDRANT_HOST", "127.0.0.1")
QDRANT_PORT = int(os.getenv("QDRANT_PORT", 6333))
RAG_COLLECTION = os.getenv("RAG_COLLECTION", "corporativo_rag")
CHUNK_SIZE = 512
CHUNK_OVERLAP = 64

# --- Funciones Auxiliares ---
def get_deterministic_id(file_path: str, chunk_content: str) -> str:
    """Genera un ID determinístico basado en la ruta del archivo y el contenido del chunk."""
    hash_object = hashlib.sha256(f"{file_path}{chunk_content}".encode())
    return hash_object.hexdigest()

@tenacity.retry(
    wait=tenacity.wait_exponential(multiplier=1, min=2, max=10),
    stop=tenacity.stop_after_attempt(5),
    before_sleep=tenacity.before_sleep_log(log, logging.INFO)
)
def wait_for_qdrant():
    """Espera a que Qdrant esté disponible."""
    log.info(f"Conectando a Qdrant en {QDRANT_HOST}:{QDRANT_PORT}...")
    client = QdrantClient(host=QDRANT_HOST, port=QDRANT_PORT)
    client.get_collections()
    log.info("Qdrant está listo para recibir conexiones.")
    return client

def main():
    log.info("--- Iniciando Proceso de Ingesta de Documentos ---")

    try:
        qdrant_client = wait_for_qdrant()

        log.info(f"Cargando el modelo de embeddings: '{EMBEDDING_MODEL}'...")
        embedding_model = SentenceTransformer(EMBEDDING_MODEL)
        log.info("Modelo de embeddings cargado.")

        vector_size = embedding_model.get_sentence_embedding_dimension()
        try:
            qdrant_client.get_collection(collection_name=RAG_COLLECTION)
            log.info(f"La colección '{RAG_COLLECTION}' ya existe.")
        except Exception:
            qdrant_client.recreate_collection(
                collection_name=RAG_COLLECTION,
                vectors_config=models.VectorParams(size=vector_size, distance=models.Distance.COSINE),
            )
            log.info(f"Colección '{RAG_COLLECTION}' creada en Qdrant.")

        docs_path = Path(RAG_DOCS_DIR)
        if not docs_path.exists() or not any(docs_path.iterdir()):
            log.warning(f"El directorio '{RAG_DOCS_DIR}' está vacío o no existe. No hay documentos para procesar.")
            return

        log.info(f"Leyendo documentos desde: '{docs_path}' (PDF, TXT, MD)...")
        reader = SimpleDirectoryReader(input_dir=str(docs_path), required_exts=[".pdf", ".txt", ".md"], recursive=True)
        documents = reader.load_data()

        if not documents:
            log.info("No se encontraron nuevos documentos para procesar.")
            return

        log.info(f"Se encontraron {len(documents)} documentos.")
        text_splitter = SentenceSplitter(chunk_size=CHUNK_SIZE, chunk_overlap=CHUNK_OVERLAP)

        points_to_upsert = []
        for doc in tqdm(documents, desc="Procesando documentos"):
            source_path = doc.metadata.get('file_path', 'unknown')
            nodes = text_splitter.get_nodes_from_documents([doc])

            for i, node in enumerate(nodes):
                chunk_content = node.get_content()
                chunk_id = get_deterministic_id(source_path, chunk_content)
                points_to_upsert.append(models.PointStruct(
                    id=chunk_id,
                    vector=embedding_model.encode(chunk_content).tolist(),
                    payload={
                        "source_path": source_path,
                        "chunk_id": i + 1,
                        "timestamp": time.time(),
                        "text": chunk_content
                    }
                ))

        if points_to_upsert:
            log.info(f"Realizando upsert de {len(points_to_upsert)} chunks a Qdrant...")
            qdrant_client.upsert(collection_name=RAG_COLLECTION, points=points_to_upsert, wait=True)
            log.info("Upsert completado.")
        else:
            log.info("No se generaron nuevos chunks para la ingesta.")

    except Exception as e:
        log.error(f"Ha ocurrido un error durante el proceso de ingesta: {e}", exc_info=True)
        return

    log.info("--- Proceso de Ingesta Finalizado ---")

if __name__ == "__main__":
    main()
EOF
info "ingestion_script.py creado."

# 2. Script de Consulta (query_agent.py)
info "Creando query_agent.py..."
cat <<'EOF' > "${RAG_LAB_DIR}/scripts/query_agent.py"
#!/usr/bin/env python
# -*- coding: utf-8 -*-

import os
import sys
import logging
import textwrap

from qdrant_client import QdrantClient
from sentence_transformers import SentenceTransformer
import ollama

# --- Configuración ---
logging.basicConfig(level=logging.WARNING, format='%(asctime)s - %(levelname)s - %(message)s')

EMBEDDING_MODEL = os.getenv("EMBEDDING_MODEL", "intfloat/multilingual-e5-small")
OLLAMA_MODEL = os.getenv("OLLAMA_MODEL", "phi3:3.8b-mini-4k-instruct-q4_K_M")
OLLAMA_BIND = os.getenv("OLLAMA_BIND", "127.0.0.1")
OLLAMA_HOST = f"http://{OLLAMA_BIND}:11434"
QDRANT_HOST = os.getenv("QDRANT_HOST", "127.0.0.1")
QDRANT_PORT = int(os.getenv("QDRANT_PORT", 6333))
RAG_COLLECTION = os.getenv("RAG_COLLECTION", "corporativo_rag")
TOP_K = 3

PROMPT_TEMPLATE = """
Eres un asistente experto que responde preguntas basándose únicamente en el siguiente contexto.
Si la respuesta no se encuentra en el contexto, di "No tengo suficiente información para responder a esa pregunta".
Sé conciso y directo.

Contexto:
{context}

Pregunta:
{query}

Respuesta:
"""

def main():
    if len(sys.argv) < 2:
        print("Uso: python query_agent.py \"<Tu pregunta aquí>\"")
        sys.exit(1)

    query_text = sys.argv[1]

    try:
        print("Cargando modelo de embeddings...")
        embedding_model = SentenceTransformer(EMBEDDING_MODEL)

        print("Conectando a Qdrant y Ollama...")
        qdrant_client = QdrantClient(host=QDRANT_HOST, port=QDRANT_PORT)
        ollama_client = ollama.Client(host=OLLAMA_HOST)

        print("Generando embedding para la consulta...")
        query_vector = embedding_model.encode(query_text).tolist()

        print("Buscando chunks relevantes en Qdrant...")
        search_results = qdrant_client.search(
            collection_name=RAG_COLLECTION, query_vector=query_vector, limit=TOP_K, with_payload=True
        )

        if not search_results:
            print("\nNo se encontraron resultados relevantes.")
            return

        context = "\n---\n".join([result.payload['text'] for result in search_results])
        prompt = PROMPT_TEMPLATE.format(context=context, query=query_text)

        print("\nEnviando pregunta al LLM...")
        print("----------------------------------------\n")

        response_stream = ollama_client.chat(
            model=OLLAMA_MODEL, messages=[{'role': 'user', 'content': prompt}], stream=True
        )

        full_response = ""
        for chunk in response_stream:
            part = chunk['message']['content']
            print(part, end='', flush=True)
            full_response += part

        print("\n\n----------------------------------------")

        sources = {result.payload['source_path'] for result in search_results}
        print("\nFuentes utilizadas:")
        for source in sources:
            print(f"- {source}")

        print("\nRespuesta (primeros 300 caracteres para el smoke test):")
        print(textwrap.shorten(full_response, width=300, placeholder="..."))

    except Exception as e:
        print(f"\nHa ocurrido un error: {e}")
        sys.exit(1)

if __name__ == "__main__":
    main()
EOF
info "query_agent.py creado."

# 3. API RAG (rag_api.py)
info "Creando rag_api.py..."
cat <<'EOF' > "${RAG_LAB_DIR}/scripts/rag_api.py"
#!/usr/bin/env python
# -*- coding: utf-8 -*-

import os
import logging
import subprocess
from contextlib import asynccontextmanager

from fastapi import FastAPI, HTTPException
from pydantic import BaseModel
from qdrant_client import QdrantClient
from sentence_transformers import SentenceTransformer
import ollama

# --- Configuración ---
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
log = logging.getLogger(__name__)

EMBEDDING_MODEL_NAME = os.getenv("EMBEDDING_MODEL", "intfloat/multilingual-e5-small")
OLLAMA_MODEL = os.getenv("OLLAMA_MODEL", "phi3:3.8b-mini-4k-instruct-q4_K_M")
OLLAMA_BIND = os.getenv("OLLAMA_BIND", "127.0.0.1")
OLLAMA_HOST = f"http://{OLLAMA_BIND}:11434"
QDRANT_HOST = os.getenv("QDRANT_HOST", "127.0.0.1")
QDRANT_PORT = int(os.getenv("QDRANT_PORT", 6333))
RAG_COLLECTION = os.getenv("RAG_COLLECTION", "corporativo_rag")
TOP_K = 3

# --- Estado Global y Lifespan ---
app_state = {}

@asynccontextmanager
async def lifespan(app: FastAPI):
    log.info("Cargando modelo de embeddings para la API...")
    app_state["embedding_model"] = SentenceTransformer(EMBEDDING_MODEL_NAME)
    log.info("Conectando a servicios...")
    app_state["qdrant_client"] = QdrantClient(host=QDRANT_HOST, port=QDRANT_PORT)
    app_state["ollama_client"] = ollama.AsyncClient(host=OLLAMA_HOST)
    log.info("API lista.")
    yield
    app_state.clear()
    log.info("Recursos de la API liberados.")

app = FastAPI(lifespan=lifespan)

# --- Modelos Pydantic ---
class QueryRequest(BaseModel):
    query: str
class QueryResponse(BaseModel):
    answer: str
    sources: list[str]
class IngestResponse(BaseModel):
    message: str

PROMPT_TEMPLATE = """
Eres un asistente experto que responde preguntas basándose únicamente en el siguiente contexto.
Si la respuesta no se encuentra en el contexto, di "No tengo suficiente información para responder a esa pregunta".

Contexto:
{context}

Pregunta:
{query}

Respuesta:
"""

# --- Endpoints ---
@app.post("/ingest", response_model=IngestResponse)
async def ingest_documents():
    script_path = "/opt/rag_lab/scripts/ingestion_script.py"
    venv_python = "/opt/rag_lab/venv/bin/python"
    log_file = "/var/log/rag_ingest.log"
    command = f"{venv_python} {script_path} >> {log_file} 2>&1 &"
    try:
        subprocess.Popen(command, shell=True)
        return IngestResponse(message="Proceso de ingesta iniciado en segundo plano.")
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Error al iniciar la ingesta: {e}")

@app.post("/query", response_model=QueryResponse)
async def query_rag(request: QueryRequest):
    try:
        embedding_model = app_state["embedding_model"]
        qdrant_client = app_state["qdrant_client"]
        ollama_client = app_state["ollama_client"]

        query_vector = embedding_model.encode(request.query).tolist()

        search_results = qdrant_client.search(
            collection_name=RAG_COLLECTION, query_vector=query_vector, limit=TOP_K
        )

        if not search_results:
            return QueryResponse(answer="No se encontraron resultados relevantes.", sources=[])

        context = "\n---\n".join([result.payload['text'] for result in search_results])
        prompt = PROMPT_TEMPLATE.format(context=context, query=request.query)

        response = await ollama_client.chat(
            model=OLLAMA_MODEL, messages=[{'role': 'user', 'content': prompt}]
        )

        answer = response['message']['content']
        sources = list({result.payload['source_path'] for result in search_results})

        return QueryResponse(answer=answer, sources=sources)
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Error durante la consulta: {e}")

# Para ejecutar: uvicorn rag_api:app --host 127.0.0.1 --port 8000
EOF
info "rag_api.py creado."

info "Todos los scripts de aplicación han sido generados."

# --- Paso 8: Generación de Scripts de Ayuda (Helpers) ---
info "Generando los scripts de ayuda en ${RAG_LAB_DIR}/scripts/..."

# 1. Script de Diagnóstico (diag_rag.sh)
info "Creando diag_rag.sh..."
cat <<'EOF' > "${RAG_LAB_DIR}/scripts/diag_rag.sh"
#!/usr/bin/env bash
set -eo pipefail
echo "--- Diagnóstico de la Plataforma RAG ---"
echo
echo "--- 1. Estado de los Contenedores Docker ---"
docker compose -f /opt/rag_lab/docker-compose.yml ps
echo
echo "--- 2. Estado del Servicio Systemd 'rag_lab' ---"
systemctl status rag_lab --no-pager || true
echo
echo "--- 3. Estado del Servicio Systemd 'ollama' ---"
systemctl status ollama --no-pager || true
echo
echo "--- 4. Comprobación de Endpoints (Healthchecks) ---"
echo -n "Qdrant (/ready): " && curl -fsS http://127.0.0.1:6333/ready || echo "FAIL"
echo
echo -n "Open WebUI (HTML): " && curl -fsS http://127.0.0.1:3000 | grep -q "<html" && echo "OK" || echo "FAIL"
echo
echo -n "Filebrowser (Health): " && curl -fsS http://127.0.0.1:8080/health && echo "OK" || echo "FAIL"
echo
echo -n "Portainer (API Health): " && curl -fsS http://127.0.0.1:9000/api/health && echo "OK" || echo "FAIL"
echo
if [[ -f /opt/rag_lab/docker-compose.yml && $(grep -q netdata /opt/rag_lab/docker-compose.yml) ]]; then
  echo -n "Netdata (API Info): " && curl -fsS http://127.0.0.1:19999/api/v1/info >/dev/null && echo "OK" || echo "FAIL"
  echo
fi
echo -n "Ollama (API): " && curl -fsS http://127.0.0.1:11434/api/tags >/dev/null && echo "OK" || echo "FAIL"
echo
echo
echo "--- 5. Modelo Ollama Instalado ---"
ollama list
echo
echo "--- 6. Uso de Disco en /opt/rag_lab ---"
du -sh /opt/rag_lab/*
echo
echo "--- 7. Últimas 10 líneas del log de ingesta (/var/log/rag_ingest.log) ---"
tail -n 10 /var/log/rag_ingest.log || echo "Log no encontrado."
echo
echo "--- 8. Estado del Cron de Ingesta ---"
systemctl is-active --quiet cron && echo "Servicio Cron: ACTIVO" || echo "Servicio Cron: INACTIVO"
grep "ingestion_script" /etc/cron.d/rag_ingest || echo "Cron job 'rag_ingest' no configurado."
echo
echo "--- Diagnóstico Finalizado ---"
EOF
info "diag_rag.sh creado."

# 2. Script de Backup (backup.sh)
info "Creando backup.sh..."
cat <<'EOF' > "${RAG_LAB_DIR}/scripts/backup.sh"
#!/usr/bin/env bash
set -Eeuo pipefail
BACKUP_DIR="/opt"
TIMESTAMP=$(date +"%Y-%m-%d_%H-%M-%S")
BACKUP_FILE="${BACKUP_DIR}/rag_lab_backup_${TIMESTAMP}.tgz"
SOURCE_DIR="/opt/rag_lab"

echo "Iniciando backup de ${SOURCE_DIR}..."
echo "El archivo de backup se guardará en: ${BACKUP_FILE}"

# Parar los servicios para asegurar la consistencia de los datos
echo "Deteniendo la pila de servicios RAG..."
systemctl stop rag_lab

# Crear el archivo comprimido
tar -czf "${BACKUP_FILE}" -C "$(dirname ${SOURCE_DIR})" "$(basename ${SOURCE_DIR})"

# Reiniciar los servicios
echo "Reiniciando la pila de servicios RAG..."
systemctl start rag_lab

echo "¡Backup completado con éxito!"
ls -lh "${BACKUP_FILE}"
EOF
info "backup.sh creado."

# 3. Script de Restauración (restore.sh)
info "Creando restore.sh..."
cat <<'EOF' > "${RAG_LAB_DIR}/scripts/restore.sh"
#!/usr/bin/env bash
set -Eeuo pipefail

if [ -z "$1" ]; then
    echo "Error: Debes proporcionar la ruta al archivo de backup .tgz"
    echo "Uso: $0 /ruta/al/backup.tgz"
    exit 1
fi

BACKUP_FILE="$1"
DEST_DIR="/opt"

if [ ! -f "${BACKUP_FILE}" ]; then
    echo "Error: El archivo de backup no existe en ${BACKUP_FILE}"
    exit 1
fi

echo "ADVERTENCIA: Esta operación sobreescribirá el contenido de /opt/rag_lab."
read -p "¿Estás seguro de que quieres continuar? (s/n): " CONFIRM
if [[ "$CONFIRM" != "s" ]]; then
    echo "Restauración cancelada."
    exit 0
fi

echo "Deteniendo la pila de servicios RAG..."
systemctl stop rag_lab

echo "Eliminando la instalación actual en /opt/rag_lab..."
rm -rf /opt/rag_lab

echo "Restaurando desde ${BACKUP_FILE}..."
tar -xzf "${BACKUP_FILE}" -C "${DEST_DIR}"

echo "Restauración de archivos completada."
echo "Reiniciando la pila de servicios RAG..."
systemctl start rag_lab

echo "¡Restauración completada con éxito!"
echo "Verifica el estado de los servicios con 'diag_rag.sh'."
EOF
info "restore.sh creado."

# 4. Script de Actualización de Open WebUI (update_openwebui.sh)
info "Creando update_openwebui.sh..."
cat <<'EOF' > "${RAG_LAB_DIR}/scripts/update_openwebui.sh"
#!/usr/bin/env bash
set -Eeuo pipefail
COMPOSE_FILE="/opt/rag_lab/docker-compose.yml"

echo "Actualizando la imagen de Open WebUI..."
docker compose -f "${COMPOSE_FILE}" pull open-webui

echo "Reiniciando el contenedor de Open WebUI con la nueva imagen..."
docker compose -f "${COMPOSE_FILE}" up -d open-webui

echo "¡Actualización de Open WebUI completada!"
EOF
info "update_openwebui.sh creado."

# 5. Script de Actualización del Modelo de Ollama (update_ollama_model.sh)
info "Creando update_ollama_model.sh..."
cat <<'EOF' > "${RAG_LAB_DIR}/scripts/update_ollama_model.sh"
#!/usr/bin/env bash
set -Eeuo pipefail

# Cargar el nombre del modelo desde el .env
if [ -f "/opt/rag_lab/config/.env" ]; then
    source "/opt/rag_lab/config/.env"
else
    echo "Error: No se encuentra el archivo .env"
    exit 1
fi

if [ -z "${OLLAMA_MODEL}" ]; then
    echo "Error: La variable OLLAMA_MODEL no está definida en el .env"
    exit 1
fi

echo "Actualizando el modelo de Ollama: ${OLLAMA_MODEL}..."
ollama pull "${OLLAMA_MODEL}"

echo "¡Actualización del modelo completada!"
ollama list | grep "${OLLAMA_MODEL}"
EOF
info "update_ollama_model.sh creado."

# Dar permisos de ejecución a todos los scripts
info "Asignando permisos de ejecución a los scripts..."
chmod +x "${RAG_LAB_DIR}/scripts/"*.sh
chmod +x "${RAG_LAB_DIR}/scripts/"*.py
info "Permisos asignados."

info "Todos los scripts de ayuda han sido generados."

# --- Paso 9: Configuración de Automatización y Servicios ---
info "Configurando la automatización (Cron, Systemd) y la rotación de logs..."

# 1. Configurar Cron para la ingesta diaria
info "Configurando la tarea de Cron para la ingesta diaria de documentos..."
cat <<'EOF' > /etc/cron.d/rag_ingest
# Cron job para ejecutar la ingesta de documentos de la plataforma RAG
# Se ejecuta todos los días a las 03:00 AM
0 3 * * * root ${RAG_LAB_DIR}/venv/bin/python ${RAG_LAB_DIR}/scripts/ingestion_script.py >> /var/log/rag_ingest.log 2>&1
EOF
chmod 0644 /etc/cron.d/rag_ingest
systemctl restart cron
info "Tarea de Cron configurada en /etc/cron.d/rag_ingest"

# 2. Configurar el servicio de Systemd para la pila Docker
info "Configurando el servicio de Systemd 'rag_lab.service'..."
cat <<'EOF' > /etc/systemd/system/rag_lab.service
[Unit]
Description=RAG Lab Docker Compose Stack
Requires=docker.service
After=docker.service

[Service]
Type=oneshot
RemainAfterExit=yes
User=root
Group=docker
WorkingDirectory=${RAG_LAB_DIR}
# Cargar el .env para que docker-compose lo utilice
EnvironmentFile=${RAG_LAB_DIR}/config/.env
# Usar docker compose v2
ExecStart=/usr/bin/docker compose -f docker-compose.yml up -d
ExecStop=/usr/bin/docker compose -f docker-compose.yml down
TimeoutStartSec=0

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
info "Servicio de Systemd configurado en /etc/systemd/system/rag_lab.service"

# 3. Configurar Logrotate
info "Configurando la rotación de logs para la plataforma RAG..."
cat <<'EOF' > /etc/logrotate.d/rag_lab
/var/log/rag_install.log
/var/log/rag_ingest.log
/opt/rag_lab/logs/ingestion.log
{
    daily
    rotate 7
    compress
    delaycompress
    missingok
    notifempty
    create 644 root root
}
EOF
info "Rotación de logs configurada en /etc/logrotate.d/rag_lab"

info "La configuración de automatización y servicios ha finalizado."

# --- Paso 10: Generación del archivo README.md ---
info "Generando el archivo README.md..."
cat <<'EOF' > "${RAG_LAB_DIR}/README.md"
# Plataforma RAG-en-una-Caja para CPU

Bienvenido a tu plataforma de desarrollo de agentes RAG, instalada y configurada en `/opt/rag_lab`.
Este documento contiene toda la información necesaria para operar, mantener y solucionar problemas de la plataforma.

## 1. Arquitectura del Sistema

La plataforma está diseñada para ser segura y eficiente, exponiendo públicamente solo los servicios necesarios.

```ascii
+--------------------------------------------------------------------------+
| VM Host (Ubuntu/Debian)                                                  |
|                                                                          |
|   +--------------------------+     +-----------------------------------+ |
|   | Ollama (Host)            |     | Python Venv (/opt/rag_lab/venv)   | |
|   | Modelo: OLLAMA_MODEL     |<--->| Scripts (ingest, query, api)    | |
|   | Bind: OLLAMA_BIND:11434  |     +-----------------------------------+ |
|   +--------------------------+                                           |
|          ^                                                               |
|          |                                                               |
| +--------|---------------------------------------------------------------+
| | Docker | Network: rag_net                                              |
| |        |                                                               |
| |   +----|----------------+      +------------------+      +-----------+ |
| |   | Open WebUI          |----->| host.internal    |      | Qdrant    | |
| |   | Port: OPENWEBUI_PORT|      | (Ollama en Host) | <----| (Vectors) | |
| |   +---------------------+      +------------------+      | :6333     | |
| |                                                          +-----------+ |
| |   +---------------------+      +------------------+      +-----------+ |
| |   | Portainer           |      | Filebrowser      |      | Netdata   | |
| |   | (Container Mgmt)    |      | (File Mgmt)      |      | (Host Mon)| |
| |   | :9000               |      | :8080            |      | :19999    | |
| |   +---------------------+      +------------------+      +-----------+ |
| +--------------------------------------------------------------------------+
```

## 2. Servicios y Endpoints

| Servicio      | Puerto Expuesto        | Acceso        | Descripción                               |
|---------------|------------------------|---------------|-------------------------------------------|
| **Open WebUI**| `0.0.0.0:3000` (def)   | **Público**   | Interfaz de chat para interactuar con el LLM. |
| **Ollama**    | `127.0.0.1:11434` (def)| Localhost     | Servidor de modelos LLM.                  |
| **Qdrant**    | `127.0.0.1:6333`       | Localhost     | Base de datos de vectores.                |
| **Filebrowser**| `127.0.0.1:8080`       | Localhost     | Gestor de archivos para subir documentos. |
| **Portainer** | `127.0.0.1:9000`       | Localhost     | Dashboard para gestionar contenedores.    |
| **Netdata**   | `127.0.0.1:19999`      | Localhost     | Monitoreo en tiempo real del host.        |
| **RAG API**   | `127.0.0.1:8000` (manual)| Localhost     | API REST para ingesta y consulta.       |

### Acceso a Paneles Internos (localhost)

Para acceder a los servicios expuestos solo en `127.0.0.1` desde tu máquina local, necesitas crear un túnel SSH. Reemplaza `usuario@IP_VM` con tus credenciales.

```bash
ssh -L 9000:127.0.0.1:9000 \
    -L 8080:127.0.0.1:8080 \
    -L 6333:127.0.0.1:6333 \
    -L 19999:127.0.0.1:19999 \
    -L 8000:127.0.0.1:8000 \
    usuario@IP_VM
```
Una vez el túnel esté activo, puedes abrir `http://localhost:9000` en tu navegador para acceder a Portainer, y así con los demás servicios.

## 3. Operación y Mantenimiento

Todos los scripts de ayuda se encuentran en `/opt/rag_lab/scripts/`.

- **Diagnóstico Rápido**:
  ```bash
  sudo /opt/rag_lab/scripts/diag_rag.sh
  ```

- **Ver Logs de la Pila Docker**:
  ```bash
  sudo docker compose -f /opt/rag_lab/docker-compose.yml logs -f
  ```

- **Reiniciar la Pila de Servicios**:
  ```bash
  sudo systemctl restart rag_lab
  ```

- **Verificar Logs de Ingesta**:
  - Log del cron: `tail -f /var/log/rag_ingest.log`
  - Log del script: `tail -f /opt/rag_lab/logs/ingestion.log`

- **Ejecutar Ingesta Manualmente**:
  ```bash
  sudo /opt/rag_lab/venv/bin/python /opt/rag_lab/scripts/ingestion_script.py
  ```

### Backup y Restore

- **Crear un Backup**:
  El script creará un archivo `.tgz` en `/opt/` con todo el contenido de `/opt/rag_lab`.
  ```bash
  sudo /opt/rag_lab/scripts/backup.sh
  ```

- **Restaurar desde un Backup**:
  **¡ADVERTENCIA!** Esto reemplazará la instalación existente.
  ```bash
  sudo /opt/rag_lab/scripts/restore.sh /opt/rag_lab_backup_YYYY-MM-DD.tgz
  ```

### Actualizaciones

- **Actualizar Open WebUI**:
  ```bash
  sudo /opt/rag_lab/scripts/update_openwebui.sh
  ```

- **Actualizar el Modelo de Ollama**:
  ```bash
  sudo /opt/rag_lab/scripts/update_ollama_model.sh
  ```

## 4. Troubleshooting

- **`docker compose` falla**: Asegúrate de que tu usuario pertenece al grupo `docker`. Puede que necesites cerrar sesión y volver a entrar después de la instalación.
- **La ingesta falla por falta de memoria**: El proceso de embeddings puede consumir mucha RAM. Asegúrate de que la VM tiene suficiente memoria. Si el problema persiste, considera usar un modelo de embeddings más pequeño en el archivo `.env`.
- **Puertos ocupados**: Si un servicio no levanta, verifica si el puerto que intenta usar ya está ocupado con `sudo lsof -i :<numero_puerto>`. Cambia el puerto en el archivo `/opt/rag_lab/config/.env` y reinicia el servicio con `sudo systemctl restart rag_lab`.
- **Ollama no responde**: Verifica el estado del servicio con `sudo systemctl status ollama` y los logs con `sudo journalctl -u ollama`.

---
*Documentación autogenerada por el script de instalación.*
EOF
info "Archivo README.md generado en ${RAG_LAB_DIR}/README.md"

# --- Paso 11: Orquestación Final y Pruebas ---
info "Iniciando la orquestación final y los smoke tests..."

# 1. Configurar el Firewall (UFW)
if command -v ufw &> /dev/null && ufw status | grep -q "Status: active"; then
    info "Configurando el firewall UFW..."

    # Permitir acceso SSH para no perder la conexión
    ufw allow ssh

    # Permitir acceso a Open WebUI
    info "Permitiendo tráfico en el puerto ${OPENWEBUI_PORT} para Open WebUI..."
    ufw allow "${OPENWEBUI_PORT}"/tcp

    # Permitir acceso a Ollama condicionalmente
    if [[ "${EXPOSE_OLLAMA:-false}" == "true" ]]; then
        info "Permitiendo tráfico en el puerto 11434 para Ollama..."
        ufw allow 11434/tcp
    fi

    ufw reload
    info "Reglas de UFW aplicadas."
else
    info "UFW no está activo. Se omite la configuración del firewall."
fi

# 2. Habilitar e iniciar el servicio principal de la plataforma RAG
info "Habilitando e iniciando el servicio 'rag_lab.service'..."
systemctl enable --now rag_lab
info "Servicio 'rag_lab' habilitado e iniciado."
info "Esperando a que los contenedores se inicien y estabilicen (puede tardar un par de minutos)..."
sleep 60 # Dar tiempo a que los contenedores se inicien y pasen sus healthchecks iniciales

# 3. Smoke Tests Automatizados
info "--- Iniciando Smoke Tests ---"
test_passed=true

# Test 1: Qdrant está listo
info "Test 1: Verificando que Qdrant está operativo..."
if curl -fsS http://127.0.0.1:6333/ready &> /dev/null; then
    info "-> Test 1 PASSED: Qdrant responde correctamente."
else
    error "-> Test 1 FAILED: Qdrant no responde en http://127.0.0.1:6333/ready"
    test_passed=false
fi

# Test 2: Open WebUI está sirviendo HTML
info "Test 2: Verificando que Open WebUI está operativo..."
if curl -fsS "http://127.0.0.1:${OPENWEBUI_PORT}" | grep -q "<html"; then
    info "-> Test 2 PASSED: Open WebUI responde con HTML."
else
    error "-> Test 2 FAILED: Open WebUI no responde en http://127.0.0.1:${OPENWEBUI_PORT}"
    test_passed=false
fi

# Test 3: El modelo de Ollama está presente
info "Test 3: Verificando que el modelo de Ollama está descargado..."
if command -v ollama &> /dev/null && ollama list | grep -q "${OLLAMA_MODEL}"; then
    info "-> Test 3 PASSED: El modelo '${OLLAMA_MODEL}' está disponible."
else
    error "-> Test 3 FAILED: El modelo '${OLLAMA_MODEL}' no fue encontrado."
    test_passed=false
fi

# Test 4: Proceso de Ingesta y Consulta End-to-End
info "Test 4: Realizando prueba de ingesta y consulta end-to-end..."
echo "Este es un documento de prueba para el smoke test." > "${RAG_DOCS_DIR}/smoke_test.txt"
info "Ejecutando script de ingesta para el documento de prueba..."
if ! "${VENV_DIR}/bin/python" "${RAG_LAB_DIR}/scripts/ingestion_script.py"; then
    error "-> Test 4 FAILED: El script de ingesta falló."
    test_passed=false
else
    info "Script de ingesta completado. Ejecutando consulta de prueba..."
    query_output=$("${VENV_DIR}/bin/python" "${RAG_LAB_DIR}/scripts/query_agent.py" "¿De qué trata el documento de prueba?")
    if echo "${query_output}" | grep -qi "documento de prueba"; then
        info "-> Test 4 PASSED: La consulta RAG devolvió una respuesta coherente."
        echo "Respuesta del agente:"
        echo "${query_output}" | tail -n 5
    else
        error "-> Test 4 FAILED: La respuesta de la consulta no fue la esperada."
        test_passed=false
    fi
fi

# Test 5: Estado final de los contenedores
info "Test 5: Verificando el estado final de los contenedores..."
docker compose -f "${COMPOSE_FILE}" ps
if ! docker compose -f "${COMPOSE_FILE}" ps | grep -v " unhealthy"; then
    info "-> Test 5 PASSED: Todos los contenedores están en estado 'running' o 'healthy'."
else
    warn "-> Test 5 WARNING: Uno o más contenedores están en estado 'unhealthy'."
    # No marcamos como fallo, pero sí como advertencia
fi

if ! ${test_passed}; then
    error "Uno o más smoke tests críticos han fallado. Revisa el log."
fi

info "--- Todos los Smoke Tests han finalizado ---"

# --- Mensaje Final ---
# Detectar la IP principal del host
ip_address=$(hostname -I | awk '{print $1}')

echo
echo "--------------------------------------------------------------------------------"
echo "¡Instalación de la Plataforma RAG completada!"
echo "--------------------------------------------------------------------------------"
echo
echo "Accede a los servicios a través de las siguientes URLs:"
echo
echo "  - Open WebUI (Público):      http://${ip_address}:${OPENWEBUI_PORT}"
echo "  - Filebrowser (Localhost):   http://127.0.0.1:8080 (Credenciales: ${FILEBROWSER_USER}/${FILEBROWSER_PASS})"
echo "  - Portainer (Localhost):     http://127.0.0.1:9000 (Crea tu usuario admin en el primer acceso)"
echo "  - Qdrant UI (Localhost):     http://127.0.0.1:6333/dashboard"
if [[ "${ENABLE_NETDATA:-true}" == "true" ]]; then
echo "  - Netdata (Localhost):       http://127.0.0.1:19999"
fi
echo
echo "Para acceder a los servicios 'Localhost' desde tu máquina, usa el túnel SSH detallado en el README."
echo
echo "Próximos pasos recomendados:"
echo "  1. Accede a Filebrowser y sube tus documentos (PDF, TXT, MD) a la carpeta raíz."
echo "  2. La ingesta se ejecutará automáticamente a las 03:00 AM, o puedes lanzarla manualmente con:"
echo "     sudo /opt/rag_lab/venv/bin/python /opt/rag_lab/scripts/ingestion_script.py"
echo "  3. Accede a Open WebUI, crea una cuenta y empieza a chatear con tus documentos."
echo
echo "¡IMPORTANTE! Cambia las credenciales por defecto de Filebrowser en tu primer acceso."
echo
echo "Toda la documentación y los scripts de ayuda están en /opt/rag_lab/."
echo "Para un diagnóstico rápido, ejecuta: sudo /opt/rag_lab/scripts/diag_rag.sh"
echo
echo "--------------------------------------------------------------------------------"
