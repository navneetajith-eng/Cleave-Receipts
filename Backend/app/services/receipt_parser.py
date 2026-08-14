import logging
import os

from dotenv import load_dotenv

from app.models.schemas import ParsedReceipt

load_dotenv()

logger = logging.getLogger(__name__)

def parseReceiptImage(image_bytes: bytes, mime_type: str = "image/jpeg") -> ParsedReceipt:
    """
    Parses a receipt image using Google's Gemini 3.5 Flash-Lite vision model.
    Raises a user-safe error if the parser is unavailable or cannot confidently
    return structured receipt data. Production must never invent financial data.
    """
    api_key = os.environ.get("GEMINI_API_KEY", "")
    if not api_key:
        raise ValueError("Receipt scanning is temporarily unavailable")

    # Import lazily so API routes that do not scan receipts stay lightweight.
    from google import genai
    from google.genai import errors, types

    prompt = """
    Extract the merchant, totals, and every purchased item from this receipt.

    Currency rules:
    - Return the ISO currency code printed or clearly implied by an explicit currency
      symbol. Supported values are USD, INR, and AED.
    - Do not guess a currency when the receipt does not provide enough evidence;
      leave currency_code empty so the app can ask the scanner to confirm it.

    Receipt line-item rules:
    - Transcribe every physical purchased row exactly once, in top-to-bottom order.
    - Never merge or deduplicate repeated products. If the same product appears twice,
      return two separate line_items, even when the names and prices are identical.
    - Preserve the printed item name, but omit SKU, UPC, register codes, and trailing
      tax/availability flags from the description.
    - Use the price printed at the far right of that item row.
    - Keep discounts, coupons, subtotals, tax, tip, payment details, barcodes, and
      footer text out of line_items.
    - Do not infer missing rows or prices. If a purchased row is readable but its
      price is unclear, still return the row only when the price can be determined.
    - Represent discounts or member savings as one positive discount value.
    - The extracted line items should reconcile with the receipt subtotal when the
      receipt provides enough information; do not change item prices to force a match.
    """

    try:
        with genai.Client(api_key=api_key) as client:
            response = client.models.generate_content(
                model=os.environ.get("GEMINI_MODEL", "gemini-3.5-flash-lite"),
                contents=[
                    prompt,
                    types.Part.from_bytes(data=image_bytes, mime_type=mime_type),
                ],
                config=types.GenerateContentConfig(
                    response_mime_type="application/json",
                    response_schema=ParsedReceipt,
                    # Receipt text is often small and densely packed. The high
                    # media resolution materially improves line-item OCR.
                    media_resolution=types.MediaResolution.MEDIA_RESOLUTION_HIGH,
                ),
            )
        if isinstance(response.parsed, ParsedReceipt):
            return response.parsed
        if response.text:
            return ParsedReceipt.model_validate_json(response.text)
        raise ValueError("The parser returned no receipt data")
    except errors.APIError as error:
        raise ValueError("Receipt scanning is temporarily unavailable") from error
    except Exception as error:
        logger.exception("Receipt parser failed: %s", type(error).__name__)
        raise ValueError(
            "We couldn't read that receipt. Try a clearer, well-lit photo."
        ) from error
