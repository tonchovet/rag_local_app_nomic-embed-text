@echo off
echo ===================================================
echo Iniciando Backend RAG (Modo Turbo)
echo ===================================================

echo [INFO] Verificando modelo de CHAT (llama3)...
ollama list | findstr "llama3" >nul
if %errorlevel% neq 0 (
    echo [ALERTA] Descargando llama3...
    ollama pull llama3
) else (
    echo [OK] Chat model listo.
)

echo [INFO] Verificando modelo de EMBEDDING (nomic-embed-text)...
ollama list | findstr "nomic-embed-text" >nul
if %errorlevel% neq 0 (
    echo [ALERTA] Descargando nomic-embed-text - esto es rapido...
    ollama pull nomic-embed-text
) else (
    echo [OK] Embedding model listo.
)

if exist "venv" goto venv_exists
echo [INFO] Creando entorno virtual...
python -m venv venv
:venv_exists

echo [INFO] Activando entorno...
call venv\Scripts\activate

echo [INFO] Actualizando PIP...
python -m pip install --upgrade pip

echo [INFO] Verificando dependencias...
pip install -r requirements.txt
if %errorlevel% neq 0 goto install_error

echo.
echo [INFO] Iniciando Servidor en http://localhost:8000 ...
venv\Scripts\python.exe backend.py

if %errorlevel% neq 0 goto server_crash
goto end

:install_error
echo [ERROR] Error instalando librerias.
pause
exit /b

:server_crash
echo [CRASH] Servidor cerrado con error.
pause
exit /b

:end
pause
