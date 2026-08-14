from __future__ import annotations


ALLOWED_IMAGE_TYPES = {"image/jpeg", "image/png", "image/heic", "image/heif"}


def detected_image_type(content: bytes) -> str | None:
    """Identify the small set of image containers Cleave accepts.

    Content-Type is supplied by the client and is not a security boundary. This
    signature check prevents HTML, scripts, and arbitrary binary files from
    being stored or forwarded to the receipt parser under an image MIME type.
    """
    if content.startswith(b"\xff\xd8\xff"):
        return "image/jpeg"
    if content.startswith(b"\x89PNG\r\n\x1a\n"):
        return "image/png"
    if len(content) >= 12 and content[4:8] == b"ftyp":
        brand = content[8:12]
        if brand in {b"heic", b"heix", b"hevc", b"hevx"}:
            return "image/heic"
        if brand in {b"mif1", b"msf1"}:
            return "image/heif"
    return None


def validate_image_upload(content: bytes, declared_type: str) -> str:
    normalized_type = declared_type.lower().strip()
    if normalized_type not in ALLOWED_IMAGE_TYPES:
        raise ValueError("unsupported image type")
    detected_type = detected_image_type(content)
    if detected_type is None:
        raise ValueError("file content is not a supported image")
    heif_family = {"image/heic", "image/heif"}
    if detected_type != normalized_type and not {
        detected_type,
        normalized_type,
    }.issubset(heif_family):
        raise ValueError("file content does not match its image type")
    return detected_type
