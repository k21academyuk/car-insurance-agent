"""RAG tool — searches the policy/IRDAI knowledge base in ChromaDB."""
import os
from pathlib import Path

from langchain_core.tools import tool
from langchain_openai import OpenAIEmbeddings
from pydantic import BaseModel, Field
import chromadb
from chromadb.config import Settings


# Lazy-init the Chroma client once
_chroma_client = None
_collection = None
_embeddings = None


def _get_collection():
    global _chroma_client, _collection, _embeddings
    if _collection is not None:
        return _collection

    persist_dir = os.getenv("CHROMA_PERSIST_DIR", "/app/chroma_db")
    Path(persist_dir).mkdir(parents=True, exist_ok=True)

    _chroma_client = chromadb.PersistentClient(
        path=persist_dir, settings=Settings(anonymized_telemetry=False)
    )
    _embeddings = OpenAIEmbeddings(model="text-embedding-3-small")
    _collection = _chroma_client.get_or_create_collection(name="insurance_kb")
    return _collection


def ingest_documents(docs_dir: str) -> int:
    """Ingest .md/.txt files from a directory into ChromaDB.

    Returns number of chunks indexed. Idempotent — safe to re-run.
    """
    collection = _get_collection()
    embeddings = _embeddings

    # Clear any prior content
    existing = collection.count()
    if existing > 0:
        all_ids = collection.get()["ids"]
        if all_ids:
            collection.delete(ids=all_ids)

    docs_path = Path(docs_dir)
    chunk_id = 0
    chunks_to_add = []
    metadatas = []
    ids = []

    for f in sorted(docs_path.glob("*.md")) + sorted(docs_path.glob("*.txt")):
        text = f.read_text(encoding="utf-8")
        # Simple chunking: split by ## headers, fallback to fixed size
        sections = [s.strip() for s in text.split("\n## ") if s.strip()]
        for section in sections:
            # Further split if section > 1500 chars
            if len(section) <= 1500:
                chunks_to_add.append(section)
                metadatas.append({"source": f.name})
                ids.append(f"chunk_{chunk_id}")
                chunk_id += 1
            else:
                for i in range(0, len(section), 1200):
                    chunks_to_add.append(section[i:i + 1200])
                    metadatas.append({"source": f.name})
                    ids.append(f"chunk_{chunk_id}")
                    chunk_id += 1

    if not chunks_to_add:
        return 0

    # Embed all at once (cheaper than one-by-one)
    vectors = embeddings.embed_documents(chunks_to_add)
    collection.add(
        documents=chunks_to_add,
        embeddings=vectors,
        metadatas=metadatas,
        ids=ids,
    )
    return len(chunks_to_add)


class KBSearchInput(BaseModel):
    query: str = Field(description="Question or topic to search the policy knowledge base for")
    top_k: int = Field(default=4, description="Number of relevant chunks to retrieve")


@tool("policy_kb_search", args_schema=KBSearchInput)
def policy_kb_search_tool(query: str, top_k: int = 4) -> dict:
    """Search the insurance policy and IRDAI regulations knowledge base.

    Use this for any policy-related question: coverage, exclusions, NCB rules,
    claim process, IRDAI guidelines, etc.
    """
    collection = _get_collection()
    embeddings = _embeddings

    if collection.count() == 0:
        return {
            "results": [],
            "note": "Knowledge base is empty. Run scripts/ingest_kb.py first.",
        }

    query_vec = embeddings.embed_query(query)
    results = collection.query(query_embeddings=[query_vec], n_results=top_k)

    chunks = []
    for doc, meta in zip(results["documents"][0], results["metadatas"][0]):
        chunks.append({"content": doc, "source": meta.get("source", "unknown")})

    return {"query": query, "results": chunks}


RAG_TOOLS = [policy_kb_search_tool]
