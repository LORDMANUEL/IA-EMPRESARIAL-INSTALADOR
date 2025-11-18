# RGIA Master – RAG CPU Lab (Plataforma IA Empresarial On-Prem)

<p align="center">
  <img alt="Version" src="https://img.shields.io/badge/version-v1.0-blue?style=for-the-badge">
  <img alt="Status" src="https://img.shields.io/badge/status-estable-green?style=for-the-badge">
  <img alt="License" src="https://img.shields.io/badge/license-Open_Source-lightgrey?style=for-the-badge">
  <img alt="Compatibility" src="https://img.shields.io/badge/compatible-Ubuntu_|_Debian-orange?style=for-the-badge">
</p>

**RGIA Master** es una plataforma de **Retrieval-Augmented Generation (RAG)** de código abierto, diseñada para ser desplegada con un solo comando en tu propia infraestructura.

## Misión y Visión
- **Misión:** “Simplificar y democratizar la adopción de IA empresarial, entregando una plataforma RAG lista para producción, segura y optimizada para CPU.”
- **Visión:** “Ser el estándar abierto de referencia para laboratorios de IA empresarial en Latinoamérica.”

---

## Ahorro y Eficiencia: La Ventaja de la Arquitectura RAG
RGIA Master utiliza RAG para **ahorrar costos y tiempo** en comparación con el fine-tuning. En lugar de re-entrenar modelos con GPUs costosas, usamos modelos pre-entrenados y los "aumentamos" en tiempo real con tus documentos, manteniendo el conocimiento siempre actualizado y reduciendo drásticamente la barrera de entrada para la IA empresarial.

---

## Dos Versiones, Dos Soluciones
Este repositorio contiene dos versiones de la plataforma. Elige la que mejor se adapte a tus necesidades.

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

## Despliegue en un Servidor en la Nube (Cloud VM)
RGIA Master es ideal para ser desplegado en cualquier proveedor de nube (DigitalOcean, AWS, etc.).
1.  **Crear una VM:** Ubuntu 22.04 con los [requisitos mínimos](#requisitos-mínimos).
2.  **Configurar Firewall:** Permite el tráfico entrante en `TCP/22` (SSH) y `TCP/3000` (Open WebUI).
3.  **Instalar RGIA Master:** Conéctate por SSH y sigue las instrucciones de instalación.

### Aprovechando la Plataforma de Forma Segura: El Túnel SSH
Para acceder a los servicios internos (Filebrowser, Portainer, Control Center) sin exponerlos a internet, usa un túnel SSH desde tu máquina local:
```bash
# Reemplaza `usuario` y `IP_DEL_SERVIDOR` con los datos de tu VM
ssh -L 8080:127.0.0.1:8080 -L 9000:127.0.0.1:9000 -L 8000:127.0.0.1:8000 -N usuario@IP_DEL_SERVIDOR
```
Mientras el túnel esté activo, accede a los servicios en `http://localhost:<puerto>`.

---
## Requisitos Mínimos
- **Sistema Operativo:** Ubuntu 20.04/22.04 o Debian 11/12.
- **CPU:** 4+ vCores recomendados.
- **RAM:** 16 GB recomendado.
- **Disco:** 25 GB de espacio libre.
