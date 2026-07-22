import logging
from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from sqlalchemy import text

from .config import get_settings
from .database import SYNC_SEQUENCE, Base, engine
from .routers import auth, photos, sync

logger = logging.getLogger("vaktinde")
settings = get_settings()


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


@app.get("/health", tags=["system"])
def health() -> dict[str, str]:
    """Docker ve nginx sağlık kontrolü için."""
    with engine.connect() as conn:
        conn.execute(text("SELECT 1"))
    return {"status": "ok"}
