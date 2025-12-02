#!/bin/bash
echo "[INFO] Verificando modelos..."
if ! ollama list | grep -q "llama3"; then
    echo "Descargando llama3..."
    ollama pull llama3
fi
if ! ollama list | grep -q "nomic-embed-text"; then
    echo "Descargando nomic-embed-text..."
    ollama pull nomic-embed-text
fi

if [ ! -d "venv" ]; then
    echo "Creando entorno virtual..."
    python3 -m venv venv
fi

echo "Instalando dependencias..."
./venv/bin/pip install -r requirements.txt

echo "Iniciando Servidor..."
./venv/bin/python backend.py
