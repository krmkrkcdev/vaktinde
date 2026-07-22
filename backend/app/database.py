from collections.abc import Iterator

from sqlalchemy import create_engine, text
from sqlalchemy.orm import DeclarativeBase, Session, sessionmaker

from .config import get_settings


class Base(DeclarativeBase):
    pass


_settings = get_settings()

engine = create_engine(
    _settings.database_url,
    pool_pre_ping=True,
    future=True,
)

SessionLocal = sessionmaker(bind=engine, autoflush=False, expire_on_commit=False)

# Senkronizasyon imleci için paylaşılan sayaç.
#
# Zaman damgası yerine dizi kullanılır: istemci saatleri güvenilmezdir ve
# aynı milisaniyede yazılan iki kayıt sıralanamaz. Monoton artan bir sayı,
# "şu imleçten sonrasını ver" sorgusunu kesin hâle getirir.
SYNC_SEQUENCE = "vaktinde_sync_seq"


def next_sync_seq(db: Session) -> int:
    return db.execute(text(f"SELECT nextval('{SYNC_SEQUENCE}')")).scalar_one()


def get_db() -> Iterator[Session]:
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()
