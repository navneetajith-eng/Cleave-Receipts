import os
import json
import google.generativeai as genai
from app.models.schemas import ParsedReceipt, LineItemBase

# The API Key should be set in the environment before starting the FastAPI server
api_key = os.environ.get("GEMINI_API_KEY", "")
if api_key:
    genai.configure(api_key=api_key)

def parseReceiptImage(image_bytes: bytes, mime_type: str = "image/jpeg") -> ParsedReceipt:
    """
    Parses a receipt image using Google's Gemini 1.5 Flash Vision model.
    If the API key is not set, it returns mock data to keep the app working.
    """
    if not api_key:
        print("WARNING: GEMINI_API_KEY not set. Returning mock data.")
        return ParsedReceipt(
            vendor_name="Mock Restaurant (Missing API Key)",
            tax=8.50,
            tip=15.00,
            total=108.50,
            line_items=[
                LineItemBase(description="Mock Burger", price=15.00),
                LineItemBase(description="Mock Fries", price=5.00),
                LineItemBase(description="Mock Steak", price=35.00),
                LineItemBase(description="Mock Salad", price=10.00),
                LineItemBase(description="Mock Wine", price=20.00),
            ]
        )

    # Initialize the model (Flash is fast, multimodal, and cheap/free)
    model = genai.GenerativeModel('gemini-flash-latest')
    
    prompt = """
    Extract the receipt details from this image. 
    Return ONLY a valid JSON object with exactly these fields:
    {
        "vendor_name": "Name of the restaurant or store",
        "tax": float (the tax amount, or 0.0),
        "tip": float (the tip amount, or 0.0),
        "total": float (the final total amount),
        "line_items": [
            {
                "description": "Item name",
                "price": float (the price of the item)
            }
        ]
    }
    Make sure to extract all line items (the actual food/drink ordered). 
    Do NOT include subtotals, tax, or tip as line items.
    """
    
    try:
        response = model.generate_content([
            {'mime_type': mime_type, 'data': image_bytes},
            prompt
        ], generation_config=genai.types.GenerationConfig(
            response_mime_type="application/json"
        ))
        
        # Parse the JSON string from Gemini into our Pydantic model
        data = json.loads(response.text)
        
        return ParsedReceipt(
            vendor_name=data.get("vendor_name", "Unknown Vendor"),
            tax=float(data.get("tax", 0.0)),
            tip=float(data.get("tip", 0.0)),
            total=float(data.get("total", 0.0)),
            line_items=[
                LineItemBase(description=item["description"], price=float(item["price"])) 
                for item in data.get("line_items", [])
            ]
        )
    except Exception as e:
        print(f"Error parsing receipt with Gemini: {e}")
        # Fallback in case of AI parsing failure (e.g. rate limit, bad photo)
        return ParsedReceipt(
            vendor_name="Parsing Error",
            tax=0.0, tip=0.0, total=0.0,
            line_items=[LineItemBase(description="Failed to parse", price=0.0)]
        )
