"""ارائه‌دهنده‌ی بردار.

انتخاب مدل تعبیه‌سازی هنوز انجام نشده و باید با اندازه‌گیری روی فارسی انجام شود، نه با
شهرت مدل. تا آن موقع، این پروتکل جای مدل واقعی را نگه می‌دارد و خط لوله و ارزیابی
مستقل از انتخاب ساخته می‌شوند.

توجه: Anthropic مدل تعبیه‌سازی ارائه نمی‌دهد؛ این یک تصمیم جدا با ارائه‌دهنده‌ی جداست.
"""

from __future__ import annotations

import hashlib
import math
from typing import Protocol, runtime_checkable

EMBEDDING_DIM = 1024


@runtime_checkable
class EmbeddingProvider(Protocol):
    model: str
    dimensions: int

    async def embed(self, texts: list[str]) -> list[list[float]]: ...


class HashingEmbedder:
    """بردارساز قطعی برای تست، بدون شبکه.

    **این مدل واقعی نیست و نباید در محیط تولید استفاده شود.** شباهت معنایی نمی‌دهد؛
    فقط هم‌پوشانی واژگانی را به فضای برداری می‌برد. برای آزمودن لوله‌کشی بازیابی و
    ترکیب رتبه‌ها کافی است و باعث می‌شود تست‌ها به هیچ سرویس بیرونی وابسته نباشند.
    """

    model = "hashing-test-only"

    def __init__(self, dimensions: int = EMBEDDING_DIM) -> None:
        self.dimensions = dimensions

    def _vector(self, text: str) -> list[float]:
        vec = [0.0] * self.dimensions
        for token in text.split():
            digest = hashlib.blake2b(token.encode("utf-8"), digest_size=8).digest()
            index = int.from_bytes(digest[:4], "big") % self.dimensions
            sign = 1.0 if digest[4] % 2 == 0 else -1.0
            vec[index] += sign
        norm = math.sqrt(sum(v * v for v in vec))
        if norm == 0.0:
            # بردار صفر در شباهت کسینوسی تعریف‌نشده است؛ یک جهت ثابت برمی‌گردانیم.
            vec[0] = 1.0
            return vec
        return [v / norm for v in vec]

    async def embed(self, texts: list[str]) -> list[list[float]]:
        return [self._vector(t) for t in texts]
