#!/usr/bin/env python3
"""
Servidor MCP que expone múltiples workspaces de AnythingLLM como
herramientas independientes para Google Antigravity y otros clientes MCP.

Ollama genera los embeddings durante la indexación en AnythingLLM.
Este servidor consulta AnythingLLM y aplica un reranker multilingüe local.
"""

import asyncio
import os
from dotenv import load_dotenv
import httpx
from mcp.server.fastmcp import FastMCP
from sentence_transformers import CrossEncoder

# Cargar variables de entorno desde .env si existe
load_dotenv()


class AnythingLLMError(Exception):
    """Excepción personalizada para errores de conexión, autenticación o configuración con AnythingLLM."""
    pass


# Detección de dispositivo (GPU / Apple Silicon / CPU)
def _get_device() -> str:
    env_device = os.getenv("RERANKER_DEVICE")
    if env_device:
        return env_device
    try:
        import torch
        if torch.cuda.is_available():
            return "cuda"
        if hasattr(torch.backends, "mps") and torch.backends.mps.is_available():
            return "mps"
    except ImportError:
        pass
    return "cpu"


RERANKER_MODEL = "BAAI/bge-reranker-v2-m3"
reranker = CrossEncoder(RERANKER_MODEL, device=_get_device())

ANYTHINGLLM_URL = os.getenv("ANYTHINGLLM_URL", "http://localhost:3001").rstrip("/")
API_KEY = os.getenv("ANYTHINGLLM_API_KEY", "")

# Slugs de workspaces configurables con valores por defecto
WS_BASICAS = os.getenv("WORKSPACE_BASICAS", "ciencias-basicas")
WS_FISIOLOGIA = os.getenv("WORKSPACE_FISIOLOGIA", "fisiologia")
WS_PATOLOGIA = os.getenv("WORKSPACE_PATOLOGIA", "patologia")
WS_PROPEDEUTICA = os.getenv("WORKSPACE_PROPEDEUTICA", "propedeutica")
WS_FARMACOLOGIA = os.getenv(
    "WORKSPACE_FARMACOLOGIA",
    os.getenv("ANYTHINGLLM_WORKSPACE", "mi-espacio-de-trabajo")
)

mcp = FastMCP("anythingllm-medicina")


async def _buscar(workspace: str, query: str, top_k: int = 8) -> str:
    """
    Busca fragmentos en AnythingLLM y los reordena con el CrossEncoder
    sin bloquear el bucle de eventos.
    """
    initial_fetch = max(top_k * 2, 20)

    try:
        async with httpx.AsyncClient(timeout=30.0) as client:
            resp = await client.post(
                f"{ANYTHINGLLM_URL}/api/v1/workspace/{workspace}/vector-search",
                headers={"Authorization": f"Bearer {API_KEY}"},
                json={
                    "query": query,
                    "topN": initial_fetch,
                    "scoreThreshold": 0.15,
                },
            )
            resp.raise_for_status()
            data = resp.json()
    except httpx.ConnectError:
        raise AnythingLLMError(
            f"No se pudo conectar con AnythingLLM en {ANYTHINGLLM_URL}. "
            "Verifica que AnythingLLM esté abierto y en ejecución."
        )
    except httpx.HTTPStatusError as e:
        if e.response.status_code in (401, 403):
            raise AnythingLLMError("API key de AnythingLLM inválida o sin permisos.")
        if e.response.status_code == 404:
            raise AnythingLLMError(
                f"El workspace '{workspace}' no existe en AnythingLLM. "
                "Revisa los slugs configurados."
            )
        raise AnythingLLMError(
            f"Error en la API de AnythingLLM (código {e.response.status_code}): {e.response.text}"
        )
    except Exception as e:
        raise AnythingLLMError(f"Error inesperado al consultar AnythingLLM: {str(e)}")

    results = data.get("results", [])
    if not results:
        return f"No se encontraron fragmentos relevantes en el workspace '{workspace}'."

    pairs = [(query, chunk.get("text", "")) for chunk in results]

    # Inferencia en hilo secundario para no bloquear el event loop
    scores = await asyncio.to_thread(reranker.predict, pairs)

    ranked = sorted(zip(results, scores), key=lambda x: x[1], reverse=True)
    top_chunks = ranked[:top_k]

    fragmentos = []
    for i, (chunk, score) in enumerate(top_chunks, 1):
        meta = chunk.get("metadata", {})
        titulo = meta.get("title") or meta.get("file_name") or chunk.get("title") or "Sin título"
        pagina = meta.get("page") or meta.get("pageNumber") or "?"
        texto = chunk.get("text", "")
        fragmentos.append(
            f"[{i}] ({titulo}, pág. {pagina}) [relevancia: {score:.3f}]\n{texto}"
        )

    return "\n\n---\n\n".join(fragmentos)


@mcp.tool()
async def buscar_basicas(query: str, top_k: int = 8) -> str:
    """
    Busca en libros de ciencias básicas (bioquímica, histología, anatomía, biología celular).

    Args:
        query: Consulta en lenguaje natural.
        top_k: Número de fragmentos más relevantes a devolver tras el reranking (por defecto 8).
    """
    return await _buscar(WS_BASICAS, query, top_k)


@mcp.tool()
async def buscar_fisiologia(query: str, top_k: int = 8) -> str:
    """
    Busca en libros de fisiología médica (Constanzo, Guyton, Boron).
    Úsalo para entender función normal, mecanismos fisiológicos, homeostasis y regulación.

    Args:
        query: Consulta en lenguaje natural sobre fisiología.
        top_k: Número de fragmentos más relevantes a devolver tras el reranking (por defecto 8).
    """
    return await _buscar(WS_FISIOLOGIA, query, top_k)


@mcp.tool()
async def buscar_patologia(query: str, top_k: int = 8) -> str:
    """
    Busca en libros de patología (Robbins, Kumar, Rubin).
    Úsalo para entender mecanismos de enfermedad, cambios morfológicos y fisiopatología.

    Args:
        query: Consulta en lenguaje natural sobre patología.
        top_k: Número de fragmentos más relevantes a devolver tras el reranking (por defecto 8).
    """
    return await _buscar(WS_PATOLOGIA, query, top_k)


@mcp.tool()
async def buscar_propedeutica(query: str, top_k: int = 8) -> str:
    """
    Busca en libros de propedéutica clínica (Argente-Álvarez, Surós, Bates).
    Úsalo para semiología, técnica de exploración física, signos, síntomas y maniobras.

    Args:
        query: Consulta en lenguaje natural sobre propedéutica.
        top_k: Número de fragmentos más relevantes a devolver tras el reranking (por defecto 8).
    """
    return await _buscar(WS_PROPEDEUTICA, query, top_k)


@mcp.tool()
async def buscar_farmacologia(query: str, top_k: int = 8) -> str:
    """
    Busca en libros de farmacología (Katzung, Goodman, Mendoza).
    Úsalo para mecanismos de acción farmacológica, dosis, interacciones y efectos adversos.

    Args:
        query: Consulta en lenguaje natural sobre farmacología.
        top_k: Número de fragmentos más relevantes a devolver tras el reranking (por defecto 8).
    """
    return await _buscar(WS_FARMACOLOGIA, query, top_k)


if __name__ == "__main__":
    mcp.run(transport="stdio")
