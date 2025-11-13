# RGIA Master – RAG CPU Lab (Plataforma IA Empresarial On-Prem)

![RGIA Master Banner](https://raw.githubusercontent.com/g-a-v-i-n/RGIA-Master-RAG-CPU-Lab-On-Prem-Alternative-to-GPT-Enterprise/main/RGIA_MASTER_RAG_ENTERPRISE_AI.png)

**RGIA Master** es una plataforma de **Retrieval-Augmented Generation (RAG)** de código abierto, diseñada para ser desplegada con un solo comando en tu propia infraestructura. Te permite convertir tus documentos corporativos (PDFs, TXT, Markdown) en una base de conocimiento interactiva y segura, accesible a través de una interfaz de chat intuitiva, sin depender de servicios en la nube de terceros.

## Misión y Visión

### Misión
> “Simplificar y democratizar la adopción de IA empresarial en las organizaciones, entregando una plataforma RAG lista para producción, segura y optimizada para CPU, que se instale con un solo script y permita a cualquier equipo convertir sus documentos en conocimiento accionable en minutos.”

### Visión
> “Ser el estándar abierto de referencia para laboratorios de IA empresarial en Latinoamérica, combinando buenas prácticas DevOps, observabilidad y agentes inteligentes, de forma sostenible y accesible incluso para empresas con infraestructura limitada y presupuestos ajustados.”

---

## ¿Por qué existe esta plataforma?

En un mundo donde la información es el activo más valioso, las empresas se ahogan en un mar de documentos dispersos. **RGIA Master** nace para resolver este problema, ofreciendo una solución "on-premise" que garantiza:

- **Seguridad y Privacidad:** Tus datos nunca abandonan tus servidores.
- **Control Total:** Eres dueño de la infraestructura, los modelos y los datos.
- **Optimización de Costos:** Funciona en hardware modesto (solo CPU), eliminando costosas facturas de GPUs en la nube.
- **Facilidad de Uso:** Un único script de instalación deja todo el entorno 100% funcional.
- **Personalización:** Los scripts de RAG están diseñados para ser modificados, permitiéndote adaptar la lógica de IA a tus necesidades específicas.

---

## Requisitos Mínimos

- **Sistema Operativo:** Ubuntu 20.04/22.04 o Debian 11/12.
- **CPU:** 4+ vCores recomendados.
- **RAM:** 16 GB recomendado para un rendimiento fluido del LLM.
- **Disco:** 25 GB de espacio libre para los modelos, contenedores y datos.

---

## Instalación en 3 Pasos

La instalación es totalmente automatizada. Simplemente clona este repositorio y ejecuta el script como `root`.

```bash
# 1. Clona el repositorio
git clone https://github.com/TU_USUARIO/TU_REPO.git
cd TU_REPO

# 2. Dale permisos de ejecución al instalador
chmod +x install_rag_cpu.sh

# 3. Ejecútalo con privilegios de superusuario
sudo ./install_rag_cpu.sh
```

El script se encargará de todo: instalará Docker, Ollama, Python, configurará los servicios y dejará la plataforma lista para usar.

---

## Arquitectura y Servicios Instalados

RGIA Master se instala en `/opt/rag_lab` y se compone de los siguientes servicios, orquestados con Docker Compose:

| Servicio | Puerto (Local) | Propósito |
| :--- | :--- | :--- |
| **Open WebUI** | `3000/tcp` (Público) | Interfaz de chat web para interactuar con el LLM. |
| **Ollama** | `11434/tcp` (Opcional) | Sirve los modelos de lenguaje (LLMs) localmente. |
| **Qdrant** | `6333/tcp` (Interno) | Base de datos vectorial para almacenar embeddings. |
| **Filebrowser** | `8080/tcp` (Interno) | Gestor de archivos web para subir documentos. |
| **Portainer** | `9000/tcp` (Interno) | UI para gestionar el entorno Docker. |

*Nota: Los servicios marcados como "Interno" solo son accesibles desde el propio servidor. Para acceder a ellos desde tu máquina, necesitas un túnel SSH.*

---

## Guía de Uso Rápido

### 1. Acceso a los Servicios Internos (Túnel SSH)

Para gestionar los archivos y los contenedores, conéctate a tu servidor usando un túnel SSH. Reemplaza `usuario` y `IP_SERVIDOR` con tus datos.

```bash
ssh -L 8080:127.0.0.1:8080 -L 9000:127.0.0.1:9000 usuario@IP_SERVIDOR
```

- **Gestor de Archivos (Filebrowser):** Abre `http://localhost:8080` en tu navegador.
  - **Usuario:** `admin`
  - **Contraseña:** `admin`
- **Gestor de Docker (Portainer):** Abre `http://localhost:9000`.

### 2. Sube tus Documentos

Usa **Filebrowser** (`http://localhost:8080`) para subir tus archivos PDF, TXT o MD al directorio `/srv` (que corresponde a `/opt/rag_lab/documents` en el servidor).

### 3. Ingesta de Datos

La plataforma está configurada para **buscar y procesar nuevos documentos automáticamente todas las noches a las 03:00 AM** (hora del servidor).

Si deseas ejecutar la ingesta manualmente, conéctate al servidor y ejecuta:
```bash
sudo /opt/rag_lab/venv/bin/python /opt/rag_lab/scripts/ingestion_script.py
```

### 4. Chatea con tus Documentos

Abre la interfaz de **Open WebUI** en tu navegador: `http://<IP_DEL_SERVIDOR>:3000`.

¡Ya puedes empezar a hacer preguntas sobre tus documentos! El sistema buscará la información relevante y generará una respuesta utilizando el LLM local.

### 5. Personaliza el Comportamiento RAG

El corazón de la lógica RAG vive en `/opt/rag_lab/scripts`. Estos scripts Python están diseñados para ser el punto de partida. Puedes modificarlos para:
- Cambiar el modelo de embedding.
- Ajustar el tamaño de los fragmentos (`chunk_size`).
- Implementar lógicas de filtrado de metadatos.
- Integrarlo con otras APIs internas.

---

## Webs del Proyecto

### Landing Pública (GitHub Pages)
La carpeta `web_public/` en este repositorio contiene el `index.html` de la landing page del producto, diseñada para ser publicada con GitHub Pages.

### Web Interna Centralizada (WebAdmin AI Dashboard)
La carpeta `web_internal/` contiene el `index.html` de un panel de control interno. El script de instalación copia este archivo a `/opt/rag_lab/web_internal/index.html` en el servidor. Puedes servirlo con un Nginx o usarlo como base para un panel de control más avanzado.

---

## Logs y Diagnóstico

- **Log de Instalación:** `/var/log/rag_install.log`
- **Errores de Instalación:** `/var/log/rag_install_errors.log` (resumen de errores fatales)
- **Log de Ingesta Diaria:** `/var/log/rag_ingest.log`
- **Logs de los Contenedores:** `cd /opt/rag_lab && sudo docker compose logs -f <nombre_servicio>`

---

## Errores Comunes y Soluciones

| Código | Descripción | Causa Probable | Solución |
| :--- | :--- | :--- | :--- |
| **E001** | `DOCKER_INSTALL_FAILED` | Problemas de red o repositorios de `apt` desactualizados. | Asegúrate de tener conexión a internet y ejecuta `sudo apt-get update` antes de reintentar. |
| **E002** | `OLLAMA_INSTALL_FAILED` | El script de instalación de Ollama no pudo descargarse o ejecutarse. | Verifica la conexión a `ollama.ai`. Intenta instalar Ollama manualmente para ver el error específico. |
| **E003** | `MODEL_PULL_FAILED` | Conexión lenta o interrumpida a los servidores de Ollama. | El modelo es grande. Vuelve a ejecutar el script de instalación; es idempotente y reintentará la descarga. |
| **E004** | `VENV_CREATION_FAILED` | Paquetes `python3-venv` o `python3-pip` no instalados. | El script debería instalarlos. Si falla, instálalos manualmente: `sudo apt-get install python3-venv python3-pip`. |
| **E005** | `PIP_INSTALL_FAILED` | Problemas de red al descargar paquetes de PyPI o conflictos de dependencias. | Revisa `/var/log/rag_install.log` para ver el error exacto de `pip`. |
| **E006** | `DOCKER_COMPOSE_FAILED`| Un puerto ya está en uso, o hay un error en la configuración de `docker-compose.yml`. | Usa `sudo lsof -i :<puerto>` para ver qué servicio está usando el puerto. Revisa los logs de Docker. |
| **E007** | `QDRANT_HEALTHCHECK_FAILED`| El contenedor de Qdrant no pudo iniciarse, posiblemente por falta de RAM. | Aumenta la memoria RAM asignada a la VM. Revisa los logs: `sudo docker logs rag_qdrant`. |
| **E008** | `OPENWEBUI_HEALTHCHECK_FAILED`| El contenedor de Open WebUI no puede comunicarse con Ollama o Qdrant. | Verifica que Ollama esté corriendo (`sudo systemctl status ollama`) y que Qdrant esté saludable. |
| **E009** | `INGEST_FAILED` | Qdrant no está disponible o hay un problema con los documentos (ej. PDF corrupto). | Asegúrate de que Qdrant funciona. Revisa el log de ingesta para detalles. |
| **E010** | `QUERY_FAILED` | Ollama no está respondiendo o el modelo LLM no está cargado. | Reinicia el servicio de Ollama (`sudo systemctl restart ollama`) y verifica que el modelo está disponible (`ollama list`). |

---

## Visión a Futuro / Roadmap

**RGIA Master es una plataforma viva.** Nuestra visión es ambiciosa y se centra en tres pilares:

1.  **Mejores Pipelines de Datos**
    -   **Embeddings de Vanguardia:** Integrar modelos de embeddings más potentes y específicos para diferentes dominios (código, finanzas, ciencia).
    -   **Soporte Multi-Modal:** Evolucionar el RAG para que pueda “ver” imágenes y “escuchar” audio, extrayendo contexto de PDFs, JPGs y MP3s por igual.
    -   **RAG con Grafos de Conocimiento:** Ir más allá de la búsqueda semántica, construyendo relaciones entre entidades en tus documentos para responder preguntas complejas que requieran razonamiento.

2.  **Centralización y Usabilidad**
    -   Mejorar continuamente el **RGIA Control Center (WebAdmin AI)** como **web interna centralizada**: el único punto de gestión para toda la plataforma, desde la ingesta y la gestión de modelos hasta las analíticas de uso y los logs.

3.  **Inteligencia y Automatización**
    -   Continuar mejorando la plataforma para que cada vez sea más fácil de usar, mantener y automatizar, reduciendo tareas manuales de operación y soporte.
