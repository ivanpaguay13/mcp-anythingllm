# Guía de instalación

Esta guía asume que **nunca has usado git, Python ni una terminal** para
cosas serias. Vamos paso a paso, con comandos copiables.

**Tiempo estimado:** 1-2 horas (más el tiempo de indexación de tus libros).

---

## Índice

1. [Antes de empezar](#antes-de-empezar)
2. [Instalar Ollama](#1-instalar-ollama)
3. [Descargar el modelo de embeddings](#2-descargar-el-modelo-de-embeddings)
4. [Instalar AnythingLLM](#3-instalar-anythingllm)
5. [Configurar AnythingLLM](#4-configurar-anythingllm)
6. [Instalar uv y el wrapper MCP](#5-instalar-uv-y-el-wrapper-mcp)
7. [Configurar Antigravity](#6-configurar-antigravity)
8. [Subir tus primeros libros](#7-subir-tus-primeros-libros)
9. [Verificar que todo funciona](#8-verificar-que-todo-funciona)

---

## Antes de empezar

### Qué necesitas tener instalado

- **Antigravity** (asumimos que ya lo tienes funcionando)
- **Una terminal** (la aplicación "Terminal" de tu sistema)

### Verificar tu sistema operativo

Abre una terminal y ejecuta:

```bash
cat /etc/os-release | head -3
```

Deberías ver el nombre de tu distribución. Si es Fedora, Ubuntu, o macOS,
todo lo que sigue debería funcionar.

---

## 1. Instalar Ollama

Ollama es el motor que genera los embeddings de tus libros. **Solo se usa
durante la indexación** — una vez que los libros están indexados, puedes
cerrarlo.

### Fedora / Linux

```bash
curl -fsSL https://ollama.com/install.sh | sh
```

Esto descarga el binario, crea un usuario dedicado `ollama`, y habilita un
servicio systemd que arranca automáticamente.

Verifica que funciona:

```bash
ollama --version
systemctl status ollama --no-pager | head -5
```

Deberías ver `ollama version is 0.x.x` y `Active: active (running)`.

### macOS

Descarga el instalador desde [ollama.com/download/mac](https://ollama.com/download/mac)
o usa Homebrew:

```bash
brew install ollama
```

En macOS, Ollama corre como una app de menú (aparece un icono junto al reloj).

### Configurar Ollama para CPU

Si tienes una GPU NVIDIA, Ollama la detectará automáticamente. Si tienes AMD
o solo CPU, hay que configurar algunas variables para que el modelo no se
descargue de RAM entre consultas.

**Fedora / Linux:**

```bash
sudo systemctl edit ollama.service
```

Se abre un editor de texto. Añade al final:

```ini
[Service]
Environment="OLLAMA_NUM_PARALLEL=1"
Environment="OLLAMA_MAX_LOADED_MODELS=1"
Environment="OLLAMA_KEEP_ALIVE=30m"
```

Guarda (`Ctrl+O`, `Enter`, `Ctrl+X`) y aplica:

```bash
sudo systemctl daemon-reload
sudo systemctl restart ollama
```

**macOS:** añade estas variables a tu `~/.zshrc`:

```bash
export OLLAMA_NUM_PARALLEL=1
export OLLAMA_MAX_LOADED_MODELS=1
export OLLAMA_KEEP_ALIVE=30m
```

Luego `source ~/.zshrc` para aplicarlas.

---

## 2. Descargar el modelo de embeddings

`bge-m3` es el modelo que convierte tus chunks de texto en vectores. Es
multilingüe (100+ idiomas), por lo que funciona igual de bien con libros
en español o en inglés.

```bash
ollama pull bge-m3
```

Tarda unos minutos (descarga ~1.2 GB). Cuando termine:

```bash
ollama list
```

Deberías ver `bge-m3:latest` en la lista.

---

## 3. Instalar AnythingLLM

AnythingLLM es la aplicación que:

- Ingiere tus PDFs
- Los divide en chunks
- Llama a Ollama para generar los embeddings
- Guarda los vectores en LanceDB
- Expone una API de búsqueda en `localhost:3001`

### Fedora / Linux

```bash
curl -fsSL https://cdn.anythingllm.com/latest/installer.sh -o installer.sh
chmod +x installer.sh
./installer.sh
```

### macOS

Descarga el `.dmg` desde [anythingllm.com](https://anythingllm.com/) o:

```bash
brew install --cask anythingllm
```

### Abrir AnythingLLM

Una vez instalado, ábrelo desde el menú de aplicaciones. La primera vez
tarda ~30 segundos porque crea la base de datos.

**Importante:** AnythingLLM debe estar **siempre abierto** cuando uses el
RAG desde Antigravity. Es el servidor que responde a las consultas.

---

## 4. Configurar AnythingLLM

### 4.1 Configurar el embedder

1. En AnythingLLM, haz clic en el icono de engranaje (⚙️) abajo a la izquierda
2. Ve a **Proveedores de IA → Incrustador (Embedder)**
3. Selecciona **Ollama** como proveedor
4. Modelo: `bge-m3:latest`
5. **Max embedding chunk length:** cambia el valor por defecto (8192) a **1024**
6. Guarda

**Por qué 1024:** chunks de 8.192 tokens diluyen la representación semántica.
Fragmentos de ~1.024 tokens capturan ideas completas sin mezclar temas.

### 4.2 Crear tus workspaces

Un workspace es una colección de libros. Se recomienda **uno por dominio**
(no uno por asignatura de la facultad, ni uno por libro).

Ejemplos que funcionan:

| Workspace | Qué meter |
|-----------|-----------|
| `ciencias-basicas` | Bioquímica, histología, biología celular |
| `fisiologia` | Constanzo, Guyton, Boron |
| `patologia` | Robbins, Kumar, Rubin |
| `propedeutica` | Argente, Surós, Bates |
| `farmacologia` | Katzung, Goodman, Mendoza |
| `genetica` | Thompson, Nussbaum |
| `nutricion` | Krause, Mahan |

**Cómo crear uno:**

1. En AnythingLLM, clic en el **`+`** junto al buscador de workspaces
2. Escribe el nombre **sin tildes** (para que el slug sea limpio)
3. Confirma

**No subas PDFs todavía.** Primero hay que obtener la API key.

### 4.3 Obtener la API key

1. En AnythingLLM, ve a **Settings → Tools → Developer API**
2. Haz clic en **Generate API Key**
3. **Copia la key completa** — solo se muestra una vez
4. Guárdala en un lugar seguro

**Regla de seguridad:** nunca compartas esta key ni la subas a GitHub. Es la
que da acceso a tu instancia local.

### 4.4 Verificar la lista de workspaces

En una terminal:

```bash
curl -s http://localhost:3001/api/v1/workspaces \
  -H "Authorization: Bearer TU_API_KEY" | python3 -m json.tool
```

Sustituye `TU_API_KEY` por tu key real. Deberías ver un JSON con la lista de
workspaces y sus **slugs**. Anota cada slug — lo necesitarás más adelante.

**Importante:** el slug (identificador interno) **no siempre coincide con el
nombre visible**. Por ejemplo, si renombraste un workspace después de crearlo,
el slug puede seguir siendo el original.

---

## 5. Instalar uv y el wrapper MCP

### 5.1 Instalar uv

```bash
curl -LsSf https://astral.sh/uv/install.sh | sh
source ~/.bashrc   # en macOS: source ~/.zshrc
```

Verifica:

```bash
uv --version
```

### 5.2 Clonar este repositorio

```bash
git clone https://github.com/ivanpaguay13/mcp-anythingllm.git
cd mcp-anythingllm
```

### 5.3 Instalar dependencias

```bash
uv sync
```

Esto descarga:

- `mcp[cli]` — SDK de Model Context Protocol (versión 1.x)
- `httpx` — cliente HTTP
- `sentence-transformers` — para el reranker

**La primera vez tarda 3-5 minutos** porque descarga PyTorch (~800 MB).

### 5.4 Editar `server.py` con tus slugs

Abre el archivo:

```bash
nano server.py
```

Busca las líneas que dicen:

```python
return await _buscar("ciencias-basicas", query, top_n)
return await _buscar("fisiologia", query, top_n)
return await _buscar("patologia", query, top_n)
return await _buscar("propedeutica", query, top_n)
return await _buscar("mi-espacio-de-trabajo", query, top_n)
```

Sustituye cada string con el **slug real** que anotaste en el paso 4.4. Si
creaste workspaces con otros nombres, ajusta también el nombre de las
funciones `buscar_*` a lo que corresponda.

### 5.5 Verificar que compila

```bash
uv run python -c "import server; print('OK')"
```

La primera ejecución **descarga el modelo del reranker** (~2.2 GB). Tarda
2-10 minutos según tu conexión.

Cuando termine, verás `OK`.

### 5.6 Probar que arranca

```bash
uv run server.py
```

Debería quedarse "colgado" sin mostrar nada — eso es correcto, está escuchando.
Presiona `Ctrl+C` para salir.

---

## 6. Configurar Antigravity

Antigravity lee los servidores MCP desde un archivo JSON.

### 6.1 Ubicación del archivo

| Sistema | Ruta |
|---------|------|
| Linux / macOS | `~/.gemini/config/mcp_config.json` |

Si el archivo no existe, créalo:

```bash
mkdir -p ~/.gemini/config
nano ~/.gemini/config/mcp_config.json
```

### 6.2 Contenido

Pega lo siguiente, adaptando las rutas y la API key:

```json
{
  "mcpServers": {
    "medicina-rag": {
      "command": "/home/TU_USUARIO/.local/bin/uv",
      "args": [
        "run",
        "--directory",
        "/home/TU_USUARIO/mcp-anythingllm",
        "server.py"
      ],
      "env": {
        "ANYTHINGLLM_URL": "http://localhost:3001",
        "ANYTHINGLLM_API_KEY": "tu-api-key-de-anythingllm-aqui"
      }
    }
  }
}
```

**Dónde encontrar la ruta de `uv`:** ejecuta en tu terminal:

```bash
which uv
```

Y usa esa ruta en el campo `"command"`.

### 6.3 Verificar que el JSON es válido

```bash
python3 -m json.tool ~/.gemini/config/mcp_config.json > /dev/null && echo "JSON válido"
```

Si no ves `JSON válido`, revisa que las comas y llaves estén bien.

### 6.4 Reiniciar Antigravity

```bash
pkill -f antigravity
```

Vuelve a abrirlo. En el panel de MCP servers, deberías ver `medicina-rag`
con las herramientas `buscar_*` listadas.

---

## 7. Subir tus primeros libros

**Antes de empezar:** verifica que Ollama está corriendo.

```bash
systemctl status ollama --no-pager | head -3
```

Si no está activo: `sudo systemctl start ollama`.

### 7.1 Renombrar PDFs antes de subirlos

El nombre del archivo aparecerá en las citas. Renombra los PDFs a algo corto:

- ❌ `Katzung_Basic_Clinical_Pharmacology_16th_edition_2019_scan.pdf`
- ✅ `Katzung 16ed.pdf`

### 7.2 Subir en AnythingLLM

1. Cambia al workspace destino (ej. `Farmacología`)
2. Haz clic en **"Cargar un documento"** o el icono **`+`**
3. Arrastra los PDFs
4. Espera la indexación

**Tiempos aproximados (CPU, por libro):**

| Páginas | Tiempo |
|---------|--------|
| 500 | 8-15 min |
| 1.000 | 15-30 min |
| 1.500 | 25-45 min |

Con GPU dedicada (NVIDIA), estos tiempos se reducen ~10× (1-3 min por libro).

### 7.3 Verificar que terminó

```bash
curl -X POST http://localhost:3001/api/v1/workspace/TU_SLUG/vector-search \
  -H "Authorization: Bearer TU_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"query": "test", "topN": 3, "scoreThreshold": 0.2}'
```

Si ves `"results": [...]` con fragmentos, el workspace está indexado. Si ves
`"No embeddings found"`, la indexación aún no ha terminado.

**Una vez indexado, puedes cerrar Ollama** si quieres. No es necesario para
consultar, solo para indexar nuevos libros.

---

## 8. Verificar que todo funciona

En Antigravity, haz una pregunta de prueba:

> Usa `buscar_farmacologia` para encontrar información sobre los betabloqueantes.

Deberías ver:

1. Antigravity llama a la herramienta MCP
2. Recibe fragmentos de tus libros
3. Genera una respuesta con citas de libro y página

Si funciona, ¡ya está! **Tiempo total de la primera consulta:** 30-60 segundos
(incluye carga del reranker en RAM). A partir de la segunda, 3-15 segundos.

---

## Siguientes pasos

- Añade reglas a Antigravity: ver `docs/AGENTS.md.example`
- Añade más workspaces según tus materias
- Si algo falla, consulta `docs/TROUBLESHOOTING.md`

---

## Resumen de comandos

Para cuando ya lo tengas todo instalado:

```bash
# Arrancar Ollama (si no está corriendo)
sudo systemctl start ollama

# Abrir AnythingLLM (desde el menú de aplicaciones)

# Reiniciar Antigravity tras cambios
pkill -f antigravity

# Ver el estado de Ollama
systemctl status ollama --no-pager | head -5
```
