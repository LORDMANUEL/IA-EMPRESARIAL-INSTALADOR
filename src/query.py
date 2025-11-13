import os, argparse, logging
from pathlib import Path
import ollama
from qdrant_client import QdrantClient
from llama_index.embeddings.huggingface import HuggingFaceEmbedding
from dotenv import load_dotenv

# Configuración de logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')

# Cargar variables de entorno
dotenv_path = Path(__file__).parent.parent / 'config' / '.env'
load_dotenv(dotenv_path=dotenv_path)

# Variables globales
EMBEDDING_MODEL = os.getenv("EMBEDDING_MODEL")
OLLAMA_BIND = os.getenv("OLLAMA_BIND", "127.0.0.1")
LLM_MODEL_CHOICE = os.getenv("LLM_MODEL_CHOICE", "phi3")

# Mapeo de modelos
LLM_MODELS = {
    "phi3": "phi3:3.8b-mini-4k-instruct-q4_K_M",
    "llama3": "llama3:8b-instruct-q4_K_M",
    "gemma": "gemma:7b-instruct-q4_K_M"
}
OLLAMA_MODEL_NAME = LLM_MODELS.get(LLM_MODEL_CHOICE, LLM_MODELS["phi3"])

def main(query: str, tenant: str, collection_prefix: str = "rag_coll_"):
    """Función principal para realizar una consulta RAG a un tenant específico."""
    collection_name = f"{collection_prefix}{tenant}"

    logging.info(f"Realizando consulta para tenant '{tenant}' en la colección '{collection_name}'...")

    # 1. Conectar a Qdrant
    client = QdrantClient(host="127.0.0.1", port=6333)

    # 2. Generar embedding de la consulta
    logging.info(f"Generando embedding para la consulta con el modelo: {EMBEDDING_MODEL}")
    embed_model = HuggingFaceEmbedding(model_name=EMBEDDING_MODEL)
    query_embedding = embed_model.get_query_embedding(query)

    # 3. Buscar en Qdrant
    logging.info("Buscando documentos relevantes en Qdrant...")
    search_result = client.search(
        collection_name=collection_name,
        query_vector=query_embedding,
        limit=5  # Top-K resultados
    )

    if not search_result:
        print("\nNo se encontraron documentos relevantes para responder a tu pregunta.")
        return

    context = "\n---\n".join([hit.payload["text"] for hit in search_result])

    # 4. Construir el prompt para el LLM
    prompt = f"""
    Eres un asistente experto que responde preguntas basándose únicamente en el contexto proporcionado.
    Si la respuesta no se encuentra en el contexto, di explícitamente: "No tengo suficiente información en mis documentos para responder a esa pregunta."

    Contexto Proporcionado:
    {context}

    Pregunta del Usuario: {query}

    Respuesta Precisa y Basada en el Contexto:
    """

    # 5. Consultar a Ollama
    logging.info(f"Enviando prompt al modelo LLM: {OLLAMA_MODEL_NAME}")
    ollama_client = ollama.Client(host=f"http://{OLLAMA_BIND}:11434")

    print("\n--- 🤖 Respuesta del Agente RAG ---\n")
    try:
        response_stream = ollama_client.chat(
            model=OLLAMA_MODEL_NAME,
            messages=[{'role': 'user', 'content': prompt}],
            stream=True
        )

        full_response = ""
        for chunk in response_stream:
            content = chunk['message']['content']
            print(content, end='', flush=True)
            full_response += content

        print("\n\n--------------------------------------\n")

        print("--- 📚 Fuentes Utilizadas ---\n")
        for hit in search_result:
            source = hit.payload.get("metadata", {}).get("source_path", "N/A")
            # Imprimir solo el nombre del archivo, no la ruta completa
            file_name = Path(source).name
            print(f"- {file_name} (Puntuación de Relevancia: {hit.score:.4f})")
        print("\n---------------------------\n")

    except Exception as e:
        logging.error(f"Error al comunicarse con Ollama: {e}")
        print("\nError: No se pudo obtener una respuesta del modelo de lenguaje. Asegúrate de que Ollama esté corriendo y sea accesible.")

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Agente de consulta RAG para la plataforma RGIA Master.")
    parser.add_argument("query", type=str, help="La pregunta que deseas hacer.")
    parser.add_argument("--tenant", type=str, required=True, help="El tenant sobre el cual realizar la consulta.")
    args = parser.parse_args()

    main(args.query, args.tenant)
