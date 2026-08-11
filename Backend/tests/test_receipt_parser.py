import pytest

from app.models.schemas import ParsedReceipt
from app.services.receipt_parser import parseReceiptImage


def test_receipt_parser_fails_safely_without_api_key(monkeypatch):
    monkeypatch.delenv("GEMINI_API_KEY", raising=False)

    with pytest.raises(ValueError, match="temporarily unavailable"):
        parseReceiptImage(b"image", "image/jpeg")


def test_gemini_response_schema_uses_supported_minimum_keyword():
    schema = ParsedReceipt.model_json_schema()
    serialized = str(schema)

    assert "exclusiveMinimum" not in serialized
    assert schema["properties"]["total"]["minimum"] == 0.01
