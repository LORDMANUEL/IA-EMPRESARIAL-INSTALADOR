# RGIA Master – RAG CPU Lab (Plataforma IA Empresarial On-Prem)

![RGIA Master Banner](https://raw.githubusercontent.com/g-a-v-i-n/RGIA-Master-RAG-CPU-Lab-On-Prem-Alternative-to-GPT-Enterprise/main/RGIA_MASTER_RAG_ENTERPRISE_AI.png)

<p align="center">
  <img alt="Version" src="https://img.shields.io/badge/version-v1.0-blue?style=for-the-badge">
  <img alt="Status" src="https://img.shields.io/badge/status-estable-green?style=for-the-badge">
  <img alt="License" src="https://img.shields.io/badge/license-Open_Source-lightgrey?style=for-the-badge">
  <img alt="Compatibility" src="https://img.shields.io/badge/compatible-Ubuntu_|_Debian-orange?style=for-the-badge">
</p>

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

## Ahorro y Eficiencia: La Ventaja de la Arquitectura RAG

Una de las decisiones estratégicas clave de RGIA Master es el uso de la arquitectura **Retrieval-Augmented Generation (RAG)**. Esto se traduce en un **ahorro masivo de costos y tiempo** en comparación con el enfoque tradicional de re-entrenar o hacer "fine-tuning" de un modelo de lenguaje.

- **Sin necesidad de GPUs costosas:** En lugar de gastar semanas y miles de dólares en GPUs para entrenar un modelo personalizado, RAG utiliza modelos pre-entrenados de propósito general (como `phi3`) y los "aumenta" en tiempo real con la información de tus documentos.
- **Conocimiento siempre actualizado:** Si tus documentos cambian, simplemente los vuelves a ingestar. Con el fine-tuning, tendrías que repetir el costoso proceso de entrenamiento. RAG separa la "inteligencia" del modelo del "conocimiento" de tus datos, ofreciendo una flexibilidad inigualable.
- **Menor consumo de recursos:** Al funcionar 100% en CPU, la plataforma puede desplegarse en hardware mucho más accesible, reduciendo drásticamente la barrera de entrada para la IA empresarial.

En resumen, RGIA Master te da el poder de un modelo personalizado sin los costos prohibitivos asociados, democratizando el acceso a la IA avanzada.

---

## Requisitos Mínimos

- **Sistema Operativo:** Ubuntu 20.04/22.04 o Debian 11/12.
- **CPU:** 4+ vCores recomendados.
- **RAM:** 16 GB recomendado para un rendimiento fluido del LLM.
- **Disco:** 25 GB de espacio libre para los modelos, contenedores y datos.

---

## Dos Versiones, Dos Soluciones

Este repositorio contiene dos versiones de la plataforma RGIA Master. Elige la que mejor se adapte a tus necesidades.

### RGIA Master (Base)
La solución ideal para empezar. Perfecta para PYMEs y equipos que trabajan principalmente con documentos de texto (PDFs nativos, TXT, MD).

**Instalación:**
```bash
# 1. Clona el repositorio
git clone https://github.com/YOUR_USERNAME/YOUR_REPOSITORY.git
cd YOUR_REPOSITORY

# 2. Dale permisos de ejecución al instalador BASE
chmod +x install_rag_cpu.sh

# 3. Ejecútalo con privilegios de superusuario
sudo ./install_rag_cpu.sh
```

### RGIA Master Pro
La solución empresarial. Incluye todo lo de la versión Base, más **soporte para PDFs escaneados (OCR)** y un **RGIA Control Center** para una gestión centralizada.

**Instalación:**
```bash
# 1. Clona el repositorio
git clone https://github.com/YOUR_USERNAME/YOUR_REPOSITORY.git
cd YOUR_REPOSITORY

# 2. Dale permisos de ejecución al instalador PRO
chmod +x install_rag_pro.sh

# 3. Ejecútalo con privilegios de superusuario
sudo ./install_rag_pro.sh
```

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

## Flujo de Trabajo y Casos de Uso

RGIA Master está diseñado para integrarse de forma natural en el flujo de trabajo de tu equipo. A continuación, se describe un ciclo de uso típico.

### Ejemplo de Uso Diario

1.  **Carga de Nuevos Documentos:**
    *   Un miembro del equipo de marketing se conecta al servidor a través del túnel SSH y accede a **Filebrowser** (`http://localhost:8080`).
    *   Sube un nuevo estudio de mercado en PDF a la carpeta de documentos. El documento es un PDF escaneado, ilegible para los buscadores tradicionales.

2.  **Proceso de Ingesta (Automático o Manual):**
    *   **Automático:** Esa noche, a las 03:00 AM, el `cron job` se activa automáticamente. El script de ingesta (versión Base o Pro) detecta el nuevo archivo.
    *   **Manual (si se necesita inmediatez):** Un administrador se conecta al servidor y ejecuta el comando de re-ingesta:
        ```bash
        # Para la versión Base
        sudo /opt/rag_lab/venv/bin/python /opt/rag_lab/scripts/ingestion_script.py

        # Para la versión Pro
        sudo /opt/rag_pro/venv/bin/python /opt/rag_pro/scripts/ingestion_script.py
        ```

3.  **La Magia de la Re-ingesta Inteligente:**
    *   El script **no re-procesa todos los documentos**. Gracias a un sistema de hashes, identifica únicamente los archivos nuevos o modificados.
    *   Si se usa la versión Pro, el script aplica **OCR** al PDF escaneado, extrae el texto de las imágenes, lo divide en fragmentos (`chunks`) y genera los `embeddings`.
    *   Los nuevos vectores de conocimiento se almacenan en la base de datos **Qdrant**.

4.  **Consulta y Obtención de Valor:**
    *   Al día siguiente, un analista de negocio accede a **Open WebUI** (`http://<IP_DEL_SERVIDOR>:3000`).
    *   Pregunta: *"¿Cuál es el sentimiento del mercado en el segmento de 18 a 25 años según el último estudio?"*
    *   El sistema RAG convierte la pregunta en un `embedding`, busca los fragmentos más relevantes en Qdrant (que ahora incluyen el nuevo estudio) y los pasa al LLM junto con la pregunta.
    *   El LLM genera una respuesta precisa y contextualizada, extrayendo información que antes estaba "atrapada" en un PDF escaneado.

---

## Despliegue en un Servidor en la Nube (Cloud VM)

RGIA Master es ideal para ser desplegado en cualquier proveedor de nube que ofrezca VMs con Linux (por ejemplo, **DigitalOcean, Vultr, Linode, AWS EC2, Azure VM, etc.**).

### Pasos para el Despliegue:

1.  **Crear una VM:** Elige una VM con **Ubuntu 22.04** y que cumpla los [requisitos mínimos](#requisitos-mínimos) (se recomiendan 4+ vCPUs y 16 GB de RAM).
2.  **Configurar el Firewall de la Nube:** En el panel de control de tu proveedor, asegúrate de que el firewall de red permita el tráfico entrante en los siguientes puertos:
    *   `TCP/22` (para SSH, esencial para la administración).
    *   `TCP/3000` (para el acceso público a Open WebUI).
3.  **Instalar RGIA Master:** Conéctate a tu nueva VM por SSH y sigue las [instrucciones de instalación](#dos-versiones-dos-soluciones) para la versión Base o Pro.

### Aprovechando la Plataforma de Forma Segura: El Túnel SSH

La arquitectura de RGIA Master está diseñada para ser segura por defecto. Servicios críticos como el gestor de archivos, la administración de Docker o el Control Center **no están expuestos a internet**. Para acceder a ellos, debes usar un **túnel SSH**.

Este comando, ejecutado desde **tu máquina local**, crea un túnel seguro a tu VM en la nube:
```bash
# Reemplaza `usuario` y `IP_DEL_SERVIDOR` con los datos de tu VM
ssh -L 8080:127.0.0.1:8080 -L 9000:127.0.0.1:9000 -L 8000:127.0.0.1:8000 -N usuario@IP_DEL_SERVIDOR
```
*   `-L 8080:127.0.0.1:8080`: Redirige el puerto `8080` de tu máquina local al puerto `8080` de la VM (Filebrowser).
*   `-L 9000:127.0.0.1:9000`: Redirige el puerto `9000` local a la VM (Portainer).
*   `-L 8000:127.0.0.1:8000`: Redirige el puerto `8000` local a la VM (RGIA Control Center - solo en versión Pro).
*   `-N`: Indica a SSH que no ejecute un comando remoto, solo establezca el túnel.

Mientras este comando esté activo en tu terminal local, puedes abrir tu navegador y acceder a:
- **Filebrowser:** `http://localhost:8080`
- **Portainer:** `http://localhost:9000`
- **RGIA Control Center:** `http://localhost:8000`

Este método te da acceso administrativo total sin exponer nunca esos servicios a la red pública, combinando la flexibilidad de la nube con la seguridad del acceso local.

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
