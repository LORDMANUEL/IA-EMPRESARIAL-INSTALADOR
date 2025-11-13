# RGIA MASTER Pro: Tu Plataforma de IA Corporativa Privada en Minutos

```
██████╗  ██████╗ ██╗ █████╗     ███╗   ███╗ █████╗ ███████╗████████╗██████╗
██╔══██╗██╔════╝ ██║██╔══██╗    ████╗ ████║██╔══██╗██╔════╝╚══██╔══╝██╔══██╗
██████╔╝██║  ███╗██║███████║    ██╔████╔██║███████║███████╗   ██║   ██████╔╝
██╔══██╗██║   ██║██║██╔══██║    ██║╚██╔╝██║██╔══██║╚════██║   ██║   ██╔══██╗
██║  ██║╚██████╔╝██║██║  ██║    ██║ ╚═╝ ██║██║  ██║███████║   ██║   ██║  ██║
╚═╝  ╚═╝ ╚═════╝ ╚═╝╚═╝  ╚═╝    ╚═╝     ╚═╝╚═╝  ╚═╝╚══════╝   ╚═╝   ╚═╝  ╚═╝
```
*Hecho por Luis Fajardo Rivera (lmfr)*

---

**¡Bienvenido a RGIA MASTER Pro!** Esta es una plataforma de **Inteligencia Artificial Generativa (RAG)** de nivel empresarial que puedes desplegar en tu propio servidor Ubuntu/Debian con un solo comando. Transforma tus documentos y datos en un "cerebro" corporativo privado, seguro y potente.

## Análisis Completo de la Plataforma

### ¿Es Funcional y Está Terminado?

**Sí, absolutamente.** La plataforma RGIA MASTER Pro está **terminada y es 100% funcional**. El script `install_rag_cpu.sh` es una solución robusta y probada que instala y configura todo el ecosistema de IA, incluyendo las características avanzadas que definen la versión "Pro".

### Puntos Fuertes vs. Áreas de Mejora

*   **🚀 Puntos Fuertes (Lo "Super Cool"):**
    *   **Despliegue "Cero a Héroe":** Transforma un servidor limpio en una plataforma de IA completa en minutos.
    *   **🔐 Privacidad Total:** Todo se ejecuta en tu infraestructura. Tus datos nunca salen.
    *   **🕹️ RAG Control Center:** Un panel de control web único para gestionar inquilinos, ingesta de datos (incluyendo SQL), creación de agentes y configuración.
    *   **🏢 Arquitectura Multi-Inquilino:** Aísla datos por departamento o cliente para una escalabilidad y organización de nivel empresarial.
    *   **🤖 Flexibilidad de Modelos:** Elige fácilmente entre LLMs optimizados para velocidad, equilibrio o potencia.

*   **🔍 Áreas de Mejora (Para el Futuro):**
    *   **Gestión de Backups:** La creación de copias de seguridad se realiza por script; una interfaz gráfica en el Control Center sería una gran mejora.
    *   **Procesamiento OCR:** La plataforma es excelente con documentos de texto. Un motor OCR para PDFs escaneados la haría aún más potente.
    *   **Interfaz Unificada:** Una futura versión podría integrar las métricas y logs más importantes directamente en el RAG Control Center.

### Versiones del Sistema: Base vs. Pro

El script instala directamente la **Versión Pro**, pero se puede entender en dos capas:
*   **Versión Base (El Núcleo):** El motor RAG fundamental: Ollama, Qdrant, Open WebUI y la capacidad de ingesta y consulta en un único espacio.
*   **Versión Pro (Lo que obtienes con este script):**
    *   Selección de Modelos LLM.
    *   Arquitectura Multi-Inquilino.
    *   Conectores de Datos (SQL).
    *   Agentes Proactivos (con detección de intenciones).
    *   El RAG Control Center completo para gestionar todo.

## Instalación

Para desplegar la plataforma completa, ejecuta el siguiente comando en un servidor Ubuntu/Debian limpio:

```bash
sudo bash -c "$(curl -fsSL https://raw.githubusercontent.com/tu_usuario/tu_repositorio/main/install_rag_cpu.sh)"
```
*(Nota: Reemplaza la URL con la ubicación real del script en tu repositorio)*

## Documentación y Página del Proyecto

*   **Documentación Completa:** Se genera automáticamente por el script y se encuentra en `/opt/rag_lab/README.md` en tu servidor después de la instalación.
*   **Página del Proyecto:** Visita nuestra página de inicio para un resumen rápido y atractivo de la plataforma.

¡Disfruta de tu nueva plataforma de IA privada!
