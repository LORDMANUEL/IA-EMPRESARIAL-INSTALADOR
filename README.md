# RGIA MASTER - Tu Plataforma RAG Auto-Instalable

**RGIA MASTER** (Retrieval-Generated Insight Agent) es un proyecto que te permite desplegar una plataforma completa de **Generación Aumentada por Recuperación (RAG)** con un único script. Está diseñado para ser robusto, seguro y fácil de administrar, funcionando eficientemente en entornos de CPU.

Este repositorio ofrece dos versiones para adaptarse a tus necesidades: **Base** y **Pro**.

![Arquitectura RGIA](https://i.imgur.com/example.png)  <!-- Enlace de imagen de ejemplo -->

---

## Versiones Disponibles

Elige la versión que mejor se adapte a tu caso de uso.

| Característica                 | `install_rag_base.sh` (Base)                                | `install_rag_pro.sh` (Pro)                                     |
| ------------------------------ | ----------------------------------------------------------- | -------------------------------------------------------------- |
| **Motor RAG Principal**        | ✅ (Ollama + Qdrant + Embeddings)                           | ✅ (Ollama + Qdrant + Embeddings)                           |
| **Interfaz de Chat**           | ✅ (Open WebUI)                                             | ✅ (Open WebUI)                                             |
| **Paneles de Monitoreo**       | ✅ (Portainer, Netdata)                                     | ✅ (Portainer, Netdata)                                     |
| **Gestor de Documentos**       | ✅ (Filebrowser)                                            | ✅ (Filebrowser)                                            |
| **Instalador Único**           | ✅ Idempotente y automatizado                               | ✅ Idempotente y automatizado                               |
| **Scripts de Ayuda**           | ✅ (Backup, Restore, Diag)                                  | ✅ (Backup, Restore, Diag)                                  |
| **Soporte Multi-Tenant**       | ❌ (Entorno único)                                          | ✅ (Aisla datos por cliente/proyecto)                     |
| **RGIA Control Center**        | ❌                                                          | ✅ (Dashboard para ingesta, backups y diagnóstico)          |
| **Procesamiento OCR**          | ❌                                                          | ✅ (Extrae texto de PDFs escaneados usando Tesseract)      |
| **Gestión Gráfica de Backups** | ❌                                                          | ✅ (Crea y visualiza backups desde el Control Center)        |
| **Selección de Modelos LLM**   | ❌ (Modelo `phi3` por defecto)                              | ✅ (Elige entre `phi3`, `llama3`, `gemma`)                    |
| **Conector de Datos (PoC)**    | ❌                                                          | ✅ (PoC para ingesta desde bases de datos SQL)               |

---

## ¿Cómo Empezar?

1.  **Clona este repositorio:**
    ```bash
    git clone https://github.com/tu_usuario/rgia-master.git
    cd rgia-master
    ```

2.  **Elige tu versión:**
    -   Para una plataforma RAG esencial, usa la versión **Base**.
    -   Para funcionalidades avanzadas, multi-tenant y gestión centralizada, usa la versión **Pro**.

3.  **Ejecuta el instalador como root:**
    ```bash
    # Para la versión Base
    sudo bash ./install_rag_base.sh

    # Para la versión Pro
    sudo bash ./install_rag_pro.sh
    ```
    El script se encargará de instalar Docker, Ollama, las dependencias del sistema y de configurar toda la plataforma.

---

## Arquitectura y Acceso a Servicios

La plataforma expone públicamente solo la interfaz de chat (Open WebUI). El resto de los servicios son accesibles únicamente desde `localhost` por seguridad.

-   **Open WebUI (Chat)**: `http://<IP_DE_TU_VM>:3000`
-   **RGIA Control Center (Pro)**: `http://127.0.0.1:8001`
-   **Filebrowser (Gestor de Archivos)**: `http://127.0.0.1:8081`
-   **Portainer (Monitor Docker)**: `http://127.0.0.1:9000`
-   **Netdata (Monitor del Host)**: `http://127.0.0.1:19999`
-   **Qdrant (Vector Store)**: `http://127.0.0.1:6333`

Para acceder a los servicios `localhost` desde tu máquina, puedes usar un túnel SSH:
```bash
ssh -L 8001:127.0.0.1:8001 -L 8081:127.0.0.1:8081 -L 9000:127.0.0.1:9000 -L 19999:127.0.0.1:19999 tu_usuario@<IP_DE_TU_VM>
```

---

## Uso y Mantenimiento

Toda la configuración y los datos se almacenan en `/opt/rag_lab_base` o `/opt/rag_lab_pro`. Dentro del subdirectorio `scripts/` encontrarás herramientas para gestionar la plataforma:

-   `diag_rag.sh`: Ejecuta un chequeo completo del estado de los servicios.
-   `backup.sh`: Crea una copia de seguridad completa de la plataforma.
-   `restore.sh`: Restaura la plataforma desde una copia de seguridad.

### Ingesta de Datos (Pro)

En la versión Pro, la ingesta se gestiona por "tenants". Simplemente sube tus archivos (`.pdf`, `.txt`, `.md`) al directorio `/opt/rag_lab_pro/documents/<nombre_del_tenant>/` usando Filebrowser o SFTP. Luego, puedes lanzar la ingesta desde el **RGIA Control Center**.

El sistema de ingesta es **idempotente** (no procesará archivos duplicados) y soporta **OCR**, lo que significa que puede extraer texto de documentos PDF que solo contienen imágenes.

---

## Contribuciones

Este proyecto es de código abierto. Las contribuciones, issues y pull requests son bienvenidas.

---
*Este proyecto fue desarrollado por Jules, un agente de software avanzado, con el objetivo de democratizar el acceso a la tecnología RAG.*
