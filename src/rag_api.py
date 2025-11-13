from fastapi import FastAPI, Request, Form
from fastapi.responses import HTMLResponse, JSONResponse
from fastapi.templating import Jinja2Templates
import os
import subprocess
import json
from dotenv import load_dotenv

# --- Configuración de la App ---
app = FastAPI(
    title="RGIA Master Control Center API",
    description="API para gestionar la plataforma RAG de IA Empresarial.",
    version="1.0.0"
)

# Cargar configuración desde .env
RAG_LAB_DIR = os.getenv("RAG_LAB_DIR", "/opt/rag_lab_pro") # Default a Pro, pero se sobrescribe en el contenedor
load_dotenv(os.path.join(RAG_LAB_DIR, "config", ".env"))

templates = Jinja2Templates(directory=os.path.join(RAG_LAB_DIR, "control_center", "templates"))

# --- Funciones de Ayuda ---
def run_script_in_shell(script_name: str, args: list = []):
    """Ejecuta un script de ayuda ubicado en el directorio de scripts."""
    script_path = os.path.join(RAG_LAB_DIR, "scripts", script_name)
    command = [script_path] + args
    try:
        # Usar el venv de la instalación para ejecutar scripts de Python
        if script_name.endswith(".py"):
            venv_python = os.path.join(RAG_LAB_DIR, "venv", "bin", "python")
            command = [venv_python] + command

        proc = subprocess.run(command, capture_output=True, text=True, check=True)
        return {"status": "success", "output": proc.stdout}
    except subprocess.CalledProcessError as e:
        return {"status": "error", "output": e.stderr}
    except FileNotFoundError:
        return {"status": "error", "output": f"Script no encontrado en {script_path}"}

# --- Endpoints de la Interfaz ---
@app.get("/", response_class=HTMLResponse)
async def get_root(request: Request):
    tenants = os.getenv("TENANTS", "default").split(',')
    return templates.TemplateResponse("index.html", {"request": request, "tenants": tenants})

# --- Endpoints de la API ---
@app.post("/api/ingest", summary="Iniciar ingesta para un tenant")
async def api_run_ingest(tenant: str = Form(...)):
    result = run_script_in_shell("ingestion_script.py", ["--tenant", tenant])
    return JSONResponse(content=result)

@app.get("/api/diagnostics", summary="Obtener diagnóstico del sistema")
async def api_get_diagnostics():
    result = run_script_in_shell("diag_rag.sh")
    return JSONResponse(content=result)

@app.post("/api/backup", summary="Crear un nuevo backup")
async def api_create_backup():
    result = run_script_in_shell("backup.sh")
    return JSONResponse(content=result)

@app.post("/api/restore", summary="Restaurar desde un backup")
async def api_restore_backup(backup_path: str = Form(...)):
    result = run_script_in_shell("restore.sh", [backup_path])
    return JSONResponse(content=result)

@app.get("/api/logs/ingest", summary="Ver los últimos logs de ingesta")
async def api_get_ingest_logs():
    edition = os.getenv("EDITION", "base").lower()
    log_file = f"/var/log/rag_ingest_{edition}.log"
    try:
        proc = subprocess.run(["tail", "-n", "100", log_file], capture_output=True, text=True, check=True)
        return {"status": "success", "output": proc.stdout}
    except subprocess.CalledProcessError as e:
        return {"status": "error", "output": f"No se pudieron leer los logs: {e.stderr}"}

# --- Endpoints Específicos de ProMax ---
@app.get("/api/models", summary="Listar modelos de Ollama (ProMax)")
async def api_list_models():
    if not os.path.exists("/usr/local/bin/ollama"):
        return JSONResponse({"status": "error", "output": "Funcionalidad solo para ProMax"}, status_code=403)

    result = run_script_in_shell("ollama", ["list"])
    return JSONResponse(content=result)

@app.post("/api/models/pull", summary="Descargar un modelo de Ollama (ProMax)")
async def api_pull_model(model_name: str = Form(...)):
    if not os.path.exists("/usr/local/bin/ollama"):
        return JSONResponse({"status": "error", "output": "Funcionalidad solo para ProMax"}, status_code=403)

    # Se ejecuta en segundo plano para no bloquear la API
    subprocess.Popen(["/usr/local/bin/ollama", "pull", model_name], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    return JSONResponse(content={"status": "success", "output": f"La descarga de '{model_name}' ha comenzado en segundo plano."})
