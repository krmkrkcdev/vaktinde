"""Test kurulumu.

Testler gerçek PostgreSQL'e karşı çalışır — üretimde kullanılan veritabanının
aynısı. SQLite taklidi kullanılsaydı senkronizasyon dizisi (`nextval`), UUID
sütunları ve eşzamanlı yazma davranışı test edilmemiş kalırdı.

Çalıştırmak için:
    docker compose run --rm --no-deps -e DATABASE_URL=... api \\
        sh -c "pip install -r requirements-dev.txt && pytest"

Ayrıntı için README'deki "Testler" bölümüne bakın.
"""

import os
import uuid

import pytest
from sqlalchemy import create_engine, text

# Uygulama ayarları import anında okunur; test veritabanı önce ayarlanır.
TEST_DB = "vaktinde_test"
_base_url = os.environ.get(
    "DATABASE_URL", "postgresql+psycopg://vaktinde:vaktinde@db:5432/vaktinde"
)
_admin_url = _base_url.rsplit("/", 1)[0] + "/postgres"
_test_url = _base_url.rsplit("/", 1)[0] + f"/{TEST_DB}"
os.environ["DATABASE_URL"] = _test_url


def _ensure_test_database() -> None:
    admin = create_engine(_admin_url, isolation_level="AUTOCOMMIT")
    with admin.connect() as conn:
        exists = conn.execute(
            text("SELECT 1 FROM pg_database WHERE datname = :name"), {"name": TEST_DB}
        ).scalar()
        if not exists:
            conn.execute(text(f'CREATE DATABASE "{TEST_DB}"'))
    admin.dispose()


_ensure_test_database()

from fastapi.testclient import TestClient  # noqa: E402

from app.config import get_settings  # noqa: E402
from app.database import SYNC_SEQUENCE, Base, engine  # noqa: E402
from app.main import app  # noqa: E402


@pytest.fixture(scope="session", autouse=True)
def _schema():
    Base.metadata.drop_all(bind=engine)
    Base.metadata.create_all(bind=engine)
    with engine.begin() as conn:
        conn.execute(text(f"CREATE SEQUENCE IF NOT EXISTS {SYNC_SEQUENCE}"))
    yield


@pytest.fixture(autouse=True)
def _clean_tables(tmp_path, monkeypatch):
    """Her testten önce tabloları boşaltır ve fotoğrafları geçici dizine yazar."""
    with engine.begin() as conn:
        conn.execute(
            text("TRUNCATE users, reminders, photos, login_attempts CASCADE")
        )
    monkeypatch.setattr(get_settings(), "photo_dir", tmp_path / "photos")
    yield


@pytest.fixture
def client():
    # Lifespan çalıştırılmaz; şema `_schema` fixture'ı tarafından kurulur.
    return TestClient(app)


@pytest.fixture
def auth_client(client):
    """Kayıtlı ve giriş yapmış bir kullanıcıyla hazır istemci."""
    email = f"kullanici-{uuid.uuid4().hex[:8]}@ornek.com"
    response = client.post(
        "/auth/register", json={"email": email, "password": "GucluSifre123"}
    )
    assert response.status_code == 201, response.text
    tokens = response.json()
    client.headers["Authorization"] = f"Bearer {tokens['access_token']}"
    client.email = email
    client.tokens = tokens
    return client
