from app.services import storage


def test_local_storage_round_trip(monkeypatch, tmp_path):
    monkeypatch.delenv("GCS_BUCKET_NAME", raising=False)
    monkeypatch.delenv("K_SERVICE", raising=False)
    monkeypatch.delenv("ENVIRONMENT", raising=False)
    monkeypatch.setenv("CLEAVE_LOCAL_STORAGE_DIR", str(tmp_path))

    object_name = storage.upload_image_to_gcs(b"avatar", "image/png", folder="avatars")

    assert object_name.startswith("avatars/")
    assert storage.download_image_from_gcs(object_name) == (b"avatar", "image/png")
    assert storage.delete_images_from_gcs([object_name]) is True
    assert storage.download_image_from_gcs(object_name) is None


def test_managed_runtime_fails_closed_without_bucket(monkeypatch, tmp_path):
    monkeypatch.delenv("GCS_BUCKET_NAME", raising=False)
    monkeypatch.setenv("K_SERVICE", "cleave-api")
    monkeypatch.setenv("CLEAVE_LOCAL_STORAGE_DIR", str(tmp_path))

    assert storage.upload_image_to_gcs(b"avatar", "image/png", folder="avatars") == ""
    assert list(tmp_path.rglob("*")) == []
    assert storage.download_image_from_gcs("avatars/missing.png") is None
    assert storage.delete_images_from_gcs(["avatars/missing.png"]) is False


def test_private_storage_rejects_traversal_urls_and_unknown_folders(monkeypatch, tmp_path):
    monkeypatch.delenv("GCS_BUCKET_NAME", raising=False)
    monkeypatch.delenv("K_SERVICE", raising=False)
    monkeypatch.delenv("ENVIRONMENT", raising=False)
    monkeypatch.setenv("CLEAVE_LOCAL_STORAGE_DIR", str(tmp_path))

    assert storage.download_image_from_gcs("../secret.txt") is None
    assert storage.download_image_from_gcs("https://example.com/avatar.jpg") is None
    assert storage.download_image_from_gcs("receipts/nested/image.jpg") is None

    try:
        storage.upload_image_to_gcs(b"bad", "image/jpeg", folder="public")
        raised = False
    except ValueError:
        raised = True

    assert raised is True
