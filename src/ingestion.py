import os, hashlib, logging, argparse
from pathlib import Path
import pytesseract
from pdf2image import convert_from_path
from llama_index.core import SimpleDirectoryReader, Document
from llama_index.core.node_parser import SentenceSplitter
from llama_index.embeddings.huggingface import HuggingFaceEmbedding
from qdrant_client import QdrantClient, models
from dotenv import load_dotenv
from tqdm import tqdm

# Configuración de logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')

# Cargar variables de entorno desde la ruta de instalación
# Se asume que este script se ejecutará desde un venv en /opt/rag_lab_*/
dotenv_path = Path(__file__).parent.parent / 'config' / '.env'
load_dotenv(dotenv_path=dotenv_path)

# Variables globales
RAG_LAB_DIR = Path(os.getenv("RAG_LAB_DIR"))
EMBEDDING_MODEL = os.getenv("EMBEDDING_MODEL")
ENABLE_OCR = os.getenv("ENABLE_OCR", "false").lower() == "true"
OCR_LANGUAGES = os.getenv("OCR_LANGUAGES", "spa")

def ocr_pdf(path: Path) -> str:
    """Extrae texto de un PDF basado en imágenes usando Tesseract."""
    try:
        return "".join(pytesseract.image_to_string(img, lang=OCR_LANGUAGES) for img in convert_from_path(path))
    except Exception as e:
        logging.error(f"Fallo en el pipeline de OCR para {path}: {e}")
        return ""

def load_documents(docs_path: Path) -> list[Document]:
    """Carga documentos desde una ruta, aplicando OCR si es necesario."""
    docs = []
    patterns = ["**/*.pdf", "**/*.md", "**/*.txt"]
    logging.info(f"Buscando documentos en {docs_path} con patrones: {patterns}")

    files = []
    for pattern in patterns:
        files.extend(list(docs_path.glob(pattern)))

    if not files:
        logging.warning("No se encontraron archivos para los patrones especificados.")
        return []

    for p in tqdm(files, desc="Cargando Documentos"):
        try:
            loaded_docs = SimpleDirectoryReader(input_files=[p]).load_data()
            # Si es un PDF sin texto y el OCR está habilitado, procesarlo
            if p.suffix.lower() == ".pdf" and ENABLE_OCR and (not loaded_docs or not loaded_docs[0].text.strip()):
                logging.warning(f"PDF sin texto detectable: {p}. Intentando OCR.")
                text = ocr_pdf(p)
                if text:
                    docs.append(Document(text=text, metadata={"source_path": str(p)}))
            else:
                docs.extend(loaded_docs)
        except Exception as e:
            logging.error(f"Error crítico al cargar el documento {p}: {e}")
    return docs

def main(tenant: str, collection_prefix: str = "rag_coll_"):
    """Función principal para la ingesta de documentos para un tenant específico."""
    collection_name = f"{collection_prefix}{tenant}"
    docs_dir = RAG_LAB_DIR / "documents" / tenant

    if not docs_dir.is_dir():
        logging.error(f"El directorio del tenant '{tenant}' no existe en {docs_dir}. Saltando ingesta.")
        return

    logging.info(f"--- Iniciando ingesta para tenant: '{tenant}' ---")

    client = QdrantClient(host="127.0.0.1", port=6333)

    # Crear colección si no existe
    try:
        client.get_collection(collection_name=collection_name)
    except Exception:
        logging.info(f"La colección '{collection_name}' no existe. Creándola...")
        client.create_collection(
            collection_name=collection_name,
            vectors_config=models.VectorParams(size=384, distance=models.Distance.COSINE)
        )

    documents = load_documents(docs_dir)
    if not documents:
        logging.info("No se encontraron documentos nuevos o legibles para procesar.")
        return

    node_parser = SentenceSplitter(chunk_size=512, chunk_overlap=50)
    nodes = node_parser.get_nodes_from_documents(documents, show_progress=True)

    logging.info(f"Cargando modelo de embedding: {EMBEDDING_MODEL}...")
    embed_model = HuggingFaceEmbedding(model_name=EMBEDDING_MODEL)

    logging.info(f"Generando embeddings para {len(nodes)} chunks...")
    for n in tqdm(nodes, desc=f"Embeddings para {tenant}"):
        n.embedding = embed_model.get_text_embedding(n.get_content())

    points = [
        models.PointStruct(
            id=hashlib.sha256(n.get_content().encode('utf-8')).hexdigest(),
            vector=n.embedding,
            payload={"text": n.get_content(), "metadata": n.metadata}
        ) for n in nodes
    ]

    logging.info(f"Haciendo upsert de {len(points)} puntos a la colección '{collection_name}'...")
    client.upsert(collection_name=collection_name, points=points, wait=True)

    success(f"--- Ingesta para tenant '{tenant}' completada. {len(points)} chunks procesados. ---")

if __name__ == "__main__":
    # Definir argumentos para la ejecución como script
    parser = argparse.ArgumentParser(description="Script de ingesta de documentos para la plataforma RAG.")
    parser.add_argument("--tenant", type=str, required=True, help="El nombre del tenant para el cual ejecutar la ingesta.")
    args = parser.parse_args()

    # Añadir un handler de logging a un archivo específico para trazabilidad
    log_dir = RAG_LAB_DIR / "logs"
    log_dir.mkdir(exist_ok=True)
    file_handler = logging.FileHandler(log_dir / f"ingest_{args.tenant}.log")
    file_handler.setFormatter(logging.Formatter('%(asctime)s - %(levelname)s - %(message)s'))
    logging.getLogger().addHandler(file_handler)

    def success(message): # Pequeña función helper para logs
        logging.info(message)

    main(args.tenant)
