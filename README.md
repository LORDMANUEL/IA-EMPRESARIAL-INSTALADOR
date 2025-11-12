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
*   **Qué verás**: Una interfaz de chat limpia y moderna, similar a ChatGPT.

### 2. El Centro de Mando - RAG Control Center
*   **Acceso**: `http://localhost:3200` (a través de túnel SSH)
*   **Qué verás**: Tu panel de control privado para gestionar la plataforma.

### 3. El Gestor de Documentos - Filebrowser
*   **Acceso**: `http://localhost:8080` (a través de túnel SSH)
*   **Qué verás**: Una interfaz para subir y gestionar los documentos que alimentarán tu IA.

### 4. El Administrador de Contenedores - Portainer
*   **Acceso**: `http://localhost:9000` (a través de túnel SSH)
*   **Qué verás**: Un dashboard técnico para una gestión avanzada de los contenedores.

### 5. El Monitor de Rendimiento - Netdata
*   **Acceso**: `http://localhost:19999` (a través de túnel SSH)
*   **Qué verás**: Métricas en tiempo real del rendimiento de tu servidor.

---

## La IA Corporativa: Privada, Inteligente y sin Entrenamiento Costoso

### ¿Por qué este enfoque es revolucionario?

Tradicionalmente, crear una IA con conocimiento corporativo implicaba un proceso largo y extremadamente costoso: re-entrenar un modelo de lenguaje con tus datos. Este método no solo requiere una inversión millonaria en hardware y tiempo, sino que también crea una "foto estática": el modelo no aprende de nueva información a menos que lo vuelvas a entrenar.

**Este proyecto utiliza Retrieval-Augmented Generation (RAG), un enfoque más inteligente y ágil:**

1.  **LLM como Cerebro Razonador**: Utilizamos un modelo de lenguaje pre-entrenado (como `phi3`) que ya es excelente en razonamiento, lenguaje y seguimiento de instrucciones. No lo modificamos.
2.  **Base de Conocimiento Vectorial**: Tus documentos (los datos de tu empresa) se convierten en una base de conocimiento externa y consultable (en Qdrant).
3.  **Proceso Dinámico**: Cuando haces una pregunta, el sistema primero busca la información más relevante en tu base de conocimiento y luego le pasa esa información al LLM como "contexto" para que formule la respuesta.

### Ventajas Clave:

-   **Privacidad Absoluta**: Todo el sistema, desde el LLM hasta tus documentos, se ejecuta **dentro de tu propio servidor**. Ningún dato sale a APIs de terceros. Cumplimiento y seguridad garantizados.
-   **Conocimiento Siempre Fresco**: Simplemente añade o actualiza documentos y la base de conocimiento se refresca automáticamente (cada noche o manualmente), sin necesidad de re-entrenar nada.
-   **Ahorro Gigante**: Evitas los costes prohibitivos del entrenamiento. La inversión se centra en un servidor adecuado, no en ciclos de GPU de supercomputadoras.

## Guía de Ingesta: ¿Cómo alimentar a tu IA?

La calidad de las respuestas de tu IA depende directamente de la calidad de la información que le proporcionas. Sigue estas mejores prácticas:

-   **Formato de Archivos**: Prefiere archivos de texto plano como **Markdown (`.md`)**. Son ligeros, estructurados y fáciles de procesar. Los archivos PDF y TXT también son soportados.
-   **Estructura Clara**: Utiliza títulos, subtítulos, listas y párrafos cortos. Una buena estructura en tus documentos ayuda al sistema a encontrar fragmentos de información más precisos.
-   **Contenido Limpio**: Evita texto dentro de imágenes, tablas complejas o formattings extraños. Cuanto más limpio y directo sea el texto, mejor.
-   **Un Tema por Documento**: Siempre que sea posible, crea documentos que se centren en un tema específico (ej. "Manual_Producto_X.md", "Politicas_Vacaciones_2024.md"). Esto mejora la relevancia de las búsquedas.

## Requisitos de Hardware y Estimación de Rendimiento

Esta plataforma está diseñada para ser flexible. A continuación, se presentan algunas configuraciones recomendadas y una estimación de su capacidad.

| Componente      | Configuración Mínima (CPU)                                  | Configuración Recomendada (GPU)                                |
|-----------------|-------------------------------------------------------------|----------------------------------------------------------------|
| **CPU**         | 8+ Núcleos (Ej. Intel Xeon E-2278G, AMD Ryzen 7 3700X)       | 8-16+ Núcleos (para soportar la carga general)                 |
| **RAM**         | 32 GB DDR4                                                  | 64 GB DDR4 o más                                               |
| **Almacenamiento**| 500 GB SSD NVMe (para SO, Docker y datos)                   | 1-2 TB SSD NVMe (para una base de conocimiento más grande)     |
| **GPU**         | N/A                                                         | **NVIDIA Tesla P40 (24 GB VRAM)** o superior                   |
| **Red**         | 1 Gbps                                                      | 1 Gbps o más                                                   |

### Estimación de Usuarios Concurrentes

-   **Configuración Mínima (CPU)**: La inferencia del LLM en CPU es lenta. Esta configuración es ideal para **desarrollo, pruebas o un uso muy ligero por 1-3 usuarios simultáneos**. Las respuestas pueden tardar varios segundos en generarse.
-   **Configuración Recomendada (GPU)**: Con una GPU como la NVIDIA P40, la velocidad de inferencia del LLM aumenta drásticamente (10x a 20x más rápido). Esta configuración puede servir cómodamente a un equipo pequeño o mediano, soportando aproximadamente **10-15 usuarios concurrentes** con tiempos de respuesta rápidos (1-3 segundos).
