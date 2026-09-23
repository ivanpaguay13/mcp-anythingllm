# Troubleshooting

Errores comunes y sus soluciones. Ordenados por frecuencia de aparición.

Si encuentras un error que no está aquí, abre un issue en GitHub con la
mayor cantidad de contexto posible (mensaje de error completo, sistema
operativo, versiones).

---

## Error: `Workspace X is not a valid workspace`

**Síntoma:** El wrapper MCP no encuentra el workspace.

**Causa:** El slug (identificador interno) no coincide con el nombre visible.
Esto pasa cuando renombras un workspace en AnythingLLM — el slug se genera al
crearlo y **no se actualiza** al renombrar.

**Solución:** Consulta los slugs reales:

```bash
curl -s http://localhost:3001/api/v1/workspaces \
  -H "Authorization: Bearer TU_API_KEY" | python3 -m json.tool
```

Busca el campo `"slug"` de cada workspace. Usa esos valores en `server.py`.

---

## Error: `No embeddings found for this workspace`

**Síntoma:** El endpoint responde correctamente, pero `"results": []`.

**Causa:** El workspace existe pero está vacío, o la indexación no ha
terminado.

**Solución:**

1. Verifica que has subido PDFs al workspace
2. Mira en AnythingLLM si la barra de progreso sigue activa
3. Si crees que ya terminó, espera 5 minutos y vuelve a probar (el último
   chunk puede tardar)
4. Si pasan horas y no termina, revisa que Ollama esté corriendo:
   ```bash
   systemctl status ollama --no-pager | head -5
   ```

---

## Error: `ModuleNotFoundError: No module named 'mcp.server.fastmcp'`

**Síntoma:** El wrapper no arranca. El mensaje menciona que `FastMCP` fue
renombrado a `MCPServer`.

**Causa:** Tienes `mcp` versión 2.x, pero el código espera la v1.x.

**Solución:** Fija la versión:

```bash
cd ~/mcp-anythingllm
uv remove mcp
uv add "mcp[cli]<2"
```

Vuelve a probar:

```bash
uv run python -c "import server; print('OK')"
```

---

## Error: `JSONDecodeError` al arrancar Antigravity

**Síntoma:** Antigravity no carga ningún MCP server.

**Causa:** El archivo `mcp_config.json` tiene un error de sintaxis (coma mal
puesta, llave sin cerrar, comillas sin cerrar).

**Solución:** Verifica el JSON:

```bash
python3 -m json.tool ~/.gemini/config/mcp_config.json
```

Si el comando falla, te dirá la línea exacta del error. Los errores más
comunes:

- Coma extra después del último elemento de un objeto
- Falta una coma entre dos servidores
- Comillas sin cerrar

**Truco:** si el error es difícil de encontrar, copia el contenido y pégalo
en un validador online como [jsonlint.com](https://jsonlint.com/).

---

## Error: `spawn ENOENT` en un MCP server

**Síntoma:** Un MCP server aparece en rojo con `ENOENT: connection closed`.

**Causa:** Antigravity no encuentra el ejecutable (por ejemplo `npx`, `uv`,
`node`). Suele pasar porque Antigravity no hereda el PATH completo de tu shell.

**Solución:** Usa la ruta **absoluta** del ejecutable en `mcp_config.json`.

```bash
which uv
```

Debería devolver algo como `/home/usuario/.local/bin/uv`. Usa esa ruta
completa en el campo `"command"` del JSON:

```json
"command": "/home/usuario/.local/bin/uv"
```

Lo mismo aplica para `npx`, `node`, `python`, etc.

---

## Error: Antigravity no ve el MCP server

**Síntoma:** El panel de MCP servers está vacío o no aparece el tuyo.

**Soluciones, en orden:**

1. Verifica que el JSON es válido (ver arriba)

2. Verifica que `uv` está en el PATH:
   ```bash
   which uv
   ```

3. Verifica que el wrapper arranca manualmente:
   ```bash
   cd ~/mcp-anythingllm && uv run server.py
   ```
   Debería quedarse colgado. `Ctrl+C` para salir.

4. Reinicia Antigravity **completamente**:
   ```bash
   pkill -f antigravity
   ```
   Espera 5 segundos y vuelve a abrirlo.

---

## Problema: La primera consulta tarda 30-60 segundos

**Síntoma:** Antigravity responde, pero la primera consulta es lentísima.

**Causa:** El modelo del reranker (`bge-reranker-v2-m3`, 2.2 GB) se está
cargando en RAM por primera vez.

**Solución:** Es **normal**. A partir de la segunda consulta, baja a 3-15
segundos. Si quieres evitarlo, pre-calentar el modelo antes de usar
Antigravity:

```bash
cd ~/mcp-anythingllm
uv run server.py    # déjalo correr 10 segundos
# Ctrl+C para salir
```

Ollama mantiene modelos en RAM 30 minutos (gracias a `OLLAMA_KEEP_ALIVE=30m`).

---

## Problema: El reranker es muy lento (todas las consultas tardan 15+ segundos)

**Síntoma:** Cada consulta tarda 15-20 segundos o más, incluso después de la
primera.

**Causa:** `bge-reranker-v2-m3` en CPU es lento (~1.5-2 s por consulta).

**Soluciones, en orden de impacto:**

1. **Reduce el `top_n`** en `server.py`:
   - Actualmente: `top_n: int = 20`
   - Prueba: `top_n: int = 10` (mitad de trabajo para el reranker)

2. **Cambia al modelo base** (solo si tus libros son todos en inglés):
   - En `server.py`, cambia:
     ```python
     RERANKER_MODEL = "BAAI/bge-reranker-base"
     ```
   - Pasa de 2.2 GB a 278 MB y de ~1.5 s a ~300 ms
   - Pierde precisión en cross-lingual (consultas en español → libros en inglés)

3. **Instala una GPU NVIDIA** (opcional, ~$180 por una RTX 3060 usada):
   - Reduce el tiempo del reranker de ~1.5 s a ~0.1 s
   - También acelera la indexación ~10×

---

## Problema: El resultado no cita el libro correcto

**Síntoma:** Antigravity menciona fragmentos de un libro distinto al que
pediste.

**Causa:** La búsqueda vectorial no filtra por libro. Recupera los fragmentos
más similares sin importar la fuente.

**Solución:** Sé explícito en el prompt:

> **Según Katzung específicamente**, ¿qué dice sobre los IECA?

Gemini filtrará los fragmentos por título de libro antes de responder.

Si esto no funciona consistentemente, se puede añadir un parámetro `libro`
al wrapper (feature pendiente).

---

## Problema: AnythingLLM no responde en `localhost:3001`

**Síntoma:** Los comandos `curl` fallan con `Connection refused`.

**Causa:** AnythingLLM está cerrado. Es el servidor que responde a las
consultas, y debe estar corriendo siempre que uses el RAG.

**Solución:** Abre AnythingLLM desde el menú de aplicaciones. No lo cierres
mientras uses Antigravity.

**Verifica que responde:**

```bash
curl -s http://localhost:3001/api/v1/workspaces \
  -H "Authorization: Bearer TU_API_KEY" | head -c 200
```

Deberías ver el comienzo de un JSON.

---

## Problema: SELinux bloquea la comunicación (Fedora)

**Síntoma:** Errores `AVC denied` en los logs del sistema.

**Causa:** Fedora tiene SELinux en modo enforcing y puede bloquear procesos
que se comunican por localhost.

**Diagnóstico:**

```bash
sudo ausearch -m avc -ts recent | tail -30
```

Si ves bloqueos específicos del wrapper o de Ollama, puedes añadir una regla
permisiva para el contexto afectado:

```bash
sudo semanage permissive -a CONTEXTO
```

**Nota:** todo el flujo de este proyecto usa `localhost` (no hay red externa),
por lo que SELinux rara vez bloquea. Este problema es más común con Ollama
si usas directorios de modelos personalizados.

---

## Problema: AnythingLLM no arranca en Fedora (AppImage / AppArmor)

**Síntoma:** Al ejecutar `./AnythingLLMDesktop.AppImage`, falla con un error
sobre AppArmor.

**Causa:** Fedora usa SELinux, no AppArmor. El instalador de AnythingLLM
intenta crear una regla de AppArmor que no aplica.

**Solución:** Ignora ese paso del instalador. El AppImage funciona igual
con SELinux en enforcing. Si hay un problema de permisos específico, revisa:

```bash
sudo ausearch -m avc -ts recent | grep anythingllm
```

---

## Problema: La API key aparece en `git status`

**Síntoma:** Al ejecutar `git status`, ves un archivo `.env` o similar con tu
API key real.

**Causa:** El `.gitignore` no está funcionando correctamente.

**Solución urgente:** **Nunca commitees un archivo con API keys reales.** Si
aparece en `git status`, primero verifica:

```bash
cat ~/mcp-anythingllm/.gitignore
```

Debería contener al menos:

```
.env
.env.local
mcp_config.json
```

Si no lo tiene, añádelo con `nano ~/mcp-anythingllm/.gitignore`.

**Si ya commiteaste la key por error:**

1. **Rota la key inmediatamente** en AnythingLLM (Settings → Tools →
   Developer API → Regenerate)
2. Elimina el archivo del historial de git. El commit queda en el historial
   aunque borres el archivo después, así que hay que reescribir la historia.
   La forma más simple:
   ```bash
   git rm --cached archivo-con-la-key
   git commit -m "Remove leaked API key from tracking"
   ```
   Pero esto **no borra el commit anterior del historial de GitHub**. Si el
   repo es público, alguien puede haber visto la key. Rótala.

---

## Problema: El wrapper arranca pero Antigravity dice "tool not found"

**Síntoma:** Antigravity conecta al MCP server, pero cuando intenta usar
`buscar_farmacologia` dice que la herramienta no existe.

**Causa:** Puede ser que el MCP server esté corriendo una versión antigua del
código, o que Antigravity no haya recargado las herramientas.

**Solución:**

1. Reinicia Antigravity completamente:
   ```bash
   pkill -f antigravity
   ```

2. Vuelve a abrirlo y espera 10 segundos antes de hacer una consulta.

3. Verifica que las herramientas aparecen en el panel de MCP servers.

---

## Problema: La respuesta de Antigravity es genérica (no cita libros)

**Síntoma:** Antigravity responde sobre medicina pero sin citar libros
específicos ni páginas.

**Causa:** Puede que no esté usando las herramientas MCP, o que esté
respondiendo de memoria.

**Solución:**

1. Verifica que el `AGENTS.md` tiene las reglas correctas (ver
   `docs/AGENTS.md.example`)

2. Sé explícito en el prompt:
   > **Consulta mis libros** sobre los betabloqueantes y cita el libro y
   > la página.

3. Verifica que el wrapper recibe las consultas. En otra terminal:
   ```bash
   tail -f ~/.config/anythingllm-desktop/storage/logs/anythingllm.log
   ```
   Deberías ver líneas como `POST /api/v1/workspace/.../vector-search`.

---

## Cómo pedir ayuda

Si encuentras un error que no está aquí:

1. Ejecuta los comandos en **modo verbose** si es posible
2. Captura el **mensaje completo** (no solo la primera línea)
3. Incluye tu **distribución** y **versión de las herramientas**:
   ```bash
   cat /etc/os-release | head -1
   ollama --version
   uv --version
   python3 --version
   ```
4. Abre un issue en GitHub con todo lo anterior:
   https://github.com/ivanpaguay13/mcp-anythingllm/issues

---

## Ver también

- [docs/INSTALL.md](INSTALL.md) — guía de instalación completa
- [README.md](../README.md) — descripción general del proyecto
