<div align="center">
  <h1>
    🚀 RGIA MASTER 🚀
  </h1>
  <p>
    <strong>Tu Plataforma RAG Empresarial Privada. Auto-Instalable. Lista en Minutos.</strong>
  </p>
  <p>
    <img src="https://img.shields.io/badge/Versión-2.0-blue.svg" alt="Versión 2.0">
    <img src="https://img.shields.io/badge/Licencia-MIT-green.svg" alt="Licencia MIT">
    <img src="https://img.shields.io/badge/Plataforma-Ubuntu%2FDebian-orange.svg" alt="Plataforma Ubuntu/Debian">
    <img src="https://img.shields.io/badge/CPU--Ready-Yes-brightgreen.svg" alt="CPU Ready">
  </p>
</div>

---

### 💡 ¿Por Qué RGIA Master?

En la era de la IA, las empresas se enfrentan a un dilema: ¿cómo aprovechar el poder de los Modelos de Lenguaje (LLMs) con **nuestros propios datos**, de forma **privada y segura**, sin incurrir en costos astronómicos o depender de APIs de terceros?

**RGIA Master** nace como la respuesta a ese desafío. Es una solución de un solo clic que despliega una plataforma completa de **Generación Aumentada por Recuperación (RAG)** en tu propia infraestructura. Olvídate de la complejidad. Con un solo script, tendrás un ecosistema de IA listo para producción, donde tus datos nunca salen de tu control.

---

### 🎯 ¿Qué Obtendrás al Ejecutar el Script?

Al finalizar la instalación, tendrás un ecosistema de IA 100% funcional y listo para usar:

*   **🧠 Un Cerebro Central (Ollama + Qdrant):** Un motor de IA que corre localmente, combinado con una base de datos vectorial de alto rendimiento para almacenar y buscar en tus documentos.
*   **💬 Una Interfaz de Chat Inteligente (Open WebUI):** Un portal web elegante y moderno para que tus equipos puedan conversar con la IA y obtener respuestas basadas en la documentación de tu empresa.
*   **🛠️ Un Centro de Control Total (RGIA Control Center - Versión Pro):** Un dashboard web para gestionar la ingesta de datos, crear y administrar copias de seguridad, y diagnosticar el estado del sistema con un solo clic.
*   **📊 Paneles de Monitoreo Completos (Portainer + Netdata):** Control absoluto sobre tus contenedores y métricas en tiempo real de tu servidor (CPU, RAM, disco) para garantizar la salud y el rendimiento de la plataforma.
*   **🔐 Seguridad por Defecto:** Todos los servicios de gestión son **privados** y accesibles solo desde `localhost`. Solo la interfaz de chat se expone a tu red, protegiendo tu infraestructura.

---

### 🏢 Tu IA Empresarial Privada: RAG como Base Fundamental

Muchas empresas creen que necesitan "entrenar su propio modelo". Esto es un error costoso y, en la mayoría de los casos, innecesario.

El **entrenamiento** o el **fine-tuning** enseñan a un modelo *nuevas habilidades* o *estilos*, pero no son eficientes para enseñarle *conocimiento fáctico* que cambia constantemente (como tu base de documental).

Aquí es donde brilla el **RAG**:

1.  **Conocimiento Fresco y Dinámico:** La IA "aprende" de tus documentos en tiempo real. Si actualizas un manual o añades un nuevo informe, la IA lo sabe al instante en la siguiente ingesta. No necesitas re-entrenar nada.
2.  **Trazabilidad y Confianza:** Las respuestas de la IA están **basadas en fragmentos reales de tus documentos**. Esto elimina las "alucinaciones" y permite a los usuarios verificar la fuente de cada afirmación.
3.  **Costo-Eficiencia Extrema:** Utilizas modelos pre-entrenados de altísima calidad (como `phi3`, `llama3`) y los especializas en tus datos sin los costos prohibitivos de GPU y tiempo asociados al entrenamiento.
4.  **Seguridad y Privacidad:** Tus datos se convierten en vectores y se quedan en tu base de datos Qdrant, en tu servidor. Nunca se envían a terceros.

**RGIA Master** te da esta capacidad estratégica desde el primer día, proporcionando una base sólida y escalable para construir tu IA empresarial.

---

### 🚀 Instalación: De Cero a Héroe en un Comando

La instalación es simple. Elige la versión que necesitas y ejecútala como `root`.

```bash
# 1. Clona el repositorio
git clone https://github.com/tu_usuario/rgia-master.git
cd rgia-master

# 2. Elige tu versión y ejecuta el instalador
# Para la versión Base (esencial)
sudo bash ./install_rag_base.sh

# Para la versión Pro (con Control Center, OCR y multi-tenant)
sudo bash ./install_rag_pro.sh
```

El script se encargará de todo: instalar dependencias, configurar Docker, descargar los modelos y orquestar los servicios. ¡Toma un café y vuelve para ver tu plataforma de IA lista!

---

### 🛠️ Arquitectura y Servicios

El ecosistema está diseñado para ser seguro y fácil de administrar.

```plaintext
           🌐 Red Pública / LAN 🌐
                    |
+------------------------------------------+
|            SERVIDOR (Ubuntu/Debian)      |
|                                          |
|  +------------------+                    |
|  |   Open WebUI     | <-- 🌍 Acceso Público (Ej: :3000)
|  |   (Chat UI)      |
|  +------------------+                    |
|                                          |
|  +------------------+                    |
|  |   Ollama (Host)  | <-- 🔑 Acceso Localhost (o LAN si se expone)
|  |   (Motor LLM)    |
|  +------------------+                    |
|                                          |
|  ----------- Red Privada Docker ('rag_net') ------------
|  |                                                    |
|  | +-----------------+   +------------------------+   |
|  | | Qdrant          |   | RGIA Control Center    |   |
|  | | (Vector DB)     |   | (Gestión - Pro)        |   |
|  | | 🚪:6333 (local) |   | 🚪:8001 (local)        |   |
|  | +-----------------+   +------------------------+   |
|  |                                                    |
|  | +-----------------+   +------------------------+   |
|  | | Portainer       |   | Netdata / Filebrowser  |   |
|  | | (Monitor Docker)|   | (Otros - local)        |   |
|  | | 🚪:9000 (local) |   | 🚪:19999 / :8081       |   |
|  | +-----------------+   +------------------------+   |
|  |                                                    |
|  ------------------------------------------------------
|                                          |
+------------------------------------------+
```

Para acceder a los paneles de gestión (`Control Center`, `Portainer`, etc.) desde tu máquina, usa un **túnel SSH**:
```bash
ssh -L 8001:127.0.0.1:8001 -L 9000:127.0.0.1:9000 -L 19999:127.0.0.1:19999 -L 8081:127.0.0.1:8081 tu_usuario@<IP_DEL_SERVIDOR>
```

---

### ✅ Smoke Tests y Garantía de Calidad

Al finalizar la instalación, el script ejecuta una serie de **pruebas automáticas (smoke tests)** para verificar que cada componente crítico de la plataforma esté funcionando correctamente. Esto no es una simulación, es una validación real del entorno recién creado.

**¿Qué verificamos?**
*   `[✔] Docker & Servicios:` Que todos los contenedores (Qdrant, Open WebUI, etc.) se hayan levantado correctamente.
*   `[✔] Conectividad de la Base de Datos:` Que Qdrant esté en línea y listo para recibir datos.
*   `[✔] Disponibilidad del Modelo LLM:` Que Ollama haya descargado el modelo y esté listo para procesar consultas.
*   `[✔] Funcionalidad del Control Center (Pro):` Que la interfaz web de gestión sea accesible.
*   `[✔] Flujo de Ingesta End-to-End (Pro):` Se realiza una ingesta de prueba para asegurar que el pipeline de datos funcione.

Este proceso te da la **tranquilidad** de que la plataforma no solo se "instaló", sino que está **operativa y validada**.

---

### ✨ Mejoras Futuras: La Hoja de Ruta de RGIA Master

Este es solo el comienzo. Aquí hay 10 mejoras planeadas para hacer de RGIA Master una herramienta aún más poderosa:

1.  **Asistente de Instalación Interactivo (CLI Wizard):** Una guía interactiva en la terminal para una configuración inicial aún más sencilla.
2.  **Analíticas de Ingesta Avanzadas:** Un dashboard en el Control Center con métricas detalladas y logs de errores por documento.
3.  **Gestión de Documentos y Chunks desde la UI:** Una interfaz para buscar, visualizar y eliminar datos vectorizados.
4.  **Gestión de Modelos LLM desde la UI:** Descargar, eliminar y cambiar modelos de Ollama directamente desde el Control Center.
5.  **Soporte para RAG Multi-Modal:** Capacidad para procesar y consultar sobre imágenes (`.png`, `.jpg`) y audio (`.mp3`).
6.  **Integración con Múltiples Vector Stores:** Añadir soporte para ChromaDB o Weaviate como alternativas a Qdrant.
7.  **Capa de Seguridad Adicional (Opcional):** Integrar un reverse proxy como Traefik para añadir autenticación a los servicios web.
8.  **RAG Basado en Grafos de Conocimiento:** Construir un grafo de conocimiento para permitir consultas relacionales complejas.
9.  **Backups Automatizados en la Nube:** Permitir subir backups a servicios como Amazon S3 o Google Cloud Storage.
10. **Agentes Proactivos y Workflows:** Crear agentes que realicen tareas autónomas, como generar resúmenes automáticos de nuevos documentos.

---
*Este proyecto fue desarrollado por Jules, un agente de software avanzado, con el objetivo de democratizar el acceso a la tecnología RAG de forma segura y eficiente.*
