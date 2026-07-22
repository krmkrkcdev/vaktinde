import uuid
from datetime import datetime, timezone

from sqlalchemy import (
    BigInteger,
    Boolean,
    DateTime,
    Float,
    ForeignKey,
    Index,
    Integer,
    String,
    Text,
)
from sqlalchemy.dialects.postgresql import UUID as PgUUID
from sqlalchemy.orm import Mapped, mapped_column, relationship

from .database import Base


def utcnow() -> datetime:
    return datetime.now(timezone.utc)


class User(Base):
    __tablename__ = "users"

    id: Mapped[uuid.UUID] = mapped_column(
        PgUUID(as_uuid=True), primary_key=True, default=uuid.uuid4
    )
    email: Mapped[str] = mapped_column(String(320), unique=True, index=True)
    password_hash: Mapped[str] = mapped_column(String(255))
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=utcnow
    )
    # Tüm oturumları geçersiz kılmak için artırılır (şifre değişimi, çıkış).
    token_version: Mapped[int] = mapped_column(Integer, default=0)

    reminders: Mapped[list["Reminder"]] = relationship(back_populates="user")


class Reminder(Base):
    """Bir hatırlatmanın sunucudaki kopyası.

    Birincil anahtar istemci tarafından üretilir: kullanıcı çevrimdışıyken
    kayıt oluşturabilmeli ve sonradan senkronize edildiğinde kimliği
    değişmemelidir.
    """

    __tablename__ = "reminders"

    id: Mapped[uuid.UUID] = mapped_column(PgUUID(as_uuid=True), primary_key=True)
    user_id: Mapped[uuid.UUID] = mapped_column(
        PgUUID(as_uuid=True), ForeignKey("users.id", ondelete="CASCADE"), index=True
    )

    category_id: Mapped[str] = mapped_column(String(64))
    title: Mapped[str] = mapped_column(String(500))
    note: Mapped[str | None] = mapped_column(Text, nullable=True)
    due_date: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    lead_days: Mapped[str] = mapped_column(String(200), default="")
    notify_hour: Mapped[int] = mapped_column(Integer, default=9)
    notify_minute: Mapped[int] = mapped_column(Integer, default=0)
    repeat_interval: Mapped[str] = mapped_column(String(32), default="none")
    is_archived: Mapped[bool] = mapped_column(Boolean, default=False)
    amount: Mapped[float | None] = mapped_column(Float, nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))

    # Silinen kayıtlar fiziksel olarak silinmez: diğer cihazların silmeyi
    # öğrenebilmesi için mezar taşı bırakılır.
    is_deleted: Mapped[bool] = mapped_column(Boolean, default=False)

    # Çakışma çözümü: istemcinin bildirdiği son değişiklik zamanı.
    # Gelen kayıt saklanandan eskiyse yok sayılır (son yazan kazanır).
    client_updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))

    # Çekme imleci. İstemci "bu sayıdan büyükleri ver" der.
    sync_seq: Mapped[int] = mapped_column(BigInteger, index=True)

    user: Mapped[User] = relationship(back_populates="reminders")

    __table_args__ = (Index("ix_reminders_user_seq", "user_id", "sync_seq"),)


class Photo(Base):
    """Belge fotoğrafı üstverisi. İkili içerik diskte tutulur."""

    __tablename__ = "photos"

    id: Mapped[uuid.UUID] = mapped_column(PgUUID(as_uuid=True), primary_key=True)
    user_id: Mapped[uuid.UUID] = mapped_column(
        PgUUID(as_uuid=True), ForeignKey("users.id", ondelete="CASCADE"), index=True
    )
    reminder_id: Mapped[uuid.UUID] = mapped_column(PgUUID(as_uuid=True), index=True)

    content_type: Mapped[str] = mapped_column(String(100), default="image/jpeg")
    size_bytes: Mapped[int] = mapped_column(Integer, default=0)

    # İçerik henüz yüklenmediyse False. Üstveri senkronizasyonu ile ikili
    # yükleme ayrı adımlardır; ikisi arasında kayıt eksik içerikli olabilir.
    has_content: Mapped[bool] = mapped_column(Boolean, default=False)

    is_deleted: Mapped[bool] = mapped_column(Boolean, default=False)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=utcnow
    )
    sync_seq: Mapped[int] = mapped_column(BigInteger, index=True)

    __table_args__ = (Index("ix_photos_user_seq", "user_id", "sync_seq"),)


class LoginAttempt(Base):
    """Kaba kuvvet denemelerini sınırlamak için başarısız giriş kaydı."""

    __tablename__ = "login_attempts"

    id: Mapped[int] = mapped_column(BigInteger, primary_key=True, autoincrement=True)
    email: Mapped[str] = mapped_column(String(320), index=True)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=utcnow, index=True
    )
