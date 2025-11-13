# Estrategia de Producto: RGIA Master (Base vs. Pro)

Este documento define la visión estratégica y la diferenciación entre las dos versiones de la plataforma RGIA Master.

## Visión General

La estrategia de producto se basa en un modelo de dos niveles:

1.  **RGIA Master (Versión Base):** Una solución **gratuita y de código abierto** diseñada para ser la puerta de entrada perfecta a la IA empresarial. Es robusta, segura y resuelve el caso de uso más común: hacer preguntas sobre documentos basados en texto.
2.  **RGIA Master (Versión Pro):** Una solución **comercial o de suscripción** que se construye sobre la base sólida de la versión gratuita, añadiendo capacidades avanzadas para resolver problemas empresariales complejos y ofrecer una gestión centralizada.

El objetivo es maximizar la adopción a través de una versión Base de alto valor, mientras se crea un camino de actualización claro y sostenible hacia la versión Pro para organizaciones con necesidades más maduras.

---

## Contenido Detallado de Cada Versión

| Característica | RGIA Master (Versión Base) | RGIA Master Pro (Visión a Futuro) |
| :--- | :---: | :---: |
| **Instalación Automatizada** | ✅ (Script único, 100% desatendido) | ✅ |
| **Tipo de Documentos (RAG)** | Solo Texto (PDF, TXT, MD) | **Soporte Multi-Modal (Texto, Imágenes, Audio)** |
| **Búsqueda y Razonamiento** | Búsqueda Semántica (Embeddings) | **RAG con Grafos de Conocimiento** (Razonamiento complejo) |
| **Panel de Control Interno** | Dashboard Estático (WebAdmin AI con enlaces) | **RGIA Control Center Avanzado** (UI dinámica para gestión, logs, analíticas) |
| **Seguridad** | ✅ (100% On-Premise, servicios internos aislados) | ✅ (Además de **Gestión de Usuarios y Roles (RBAC)**) |
| **Modelo de Lenguaje (LLM)** | ✅ (Ollama con `phi3` por defecto) | ✅ (Con gestión de múltiples modelos desde la UI) |
| **Modelo de Embeddings** | ✅ (`multilingual-e5-small` por defecto) | ✅ (Con **integración de modelos de vanguardia** y específicos por dominio) |
| **Interfaz de Chat** | ✅ (Open WebUI) | ✅ (Con posibles mejoras y analíticas de uso) |
| **Costo / Licencia** | **Gratuita y de Código Abierto** | **Comercial o de Código Abierto con suscripción** |

---

## Razonamiento Estratégico

### 1. RGIA Master (Versión Base): La Puerta de Entrada a la IA Empresarial

*   **Propósito:** Democratizar y simplificar. El objetivo es eliminar todas las barreras para que cualquier empresa o equipo técnico pueda empezar a experimentar con una plataforma RAG privada y segura.
*   **Público Objetivo:** PYMEs, equipos de desarrollo, laboratorios de innovación y cualquier organización que necesite una solución sólida para su problema más común: **hacer preguntas sobre sus documentos de texto**.
*   **Propuesta de Valor:** Es una solución de "problema resuelto". Con un solo comando, obtienes una plataforma de nivel profesional, segura y gratuita, sin depender de nubes costosas ni de tener hardware especializado (GPU). Genera confianza y demuestra el valor de la IA con los datos propios de la empresa.

### 2. RGIA Master (Versión Pro): La Solución para la Madurez y la Escalabilidad

*   **Propósito:** Resolver problemas complejos y ofrecer una gestión centralizada a nivel empresarial. A medida que una organización madura en su uso de la IA, sus necesidades se vuelven más sofisticadas.
*   **Público Objetivo:** Empresas más grandes, corporaciones con diversos tipos de datos (planos, informes escaneados, grabaciones de reuniones, etc.) y equipos que necesitan analíticas, control de acceso y capacidades de razonamiento más profundas.
*   **Propuesta de Valor:** Es la ruta de "upgrade" natural. Una vez que la versión Base ha demostrado su valor, la versión Pro responde a las siguientes preguntas:
    *   *"¿Y si ahora quiero preguntarle cosas a las imágenes de mis PDFs o a las grabaciones de mis reuniones?"* → **Soporte Multi-Modal**.
    *   *"¿Cómo puedo hacer preguntas que requieran relacionar información entre 5 documentos distintos?"* → **RAG con Grafos de Conocimiento**.
    *   *"¿Cómo puedo gestionar quién tiene acceso, ver quién pregunta qué y administrar todo desde una única interfaz web sin usar la línea de comandos?"* → **RGIA Control Center Avanzado**.
