import pytest

from app.services.receipt_parser import parseReceiptImage


def test_receipt_parser_fails_safely_without_api_key(monkeypatch):
    monkeypatch.delenv("GEMINI_API_KEY", raising=False)

    with pytest.raises(ValueError, match="temporarily unavailable"):
        parseReceiptImage(b"image", "image/jpeg")
