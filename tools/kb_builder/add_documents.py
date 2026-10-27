"""Appends documents to an existing law_index.json without rebuilding it.

For filling gaps in the bundled index from a few official texts, when the full
source corpus is not at hand. Each document is cleaned and split by article
exactly as build_law_index.py does, and gets the next free LAW-#### id.

    python3 tools/kb_builder/add_documents.py \
      --index harmony-app/entry/src/main/resources/rawfile/law_index.json \
      --manifest tools/kb_builder/supplements.json --source-dir ~/Downloads

The manifest lists, for each file, the title, category, status and effective
date to record; nothing is inferred from the text. Documents whose title is
already in the index are skipped, so running it twice changes nothing.
"""
from __future__ import annotations

import argparse
import json
import re
from datetime import datetime, timezone
from pathlib import Path

from build_law_index import LawDocument, build_chunks, normalize_text


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--index", type=Path, required=True)
    parser.add_argument("--manifest", type=Path, required=True)
    parser.add_argument("--source-dir", type=Path, required=True)
    parser.add_argument("--max-chars", type=int, default=1200)
    parser.add_argument("--overlap-chars", type=int, default=120)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    index = json.loads(args.index.read_text(encoding="utf-8"))
    manifest = json.loads(args.manifest.read_text(encoding="utf-8"))
    titles = {document["title"] for document in index["documents"]}
    next_number = 1 + max(int(d["documentId"].split("-")[1]) for d in index["documents"])
    added = 0
    for entry in manifest["documents"]:
        if entry["title"] in titles:
            print(f"[SKIP] {entry['title']} is already in the index")
            continue
        path = args.source_dir / entry["file"]
        text = normalize_text(path.read_text(encoding="utf-8"), entry["title"])
        if len(text.strip()) < 40:
            raise ValueError(f"{entry['file']}: extracted text is empty or too short")
        document = LawDocument(
            documentId=f"LAW-{next_number:04d}",
            title=entry["title"],
            category=entry["category"],
            subcategory=entry.get("subcategory", ""),
            region="全国",
            source=entry["file"],
            sourcePath=entry["file"],
            fileFormat="TXT",
            extractionStatus="正文已提取",
            extractionNote="",
            status=entry["status"],
            effectiveDate=entry.get("effectiveDate", ""),
            pageCount=1,
            contentHash="",
        )
        chunks = build_chunks(document, text, args.max_chars, args.overlap_chars)
        index["documents"].append({
            "documentId": document.documentId,
            "title": document.title,
            "category": document.category,
            "subcategory": document.subcategory,
            "region": document.region,
            "source": document.source,
            "status": document.status,
            "effectiveDate": document.effectiveDate,
        })
        index["chunks"].extend(
            {"id": c.id, "documentId": c.documentId, "article": c.article, "text": c.text}
            for c in chunks
        )
        print(f"[ADD] {document.documentId} {document.title}: {len(chunks)} chunks")
        titles.add(entry["title"])
        next_number += 1
        added += 1
    if added == 0:
        return 0
    index["documentCount"] = len(index["documents"])
    index["searchableDocumentCount"] = index.get("searchableDocumentCount", 0) + added
    index["sourceFileCount"] = index.get("sourceFileCount", 0) + added
    index["chunkCount"] = len(index["chunks"])
    index["generatedAt"] = datetime.now(timezone.utc).isoformat()
    args.index.write_text(
        json.dumps(index, ensure_ascii=False, separators=(",", ":")), encoding="utf-8"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
