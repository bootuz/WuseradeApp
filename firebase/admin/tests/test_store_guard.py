"""The chunk size guard needs no emulator."""

import json

import pytest

from wuserade_admin import store


def entry(n: int, title: str = "t") -> dict:
    return {"id": n, "title": title, "authorId": 1, "authorName": "A", "themeId": None, "createdAt": None}


def encoded_size(chunk: list[dict]) -> int:
    return len(json.dumps(chunk, ensure_ascii=False, default=str).encode())


def test_chunks_under_the_limit_pass():
    chunks = [[entry(n) for n in range(10)], [entry(n) for n in range(10, 15)]]

    store.check_chunk_sizes(chunks)


def test_oversized_chunk_is_named_by_index():
    big = [entry(n, title="x" * 1000) for n in range(1000)]
    chunks = [[entry(1)], big, [entry(2)]]
    assert encoded_size(big) >= 900_000

    with pytest.raises(store.ChunkTooLargeError) as caught:
        store.check_chunk_sizes(chunks)

    message = str(caught.value)
    assert "chunk 1" in message
    assert "CHUNK_SIZE" in message
    assert isinstance(caught.value, ValueError)


def test_limit_is_900_000_bytes_and_measured_in_utf8():
    assert store.MAX_CHUNK_BYTES == 900_000
    # Kabardian letters take two bytes each, so the byte count must not be the character count.
    cyrillic = [entry(n, title="Ӏ" * 700) for n in range(700)]
    assert len(json.dumps(cyrillic, ensure_ascii=False)) < 900_000 <= encoded_size(cyrillic)

    with pytest.raises(store.ChunkTooLargeError, match="chunk 0"):
        store.check_chunk_sizes([cyrillic])


def test_limit_can_be_given_explicitly():
    chunks = [[entry(n) for n in range(100)]]

    with pytest.raises(store.ChunkTooLargeError, match="chunk 0"):
        store.check_chunk_sizes(chunks, limit=1_000)
