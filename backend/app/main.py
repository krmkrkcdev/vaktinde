import logging
from contextlib import asynccontextmanager
from pathlib import Path

from fastapi import FastAPI
from fastapi.responses import HTMLResponse
from fastapi.middleware.cors import CORSMiddleware
from sqlalchemy import text

from .config import get_settings
from .database import SYNC_SEQUENCE, Base, engine
from .routers import auth, photos, sync

logger = logging.getLogger("vaktinde")
settings = get_settings()

# Açılışta bir kez okunur: her istekte diske gitmenin anlamı yok.
_STATIC = Path(__file__).parent / "static"
_PRIVACY_HTML = (_STATIC / "gizlilik.html").read_text(encoding="utf-8")
_SUPPORT_HTML = (_STATIC / "destek.html").read_text(encoding="utf-8")


@asynccontextmanager
async def lifespan(app: FastAPI):
    # Şema oluşturma basit tutuldu: tek sürümlü bir başlangıç için yeterli.
    # Şema değiştirmeye başlandığında Alembic eklenmelidir; `create_all`
    # mevcut tabloları değiştirmez.
    Base.metadata.create_all(bind=engine)
    with engine.begin() as conn:
        conn.execute(text(f"CREATE SEQUENCE IF NOT EXISTS {SYNC_SEQUENCE}"))

    settings.photo_dir.mkdir(parents=True, exist_ok=True)
    logger.info("Vaktinde API hazır")
    yield


app = FastAPI(
    title="Vaktinde API",
    version="1.0.0",
    description="Belge ve ödeme hatırlatıcısı için senkronizasyon sunucusu.",
    lifespan=lifespan,
)

if settings.cors_origin_list:
    app.add_middleware(
        CORSMiddleware,
        allow_origins=settings.cors_origin_list,
        allow_credentials=True,
        allow_methods=["*"],
        allow_headers=["*"],
    )

app.include_router(auth.router)
app.include_router(sync.router)
app.include_router(photos.router)


@app.get("/gizlilik", response_class=HTMLResponse, tags=["system"])
def privacy_policy() -> HTMLResponse:
    """Gizlilik politikası.

    App Store ve AdMob, uygulamanın herkese açık bir gizlilik politikası
    adresi sunmasını zorunlu tutuyor. Sayfa statik olduğu için şablon motoru
    yerine doğrudan dosyadan okunuyor.
    """
    return HTMLResponse(_PRIVACY_HTML)


@app.get("/destek", response_class=HTMLResponse, tags=["system"])
def support() -> HTMLResponse:
    """Destek sayfası. App Store zorunlu bir destek URL'i istiyor."""
    return HTMLResponse(_SUPPORT_HTML)


@app.get("/health", tags=["system"])
def health() -> dict[str, str]:
    """Docker ve nginx sağlık kontrolü için."""
    with engine.connect() as conn:
        conn.execute(text("SELECT 1"))
    return {"status": "ok"}
