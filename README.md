<div align="center"><h1>🚀 IA EMPRESARIAL 🚀</h1><p><strong>Tu Plataforma RAG Privada. Auto-Instalable. Lista en Minutos.</strong></p>
<p><img src="https://img.shields.io/badge/Versión-6.1-blue.svg"><img src="https://img.shields.io/badge/Licencia-MIT-green.svg"><img src="https://img.shields.io/badge/Plataforma-Ubuntu%2FDebian-orange.svg"></p></div>

---

### Misión y Visión
*   **Misión:** Democratizar la IA empresarial con una plataforma RAG lista para producción, segura, y optimizada para CPU, que se instale con un solo script.
*   **Visión:** Ser el estándar abierto de referencia para laboratorios de IA empresarial en Latinoamérica.

---
### 🌟 Ediciones

| Característica | `Base` | `Pro` | `Pro Max` |
|---|:---:|:---:|:---:|
| Motor RAG Esencial | ✅ | ✅ | ✅ |
| Soporte Multi-Tenant | ❌ | ✅ | ✅ |
| Control Center RAG | ❌ | ✅ | ✅ |
| OCR para PDFs | ❌ | ✅ | ✅ |
| Asistente de Instalación | ✅ | ✅ | ✅ |
| Gestión de Modelos (UI) | ❌ | ❌ | ✅ |

---

### 🚀 Instalación
```bash
# 1. Clona el repositorio
git clone https://github.com/LORDMANUEL/IA-EMPRESARIAL-INSTALADOR.git
cd IA-EMPRESARIAL-INSTALADOR

# 2. Ejecuta el instalador como root
sudo bash ./install_ia_empresarial.sh
```
El instalador te guiará a través de un asistente para elegir tu edición y configurar la plataforma.

---
### ✅ Calidad Garantizada: Smoke Tests
Al finalizar, el script ejecuta **pruebas automáticas** para validar cada componente. Esto te da la tranquilidad de que la plataforma no solo se "instaló", sino que está **verificada y lista para trabajar**.

---
### ⚙️ Errores Comunes y Soluciones

| Código | Mensaje | Causa Probable | Solución |
|---|---|---|---|
| E001 | DOCKER_INSTALL_FAILED | Red o repositorios APT | Revisa tu conexión y el log `/var/log/ia_empresarial_install.log`. |
| E002 | OLLAMA_INSTALL_FAILED | Fallo del script de Ollama | Instala Ollama manually y re-ejecuta. |
| E003 | MODEL_PULL_FAILED | Red o el modelo no existe | Verifica tu conexión y el nombre del modelo. |
| E006 | DOCKER_COMPOSE_FAILED | Puertos ocupados | Revisa `docker compose logs` para ver el conflicto en el directorio de instalación. |
| E007 | QDRANT_HEALTHCHECK_FAILED | Qdrant no pudo iniciarse | Revisa `docker compose logs qdrant` y el espacio en disco. |
