#!/usr/bin/env python3
"""
Servidor MCP que expone multiples workspaces de AnythingLLM como
herramientas independientes para Google Antigravity.

Ollama NO se usa aqui. Solo se llama al endpoint de busqueda vectorial
de AnythingLLM, que devuelve fragmentos crudos con citas (libro + pagina).
"""

import os
import httpx
from mcp.server.fastmcp import FastMCP
from sentence_transformers import CrossEncoder

# Reranker para mejorar la relevancia de los fragmentos
RERANKER_MODEL = "BAAI/bge-reranker-v2-m3"
reranker = CrossEncoder(RERANKER_MODEL, device="cpu")

ANYTHINGLLM_URL = os.getenv("ANYTHINGLLM_URL", "http://localhost:3001")
API_KEY = os.getenv("ANYTHINGLLM_API_KEY", "")

mcp = FastMCP("anythingllm-medicina")


async def _buscar(workspace: str, query: str, top_n: int = 20) -> str:
    """
    Busca fragmentos en AnythingLLM y los reordena con un cross-encoder
    para mejorar la precisión antes de devolverlos a Antigravity.
    """
    async with httpx.AsyncClient(timeout=30.0) as client:
        resp = await client.post(
            f"{ANYTHINGLLM_URL}/api/v1/workspace/{workspace}/vector-search",
            headers={"Authorization": f"Bearer {API_KEY}"},
            json={
                "query": query,
                "topN": top_n,          # Pedimos más fragmentos de los que necesitamos
                "scoreThreshold": 0.15, # Umbral bajo para no perder nada en la primera etapa
            },
        )
        resp.raise_for_status()
        data = resp.json()

    results = data.get("results", [])
    if not results:
        return f"No se encontraron fragmentos relevantes en {workspace}."

    # Preparar pares (query, texto) para el reranker
    pairs = [(query, chunk.get("text", "")) for chunk in results]

    # Obtener scores del reranker
    scores = reranker.predict(pairs)

    # Reordenar los fragmentos por score (descendente)
    ranked = sorted(zip(results, scores), key=lambda x: x[1], reverse=True)

    # Quedarnos con los 5 mejores
    top_chunks = ranked[:8]

    fragmentos = []
    for i, (chunk, score) in enumerate(top_chunks, 1):
        meta = chunk.get("metadata", {})
        titulo = meta.get("title", "Sin titulo")
        pagina = meta.get("page", "?")
        texto = chunk.get("text", "")
        fragmentos.append(
            f"[{i}] ({titulo}, pag. {pagina}) [relevancia: {score:.3f}]\n{texto}"
        )

    return "\n\n---\n\n".join(fragmentos)


@mcp.tool()
async def buscar_basicas(query: str, top_n: int = 20) -> str:
    """
    Busca en libros de ciencias basicas (bioquimica, histologia,
    anatomia, biologia celular).

    Args:
        query: Consulta en lenguaje natural.
        top_n: Numero de fragmentos a devolver (por defecto 6).
    """
    return await _buscar("ciencias-basicas", query, top_n)


@mcp.tool()
async def buscar_fisiologia(query: str, top_n: int = 20) -> str:
    """
    Busca en libros de fisiologia medica (Constanzo, Guyton, Boron).
    Usalo para entender funcion normal, mecanismos fisiologicos,
    homeostasis, regulacion endocrina y cardiovascular.

    Args:
        query: Consulta en lenguaje natural sobre fisiologia.
        top_n: Numero de fragmentos a devolver (por defecto 6).
    """
    return await _buscar("fisiologia", query, top_n)


@mcp.tool()
async def buscar_patologia(query: str, top_n: int = 20) -> str:
    """
    Busca en libros de patologia (Robbins, Kumar, Rubin).
    Usalo para entender mecanismos de enfermedad, cambios morfologicos,
    fisiopatologia, inflamacion y neoplasias.

    Args:
        query: Consulta en lenguaje natural sobre patologia.
        top_n: Numero de fragmentos a devolver (por defecto 6).
    """
    return await _buscar("patologia", query, top_n)

@mcp.tool()
async def buscar_propedeutica(query: str, top_n: int = 20) -> str:
    """
    Busca en libros de propedeutica clinica (Argente-Alvarez, Surós,
    Bates). Usalo para semiologia, tecnica de exploracion fisica,
    reconocimiento de signos y sintomas, maniobras exploratorias y
    hallazgos al examen fisico.

    Args:
        query: Consulta en lenguaje natural sobre propedeutica.
        top_n: Numero de fragmentos a devolver (por defecto 10).
    """
    return await _buscar("propedeutica", query, top_n)

@mcp.tool()
async def buscar_farmacologia(query: str, top_n: int = 20) -> str:
    """
    Busca en libros de farmacologia (Katzung, Goodman, Mendoza).
    Usalo para mecanismos de accion farmacologica, dosis, interacciones,
    contraindicaciones, farmacocinetica y efectos adversos.

    Args:
        query: Consulta en lenguaje natural sobre farmacologia.
        top_n: Numero de fragmentos a devolver (por defecto 6).
    """
    return await _buscar("mi-espacio-de-trabajo", query, top_n)


if __name__ == "__main__":
    mcp.run(transport="stdio")
