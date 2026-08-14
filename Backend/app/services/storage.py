from __future__ import annotations

import logging
import mimetypes
import os
import uuid
from pathlib import Path
from pathlib import PurePosixPath

from google.cloud import storage


logger = logging.getLogger(__name__)
ALLOWED_STORAGE_FOLDERS = {"avatars", "memories", "receipts"}


def _safe_object_name(object_name: str) -> str | None:
    if not object_name or object_name.startswith(("http://", "https://", "/")):
        return None
    path = PurePosixPath(object_name)
    if ".." in path.parts or len(path.parts) != 2 or path.parts[0] not in ALLOWED_STORAGE_FOLDERS:
        return None
    return str(path)


def _bucket_name() -> str:
    return os.environ.get("GCS_BUCKET_NAME", "")


def _local_storage_dir() -> Path:
    root = Path(os.environ.get("CLEAVE_LOCAL_STORAGE_DIR", "/private/tmp/cleave-local-storage"))
    root.mkdir(parents=True, exist_ok=True)
    return root


def _use_local_storage() -> bool:
    # A managed deployment must never report a successful upload to ephemeral
    # disk when its bucket configuration is missing. Local development keeps
    # the filesystem fallback for an easy offline setup.
    is_managed_runtime = bool(os.environ.get("K_SERVICE"))
    environment = os.environ.get("ENVIRONMENT", "").strip().lower()
    return not bool(_bucket_name()) and not is_managed_runtime and environment not in {
        "production",
        "staging",
    }


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
    if safe_folder not in ALLOWED_STORAGE_FOLDERS:
        raise ValueError("Unsupported private storage folder")
    object_name = f"{safe_folder}/{uuid.uuid4()}.{extension}"
    if _use_local_storage():
        path = _local_storage_dir() / object_name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(image_bytes)
        return object_name
    if not _bucket_name():
        logger.error("GCS_BUCKET_NAME is required outside local development")
        return ""
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
    object_name = _safe_object_name(object_name)
    if object_name is None:
        return None
    if _use_local_storage():
        path = _local_storage_dir() / object_name
        if not path.is_file():
            return None
        return path.read_bytes(), mimetypes.guess_type(path.name)[0] or "application/octet-stream"
    if not _bucket_name():
        logger.error("GCS_BUCKET_NAME is required outside local development")
        return None
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
        safe_name
        for name in object_names
        if (safe_name := _safe_object_name(name)) is not None
    }
    if not valid_names:
        return True

    if _use_local_storage():
        for object_name in valid_names:
            path = _local_storage_dir() / object_name
            path.unlink(missing_ok=True)
        return True

    if not _bucket_name():
        logger.error("GCS_BUCKET_NAME is required outside local development")
        return False

    try:
        bucket = storage.Client().bucket(_bucket_name())
        for object_name in valid_names:
            bucket.blob(object_name).delete(if_generation_match=None)
        return True
    except Exception:
        logger.exception("Receipt image deletion failed")
        return False
