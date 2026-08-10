from __future__ import annotations

import logging
import mimetypes
import os
import uuid
from pathlib import Path

from google.cloud import storage


logger = logging.getLogger(__name__)


def _bucket_name() -> str:
    return os.environ.get("GCS_BUCKET_NAME", "")


def _local_storage_dir() -> Path:
    root = Path(os.environ.get("CLEAVE_LOCAL_STORAGE_DIR", "/private/tmp/cleave-local-storage"))
    root.mkdir(parents=True, exist_ok=True)
    return root


def _use_local_storage() -> bool:
    # Local development has no GCS bucket configured. Production sets
    # GCS_BUCKET_NAME and continues to use the private Cloud Storage bucket.
    return not bool(_bucket_name())


def upload_image_to_gcs(
    image_bytes: bytes,
    mime_type: str = "image/jpeg",
    *,
    folder: str = "receipts",
) -> str:
    """Upload an image and return its private object name, never a public URL."""
    extension = {
        "image/jpeg": "jpg",
        "image/png": "png",
        "image/heic": "heic",
        "image/heif": "heif",
    }.get(mime_type, "bin")
    safe_folder = folder.strip("/") or "receipts"
    object_name = f"{safe_folder}/{uuid.uuid4()}.{extension}"
    if _use_local_storage():
        path = _local_storage_dir() / object_name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(image_bytes)
        return object_name
    try:
        client = storage.Client()
        blob = client.bucket(_bucket_name()).blob(object_name)
        blob.upload_from_string(image_bytes, content_type=mime_type)
        return object_name
    except Exception:
        logger.exception("Receipt image upload failed")
        return ""


def download_image_from_gcs(object_name: str) -> tuple[bytes, str] | None:
    """Download a private image after the API has authorized the caller."""
    if not object_name or object_name.startswith(("http://", "https://")):
        return None
    if _use_local_storage():
        path = _local_storage_dir() / object_name
        if not path.is_file():
            return None
        return path.read_bytes(), mimetypes.guess_type(path.name)[0] or "application/octet-stream"
    try:
        client = storage.Client()
        blob = client.bucket(_bucket_name()).blob(object_name)
        blob.reload()
        return blob.download_as_bytes(), blob.content_type or "application/octet-stream"
    except Exception:
        logger.exception("Receipt image download failed")
        return None


def delete_images_from_gcs(object_names: list[str]) -> bool:
    """Delete private objects and report whether every requested object was removed."""
    valid_names = {
        name
        for name in object_names
        if name and not name.startswith(("http://", "https://"))
    }
    if not valid_names:
        return True

    if _use_local_storage():
        for object_name in valid_names:
            path = _local_storage_dir() / object_name
            path.unlink(missing_ok=True)
        return True

    try:
        bucket = storage.Client().bucket(_bucket_name())
        for object_name in valid_names:
            bucket.blob(object_name).delete(if_generation_match=None)
        return True
    except Exception:
        logger.exception("Receipt image deletion failed")
        return False
