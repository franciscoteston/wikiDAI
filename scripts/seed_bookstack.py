#!/usr/bin/env python3
import json
import os
import sys
import urllib.parse
import urllib.request


def api_request(method, path, payload=None, query=None):
    base = os.environ.get("APP_URL", "http://localhost:7860").rstrip("/")
    token_id = os.environ["BOOKSTACK_API_TOKEN_ID"]
    token_secret = os.environ["BOOKSTACK_API_TOKEN_SECRET"]

    url = f"{base}/api/{path.lstrip('/')}"
    if query:
        url += "?" + urllib.parse.urlencode(query)

    data = None
    headers = {
        "Authorization": f"Token {token_id}:{token_secret}",
        "Content-Type": "application/json",
    }

    if payload is not None:
        data = json.dumps(payload).encode("utf-8")

    req = urllib.request.Request(url, data=data, headers=headers, method=method)
    with urllib.request.urlopen(req) as response:
        return json.loads(response.read().decode("utf-8"))


def find_by_name(path, name, parent_key=None, parent_value=None):
    offset = 0
    while True:
        query = {"count": 100, "offset": offset}
        result = api_request("GET", path, query=query)
        items = result.get("data", [])
        for item in items:
            if item.get("name") != name:
                continue
            if parent_key and item.get(parent_key) != parent_value:
                continue
            return item
        if len(items) < 100:
            return None
        offset += 100


def ensure_book(name, description):
    existing = find_by_name("books", name)
    payload = {"name": name, "description": description}
    if existing:
        return api_request("PUT", f"books/{existing['id']}", payload)
    return api_request("POST", "books", payload)


def ensure_chapter(book_id, name):
    existing = find_by_name("chapters", name, "book_id", book_id)
    payload = {"name": name, "book_id": book_id}
    if existing:
        return api_request("PUT", f"chapters/{existing['id']}", payload)
    return api_request("POST", "chapters", payload)


def ensure_page(book_id, chapter_id, name, markdown):
    existing = find_by_name("pages", name, "chapter_id", chapter_id)
    payload = {
        "name": name,
        "book_id": book_id,
        "chapter_id": chapter_id,
        "markdown": markdown,
    }
    if existing:
        return api_request("PUT", f"pages/{existing['id']}", payload)
    return api_request("POST", "pages", payload)


def main(seed_file):
    with open(seed_file, "r", encoding="utf-8") as handle:
        seed = json.load(handle)

    book = ensure_book(seed["book"]["name"], seed["book"]["description"])
    book_id = book["id"]

    for chapter in seed["chapters"]:
        ch = ensure_chapter(book_id, chapter["name"])
        for page in chapter["pages"]:
            ensure_page(book_id, ch["id"], page["name"], page["markdown"])

    print("Seed concluído com sucesso.")


if __name__ == "__main__":
    if len(sys.argv) != 2:
        print("Uso: seed_bookstack.py <arquivo_seed.json>")
        raise SystemExit(1)
    main(sys.argv[1])
