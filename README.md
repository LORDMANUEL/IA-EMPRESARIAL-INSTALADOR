# Prompt Maestro 3.0 — Instalador de Plataforma RAG en CPU

## Visión General

**Prompt Maestro 3.0** es un instalador autocontenido que despliega una plataforma completa de **Retrieval-Augmented Generation (RAG)** en una máquina Ubuntu/Debian con CPU en cuestión de minutos. Con un solo comando, transforma un servidor "vacío" en un entorno de desarrollo de agentes de IA potente, seguro y listo para producción.

Este proyecto nace de la necesidad de estandarizar y acelerar la creación de entornos RAG, eliminando la complejidad y las horas de configuración manual.

## Beneficios Clave

- **Velocidad de Despliegue**: Pasa de un servidor limpio a una plataforma RAG funcional en menos de 10 minutos. El script es 100% automatizado y no requiere intervención manual.
- **Seguridad por Defecto**: La arquitectura expone públicamente solo la interfaz de chat (Open WebUI). Todos los paneles de gestión y servicios de datos son accesibles únicamente desde `localhost`, protegidos de accesos no autorizados y pensados para ser utilizados a través de un túnel SSH seguro.
- **Observabilidad Integrada**: La plataforma incluye Portainer para la gestión de contenedores y Netdata para el monitoreo en tiempo real del host. Además, el **RAG Control Center** ofrece un dashboard centralizado para supervisar la salud del sistema y realizar operaciones comunes.
- **Idempotente y Robusto**: Puedes ejecutar el script múltiples veces. No romperá nada; solo instalará o actualizará los componentes necesarios, asegurando un estado consistente.
- **Todo Incluido**: Desde el servidor de modelos LLM (Ollama) hasta la base de datos vectorial (Qdrant) y una interfaz de chat lista para usar, todo está preconfigurado y optimizado para CPU.

## Arquitectura

El sistema se divide en dos capas principales: servicios que corren directamente en el **Host** y servicios contenedorizados gestionados por **Docker**.

```ascii
                                      +--------------------------------+
                                      |       Usuario (Navegador)      |
                                      +--------------------------------+
                                                 |       ^
                                                 |       | (Túnel SSH Opcional)
                                                 v       |
+--------------------------------------------------------------------------------------------+
|                                        VM Host (Ubuntu/Debian)                             |
|                                                                                            |
|   +--------------------------+         +--------------------------+                        |
|   |         Público          |         |      Acceso Local        |                        |
|   |--------------------------|         |--------------------------|                        |
|   |   HTTP/S (Port: 3000)    |         |     SSH   (Port: 22)     |                        |
|   +--------------------------+         +--------------------------+                        |
|      |                                    |                                                |
|      |                                    |                                                |
|      v (Docker Port Mapping)              v (Túnel)                                        |
| +----------------------------------------------------------------------------------------+ |
| |                                     Docker Engine                                      | |
| |                                   (Network: rag_net)                                   | |
| |                                                                                        | |
| |    +---------------------+      +------------------------+      +--------------------+ | |
| |    |   Open WebUI        |<---->| RAG Control Center     |<---->|   Docker Socket    | | |
| |    | (Chat Interface)    |      | (API & Dashboard)      |      |   (/var/run/...)   | | |
| |    | Port: 0.0.0.0:3000  |      | Port: 127.0.0.1:3200   |      +--------------------+ | |
| |    +---------------------+      +------------------------+                             | |
| |      ^      |                           |          ^                                   | |
| |      |      |                           |          |                                   | |
| |      |      | (host.docker.internal)    |          | (Llamadas a scripts)            | |
| |      |      v                           v          v                                   | |
| +------|---------------------------------------------------------------------------------+ |
|      | |                                     |          |                                 |
|      v |                                     v          v                                 |
|   +--------------------------+   +--------------------------+   +-------------------------+  |
|   |       Ollama (Host)      |   | Python Venv & Scripts    |   |    Archivos del Host    |  |
|   | (LLM Server)             |<->| (/opt/rag_lab/scripts)   |   | (/opt/rag_lab, /var/log)|  |
|   | Port: 127.0.0.1:11434    |   +--------------------------+   +-------------------------+  |
|   +--------------------------+                                                              |
|                                                                                            |
+--------------------------------------------------------------------------------------------+

```

## Características Incluidas

Este instalador configura una suite completa de herramientas:

- **Servidor de Modelos LLM**:
  - **Ollama**: Se instala directamente en el host para un rendimiento óptimo, con el modelo `phi3:3.8b-mini-4k-instruct-q4_K_M` pre-descargado y listo para usar.

- **Interfaz de Usuario (Chat)**:
  - **Open WebUI**: Una interfaz de chat moderna y responsiva, expuesta públicamente para que puedas interactuar con tus modelos y documentos desde cualquier lugar.

- **Núcleo RAG**:
  - **Qdrant**: Base de datos vectorial de alto rendimiento para almacenar y buscar embeddings, accesible solo localmente.
  - **Scripts de Ingesta**: Un script de Python (`ingestion_script.py`) que automáticamente procesa documentos (PDF, TXT, MD), los divide, genera embeddings y los almacena en Qdrant.

- **Panel de Control y Operaciones**:
  - **RAG Control Center**: Un dashboard web interno (`localhost:3200`) creado a medida para esta plataforma. Permite ver el estado de los servicios, ejecutar tareas comunes (ingesta, backups), y modificar la configuración del sistema de forma segura.

- **Gestión y Monitoreo**:
  - **Portainer**: Para una visión detallada de los contenedores, logs y el entorno Docker.
  - **Netdata**: Ofrece más de 2000 métricas en tiempo real sobre el rendimiento del servidor (CPU, RAM, disco, red).
  - **Filebrowser**: Una sencilla interfaz web para subir y gestionar los documentos que alimentarán tu sistema RAG.

- **Automatización**:
  - **Cron Job**: Para la re-ingesta automática de documentos cada noche.
  - **Systemd Service**: Asegura que toda la pila de servicios se inicie automáticamente con el servidor.
  - **Scripts de Ayuda**: Un conjunto de scripts (`diag_rag.sh`, `backup.sh`, `restore.sh`, etc.) para facilitar las tareas de mantenimiento.

## Uso Rápido

Para desplegar la plataforma completa, solo necesitas ejecutar un comando en un servidor Ubuntu/Debian limpio:

```bash
sudo bash -c "$(curl -fsSL https://raw.githubusercontent.com/user/repo/main/install_rag_cpu.sh)"
```
*(Nota: Reemplaza la URL con la ubicación real del script)*

El script se encargará de todo lo demás. Una vez finalizado, te presentará las URLs de acceso y los próximos pasos.

## Tu Plataforma en Funcionamiento (El Resultado Final)

Una vez que el script finalice, tendrás acceso a un conjunto de paneles web diseñados para cada tarea. Así es como se verá tu nuevo entorno de trabajo:

### 1. El Chat - Open WebUI

*   **Acceso**: `http://<IP_DE_LA_VM>:3000`
*   **Qué verás**: Una interfaz de chat limpia y moderna, similar a ChatGPT. Aquí es donde interactúas con el modelo LLM. Podrás hacer preguntas directas o, una vez que subas documentos, hacer preguntas sobre ellos y recibir respuestas basadas en su contenido. Es el "frontend" principal de tu plataforma RAG.

### 2. El Centro de Mando - RAG Control Center

*   **Acceso**: `http://localhost:3200` (a través de túnel SSH)
*   **Qué verás**: Tu panel de control privado. En la pantalla principal, verás el estado de todos los contenedores (Qdrant, Open WebUI, etc.) con indicadores de salud verdes o rojos. Habrá botones grandes para ejecutar acciones con un solo clic: "Iniciar Ingesta", "Crear Backup", "Ejecutar Diagnóstico". También verás una sección para editar la configuración (`.env`) directamente desde la web.

### 3. El Gestor de Documentos - Filebrowser

*   **Acceso**: `http://localhost:8080` (a través de túnel SSH)
*   **Qué verás**: Una interfaz simple de gestión de archivos, como una carpeta en la nube. Aquí es donde arrastras y sueltas tus archivos PDF, TXT o Markdown para que la plataforma los "aprenda".

### 4. El Administrador de Contenedores - Portainer

*   **Acceso**: `http://localhost:9000` (a través de túnel SSH)
*   **Qué verás**: Un dashboard técnico avanzado. Verás una lista de todos tus contenedores, su consumo de CPU y RAM en tiempo real, y podrás acceder a sus logs en vivo. Es la herramienta para una depuración y gestión más profunda.

### 5. El Monitor de Rendimiento - Netdata

*   **Acceso**: `http://localhost:19999` (a través de túnel SSH)
*   **Qué verás**: Cientos de gráficos y medidores en tiempo real que muestran cada detalle del rendimiento de tu servidor. Desde el uso de cada núcleo de la CPU hasta el tráfico de red y las operaciones de disco. Es el electrocardiograma de tu VM.
