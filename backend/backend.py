import os
import sys
import uvicorn
from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
from typing import List

# Verificación de entorno visual
print(f"Iniciando Python desde: {sys.executable}")

try:
    from langchain_community.document_loaders import TextLoader, PyPDFLoader, Docx2txtLoader
    from langchain_text_splitters import RecursiveCharacterTextSplitter
    from langchain_chroma import Chroma
    from langchain_ollama import OllamaLLM, OllamaEmbeddings
    from langchain_core.prompts import ChatPromptTemplate
    from langchain_core.output_parsers import StrOutputParser
    from langchain_core.runnables import RunnablePassthrough
except ImportError as e:
    print("\n" + "="*50)
    print("!!! ERROR CRÍTICO DE IMPORTACIÓN !!!")
    print("SOLUCIÓN: Borra la carpeta 'venv' y ejecuta 'run_backend.bat'.")
    sys.exit(1)

app = FastAPI(title="Local RAG API with Ollama")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# --- CONFIGURACIÓN DE MODELOS ---
# Usamos Llama3 para PENSAR (Chat)
CHAT_MODEL = "llama3" 
# Usamos Nomic para LEER (Embeddings) -> Mucho más rápido y preciso
EMBEDDING_MODEL = "nomic-embed-text" 

VECTOR_DB_PATH = "./chroma_db"
vectorstore = None

class IngestRequest(BaseModel):
    folder_path: str

class ChatRequest(BaseModel):
    question: str

def get_or_create_vectorstore():
    global vectorstore
    if vectorstore is not None:
        return vectorstore
    
    if os.path.exists(VECTOR_DB_PATH) and os.listdir(VECTOR_DB_PATH):
        try:
            print("Cargando base de datos vectorial existente...")
            # IMPORTANTE: Usar el mismo modelo de embeddings al cargar
            embeddings = OllamaEmbeddings(model=EMBEDDING_MODEL)
            vectorstore = Chroma(
                persist_directory=VECTOR_DB_PATH, 
                embedding_function=embeddings, 
                collection_name="local_docs"
            )
            return vectorstore
        except Exception as e:
            print(f"Error cargando DB existente: {e}")
            return None
    return None

def load_documents_from_folder(folder_path: str):
    documents = []
    if not os.path.exists(folder_path):
        raise FileNotFoundError(f"La carpeta {folder_path} no existe.")

    print(f"Escaneando carpeta: {folder_path}")
    for root, _, files in os.walk(folder_path):
        for file in files:
            file_path = os.path.join(root, file)
            try:
                if file.endswith(".txt"):
                    loader = TextLoader(file_path, encoding="utf-8")
                    documents.extend(loader.load())
                elif file.endswith(".pdf"):
                    loader = PyPDFLoader(file_path)
                    documents.extend(loader.load())
                elif file.endswith(".docx") or file.endswith(".doc"):
                    loader = Docx2txtLoader(file_path)
                    documents.extend(loader.load())
            except Exception as e:
                print(f"Error cargando {file}: {e}")
    return documents

@app.post("/ingest")
async def ingest_documents(request: IngestRequest):
    global vectorstore
    try:
        clean_path = request.folder_path.replace('"', '').strip()
        print(f"Iniciando ingestión desde: {clean_path}")
        docs = load_documents_from_folder(clean_path)
        if not docs:
            return {"status": "warning", "message": "No se encontraron documentos compatibles."}

        text_splitter = RecursiveCharacterTextSplitter(chunk_size=1000, chunk_overlap=200)
        splits = text_splitter.split_documents(docs)

        print(f"Generando embeddings ultra-rapidos con {EMBEDDING_MODEL}...")
        try:
            embeddings = OllamaEmbeddings(model=EMBEDDING_MODEL)
            embeddings.embed_query("test") # Test de conectividad
        except Exception as e:
            if "not found" in str(e).lower() or "404" in str(e):
                raise HTTPException(status_code=404, detail=f"Modelo '{EMBEDDING_MODEL}' no instalado. El script de arranque debería haberlo instalado.")
            raise e

        # Crear y persistir DB
        vectorstore = Chroma.from_documents(
            documents=splits, 
            embedding=embeddings,
            collection_name="local_docs",
            persist_directory=VECTOR_DB_PATH
        )

        return {"status": "success", "message": f"¡Velocidad Turbo! Indexados {len(docs)} archivos ({len(splits)} fragmentos)."}

    except HTTPException as he:
        raise he
    except Exception as e:
        print(f"Error en ingest: {e}")
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/chat")
async def chat(request: ChatRequest):
    vs = get_or_create_vectorstore()
    if not vs:
        raise HTTPException(status_code=400, detail="Primero carga documentos.")

    try:
        print(f"Pregunta: {request.question}")
        
        # 1. Buscar info
        retriever = vs.as_retriever()
        retrieved_docs = retriever.invoke(request.question)
        context_text = "\n\n".join([d.page_content for d in retrieved_docs])
        
        if not context_text:
             return {"answer": "No encontré información relevante en los documentos.", "sources": []}

        # 2. Generar respuesta con Llama 3
        template = """Responde basándote ÚNICAMENTE en el contexto:
{context}

Pregunta: {question}
"""
        prompt = ChatPromptTemplate.from_template(template)
        llm = OllamaLLM(model=CHAT_MODEL)
        output_parser = StrOutputParser()
        chain = prompt | llm | output_parser
        
        answer = chain.invoke({"context": context_text, "question": request.question})
        sources = list(set([doc.metadata.get('source', 'Desc') for doc in retrieved_docs]))

        return {"answer": answer, "sources": sources}
    except Exception as e:
        print(f"Error chat: {e}")
        if "not found" in str(e).lower():
             raise HTTPException(status_code=404, detail=f"Modelo '{CHAT_MODEL}' no encontrado.")
        raise HTTPException(status_code=500, detail=str(e))

if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=8000)
