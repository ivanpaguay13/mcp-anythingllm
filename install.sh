#!/usr/bin/env bash
# install.sh - Instalador de MCP AnythingLLM
# Copyright (C) 2026 Ivan Paguay
# Licencia: AGPL-3.0-or-later
#
# Uso:
#   ./install.sh              Fase 1 - Instala todo lo automatizable
#   ./install.sh --configure  Fase 2 - Configura Antigravity (requiere API key)

set -euo pipefail

# ============================================================
# CONFIGURACIÓN
# ============================================================
readonly REPO_URL="https://github.com/ivanpaguay13/mcp-anythingllm.git"
readonly INSTALL_DIR="${HOME}/mcp-anythingllm"
readonly CONFIG_DIR="${HOME}/.gemini/config"
readonly CONFIG_FILE="${CONFIG_DIR}/mcp_config.json"

# Colores con ANSI-C quoting (garantiza el byte ESC)
readonly GREEN=$'\033[0;32m'
readonly YELLOW=$'\033[1;33m'
readonly RED=$'\033[0;31m'
readonly BLUE=$'\033[0;34m'
readonly BOLD=$'\033[1m'
readonly NC=$'\033[0m'

log()    { printf "%s[INFO]%s  %s\n" "$GREEN" "$NC" "$*"; }
warn()   { printf "%s[WARN]%s  %s\n" "$YELLOW" "$NC" "$*"; }
error()  { printf "%s[ERROR]%s %s\n" "$RED" "$NC" "$*" >&2; exit 1; }
header() { printf "\n%s==>%s %s%s%s\n" "$BLUE" "$NC" "$BOLD" "$*" "$NC"; }

# ============================================================
# DETECCIÓN DE SISTEMA
# ============================================================
detect_os() {
    if [[ "$(uname -s)" == "Darwin" ]]; then
        echo "macos"
        return
    fi
    if [[ -f /etc/os-release ]]; then
        source /etc/os-release
        case "${ID}" in
            fedora|rhel|centos) echo "fedora" ;;
            ubuntu|debian|linuxmint|pop) echo "debian" ;;
            arch|manjaro|endeavouros) echo "arch" ;;
            *) echo "unknown" ;;
        esac
    else
        echo "unknown"
    fi
}

# ============================================================
# FASE 2 - CONFIGURAR ANTIGRAVITY
# ============================================================
configure_antigravity() {
    header "Configurando Antigravity MCP"

    if [[ ! -d "$INSTALL_DIR" ]]; then
        error "No se encontró $INSTALL_DIR. Ejecuta primero la Fase 1: ./install.sh"
    fi

    if [[ ! -f "$INSTALL_DIR/server.py" ]]; then
        error "No se encontró $INSTALL_DIR/server.py. Ejecuta primero la Fase 1."
    fi

    if ! command -v ollama &>/dev/null; then
        error "Ollama no está instalado. Ejecuta primero la Fase 1."
    fi

    echo ""
    echo "Antes de continuar, asegúrate de tener:"
    echo "  1. AnythingLLM instalado y corriendo"
    echo "  2. Al menos un workspace creado"
    echo "  3. Tu API key a mano (Settings -> Tools -> Developer API)"
    echo ""
    read -rp "¿Continuar? [y/N]: " response
    if [[ ! "$response" =~ ^[Yy]$ ]]; then
        error "Configuración cancelada"
    fi

    echo ""
    read -rsp "Introduce tu API key de AnythingLLM: " api_key
    echo ""
    [[ -z "$api_key" ]] && error "La API key no puede estar vacía"

    local uv_path="${HOME}/.local/bin/uv"
    if [[ ! -x "$uv_path" ]]; then
        uv_path="$(command -v uv 2>/dev/null || echo "$uv_path")"
    fi

    mkdir -p "$CONFIG_DIR"

    if [[ -f "$CONFIG_FILE" ]]; then
        local backup="${CONFIG_FILE}.backup.$(date +%Y%m%d-%H%M%S)"
        warn "Ya existe $CONFIG_FILE"
        warn "Guardando backup en: $backup"
        cp "$CONFIG_FILE" "$backup"
    fi

    cat > "$CONFIG_FILE" <<EOF
{
  "mcpServers": {
    "medicina-rag": {
      "command": "$uv_path",
      "args": [
        "run",
        "--directory",
        "$INSTALL_DIR",
        "server.py"
      ],
      "env": {
        "ANYTHINGLLM_URL": "http://localhost:3001",
        "ANYTHINGLLM_API_KEY": "$api_key"
      }
    }
  }
}
EOF
    chmod 600 "$CONFIG_FILE"
    log "Configuración escrita en $CONFIG_FILE"

    header "Verificando configuración"

    cd "$INSTALL_DIR"

    if "$uv_path" run python -c "import server; print('OK')" > /dev/null 2>&1; then
        log "El wrapper compila correctamente"
    else
        error "El wrapper no compila. Ejecuta: cd $INSTALL_DIR && uv run python -c 'import server'"
    fi

    if python3 -m json.tool "$CONFIG_FILE" > /dev/null 2>&1; then
        log "mcp_config.json es JSON válido"
    else
        error "mcp_config.json tiene un error de sintaxis"
    fi

    printf "\n"
    printf "%s%s%s\n" "$GREEN" "════════════════════════════════════════════════════════════" "$NC"
    printf "%s  Configuración completada%s\n" "$GREEN" "$NC"
    printf "%s%s%s\n" "$GREEN" "════════════════════════════════════════════════════════════" "$NC"
    printf "\n"
    printf "Último paso: reinicia Antigravity para cargar el MCP\n"
    printf "\n"
    printf "  %spkill -f antigravity%s\n" "$YELLOW" "$NC"
    printf "\n"
}

# ============================================================
# INSTALAR DEPENDENCIAS DEL SISTEMA
# ============================================================
install_system_deps() {
    local os="$1"
    header "Instalando dependencias del sistema (git, curl, python3)"

    case "$os" in
        fedora)
            sudo dnf install -y git curl python3
            ;;
        debian)
            sudo apt update
            sudo apt install -y git curl python3
            ;;
        arch)
            sudo pacman -S --noconfirm git curl python
            ;;
        macos)
            if ! command -v brew &>/dev/null; then
                error "Homebrew no está instalado. Instálalo desde https://brew.sh"
            fi
            brew install git curl python
            ;;
        *)
            error "Distribución no soportada."
            ;;
    esac
}

# ============================================================
# INSTALAR OLLAMA
# ============================================================
install_ollama() {
    local os="$1"
    header "Instalando Ollama"

    if command -v ollama &>/dev/null; then
        log "Ollama ya está instalado ($(ollama --version 2>/dev/null | head -1))"
        return
    fi

    if [[ "$os" == "macos" ]]; then
        brew install ollama
    else
        curl -fsSL https://ollama.com/install.sh | sh
    fi
}

# ============================================================
# CONFIGURAR VARIABLES DE OLLAMA
# ============================================================
configure_ollama() {
    local os="$1"
    header "Configurando variables de Ollama"

    if [[ "$os" == "macos" ]]; then
        local zshrc="${HOME}/.zshrc"
        touch "$zshrc"
        for var in \
            'export OLLAMA_NUM_PARALLEL=1' \
            'export OLLAMA_MAX_LOADED_MODELS=1' \
            'export OLLAMA_KEEP_ALIVE=30m'; do
            if ! grep -qF "$var" "$zshrc"; then
                echo "$var" >> "$zshrc"
            fi
        done
        log "Variables añadidas a $zshrc"
    else
        local override_dir="/etc/systemd/system/ollama.service.d"
        local override_file="${override_dir}/override.conf"

        sudo mkdir -p "$override_dir"
        sudo tee "$override_file" > /dev/null <<'EOF'
[Service]
Environment="OLLAMA_NUM_PARALLEL=1"
Environment="OLLAMA_MAX_LOADED_MODELS=1"
Environment="OLLAMA_KEEP_ALIVE=30m"
EOF
        sudo systemctl daemon-reload
        sudo systemctl restart ollama
    fi
}

# ============================================================
# DESCARGAR MODELO DE EMBEDDINGS
# ============================================================
pull_embedder() {
    header "Descargando modelo de embeddings (bge-m3, ~1.2 GB)"

    if ollama list 2>/dev/null | grep -q "bge-m3"; then
        log "bge-m3 ya está descargado"
        return
    fi

    ollama pull bge-m3
}

# ============================================================
# INSTALAR UV
# ============================================================
install_uv() {
    header "Instalando uv (gestor de paquetes Python)"

    if command -v uv &>/dev/null; then
        log "uv ya está instalado ($(uv --version))"
        return
    fi

    curl -LsSf https://astral.sh/uv/install.sh | sh
    export PATH="${HOME}/.local/bin:${PATH}"
    log "uv instalado en ~/.local/bin/uv"
}

# ============================================================
# CLONAR O ACTUALIZAR EL REPO
# ============================================================
setup_repo() {
    header "Configurando repositorio"

    if [[ -d "$INSTALL_DIR/.git" ]]; then
        log "Repositorio ya existe. Actualizando..."
        git -C "$INSTALL_DIR" pull --ff-only || warn "git pull falló, continuando con la versión actual"
    elif [[ -d "$INSTALL_DIR" ]]; then
        warn "El directorio $INSTALL_DIR existe pero no es un repo git"
    else
        log "Clonando $REPO_URL"
        git clone "$REPO_URL" "$INSTALL_DIR"
    fi
}

# ============================================================
# INSTALAR DEPENDENCIAS PYTHON
# ============================================================
install_python_deps() {
    header "Instalando dependencias Python (uv sync)"

    if [[ ! -f "$INSTALL_DIR/pyproject.toml" ]]; then
        error "No se encontró pyproject.toml en $INSTALL_DIR"
    fi

    cd "$INSTALL_DIR"
    "${HOME}/.local/bin/uv" sync
}

# ============================================================
# DESCARGAR RERANKER
# ============================================================
download_reranker() {
    header "Descargando modelo del reranker (~2.2 GB, solo la primera vez)"

    cd "$INSTALL_DIR"
    "${HOME}/.local/bin/uv" run python -c "
from sentence_transformers import CrossEncoder
CrossEncoder('BAAI/bge-reranker-v2-m3', device='cpu')
print('Reranker descargado y listo')
"
}

# ============================================================
# RESUMEN FASE 1
# ============================================================
final_summary_phase1() {
    printf "\n"
    printf "%s%s%s\n" "$GREEN" "════════════════════════════════════════════════════════════" "$NC"
    printf "%s  %sFase 1 completada%s - Componentes instalados%s\n" "$GREEN" "$BOLD" "$NC" "$NC"
    printf "%s%s%s\n" "$GREEN" "════════════════════════════════════════════════════════════" "$NC"
    printf "\n"
    printf "Se instaló:\n"
    printf "  - Ollama con el modelo bge-m3\n"
    printf "  - uv y las dependencias Python del wrapper\n"
    printf "  - El repositorio en ~/mcp-anythingllm\n"
    printf "  - El modelo del reranker (bge-reranker-v2-m3)\n"
    printf "\n"
    printf "%s%sPasos manuales que faltan:%s\n" "$YELLOW" "$BOLD" "$NC"
    printf "\n"
    printf "%sPASO 1 - Instalar AnythingLLM%s\n" "$BOLD" "$NC"
    printf "  Descarga desde https://anythingllm.com/ e instálalo.\n"
    printf "  En Fedora, el instalador oficial crea un AppImage o similar.\n"
    printf "\n"
    printf "%sPASO 2 - Configurar el embedder en AnythingLLM%s\n" "$BOLD" "$NC"
    printf "  Settings -> Proveedores de IA -> Incrustador (Embedder)\n"
    printf "    - Proveedor: Ollama\n"
    printf "    - Modelo: bge-m3:latest\n"
    printf "    - Max embedding chunk length: 1024\n"
    printf "\n"
    printf "%sPASO 3 - Crear workspaces%s\n" "$BOLD" "$NC"
    printf "  Uno por dominio (farmacologia, fisiologia, patologia...)\n"
    printf "  Nombres sin tildes para que el slug sea limpio.\n"
    printf "\n"
    printf "%sPASO 4 - Subir tus PDFs (opcional pero recomendado)%s\n" "$BOLD" "$NC"
    printf "  15-30 min por libro de 1.000 paginas en CPU.\n"
    printf "\n"
    printf "%sPASO 5 - Obtener la API key%s\n" "$BOLD" "$NC"
    printf "  En AnythingLLM: Settings -> Tools -> Developer API\n"
    printf "  Clic en Generate API Key y copiala.\n"
    printf "\n"
    printf "%sPASO 6 - Actualizar server.py con tus slugs reales%s\n" "$BOLD" "$NC"
    printf "  Edita ~/mcp-anythingllm/server.py y sustituye los slugs\n"
    printf "  por los que devuelva:\n"
    printf "    curl -s http://localhost:3001/api/v1/workspaces \\\\\n"
    printf "      -H \"Authorization: Bearer TU_API_KEY\" | python3 -m json.tool\n"
    printf "\n"
    printf "%sPASO 7 - Ejecutar la Fase 2%s\n" "$BOLD" "$NC"
    printf "  Cuando tengas la API key a mano:\n"
    printf "\n"
    printf "    %scd ~/mcp-anythingllm && ./install.sh --configure%s\n" "$YELLOW" "$NC"
    printf "\n"
    printf "%sPASO 8 - Reiniciar Antigravity%s\n" "$BOLD" "$NC"
    printf "\n"
    printf "    %spkill -f antigravity%s\n" "$YELLOW" "$NC"
    printf "\n"
    printf "Documentación completa:\n"
    printf "  - Guía:      ~/mcp-anythingllm/docs/INSTALL.md\n"
    printf "  - Problemas: ~/mcp-anythingllm/docs/TROUBLESHOOTING.md\n"
    printf "  - Reglas:    ~/mcp-anythingllm/docs/AGENTS.md.example\n"
    printf "\n"
}

# ============================================================
# MAIN
# ============================================================
main() {
    # Fase 2
    if [[ "${1:-}" == "--configure" ]]; then
        log "Instalador de MCP AnythingLLM - Fase 2 (configuración)"
        configure_antigravity
        exit 0
    fi

    # Ayuda
    if [[ "${1:-}" == "--help" ]] || [[ "${1:-}" == "-h" ]]; then
        cat <<'EOF'
Instalador de MCP AnythingLLM

Uso:
  ./install.sh              Fase 1: instala todo lo automatizable
  ./install.sh --configure  Fase 2: configura Antigravity (requiere API key)
  ./install.sh --help       Muestra esta ayuda

Flujo de instalación:
  1. Ejecuta ./install.sh para instalar todos los componentes
  2. Sigue los pasos manuales que se muestran al final
  3. Cuando tengas AnythingLLM configurado y tu API key, ejecuta:
       ./install.sh --configure
EOF
        exit 0
    fi

    # Fase 1
    printf "\n"
    log "Instalador de MCP AnythingLLM - Fase 1 (instalación)"

    local os
    os="$(detect_os)"
    log "Sistema operativo detectado: $os"

    if [[ "$os" == "unknown" ]]; then
        error "No se pudo detectar el sistema operativo"
    fi

    install_system_deps "$os"
    install_ollama "$os"
    configure_ollama "$os"
    pull_embedder
    install_uv
    setup_repo
    install_python_deps
    download_reranker
    final_summary_phase1
}

main "$@"
