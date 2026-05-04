"""Ingest knowledge base markdown files into ChromaDB.

Run once after starting the container:
    python scripts/ingest_kb.py
"""
import sys
from pathlib import Path

# Add backend/ to path
sys.path.insert(0, str(Path(__file__).parent.parent))

from app.tools.rag_tools import ingest_documents

KB_DIR = Path(__file__).parent.parent / "data" / "knowledge_base"


def main():
    print(f"Ingesting documents from: {KB_DIR}")
    if not KB_DIR.exists():
        print(f"ERROR: Directory not found: {KB_DIR}")
        sys.exit(1)

    files = list(KB_DIR.glob("*.md")) + list(KB_DIR.glob("*.txt"))
    if not files:
        print("ERROR: No .md or .txt files found")
        sys.exit(1)

    print(f"Found {len(files)} file(s):")
    for f in files:
        print(f"  - {f.name}")

    chunks = ingest_documents(str(KB_DIR))
    print(f"\n✓ Ingested {chunks} chunks into ChromaDB")


if __name__ == "__main__":
    main()
