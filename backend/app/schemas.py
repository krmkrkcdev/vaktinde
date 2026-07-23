import uuid
from datetime import datetime

from pydantic import BaseModel, ConfigDict, EmailStr, Field, field_validator


# --------------------------------------------------------------------- auth


class RegisterRequest(BaseModel):
    email: EmailStr
    password: str = Field(min_length=8, max_length=200)

    @field_validator("password")
    @classmethod
    def not_only_whitespace(cls, v: str) -> str:
        if not v.strip():
            raise ValueError("Şifre boşluk karakterlerinden oluşamaz")
        return v


class LoginRequest(BaseModel):
    email: EmailStr
    password: str


class RefreshRequest(BaseModel):
    refresh_token: str


class TokenResponse(BaseModel):
    access_token: str
    refresh_token: str
    token_type: str = "bearer"


class UserResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    email: str
    created_at: datetime


class ChangePasswordRequest(BaseModel):
    current_password: str
    new_password: str = Field(min_length=8, max_length=200)


class DeleteAccountRequest(BaseModel):
    """Hesap silme geri alınamaz olduğu için şifre yeniden doğrulanır."""

    password: str


# --------------------------------------------------------------------- sync


class ReminderPayload(BaseModel):
    """İstemciden gelen veya istemciye giden bir hatırlatma.

    Fotoğraflar burada listelenmez: her fotoğraf kendi `reminder_id` alanını
    taşır ve `/sync/changes` içinde ayrı döner. Tek kaynak tutulur, iki
    listenin birbiriyle çelişmesi mümkün olmaz.
    """

    id: uuid.UUID
    category_id: str = Field(max_length=64)
    title: str = Field(max_length=500)
    note: str | None = None
    due_date: datetime
    lead_days: str = Field(default="", max_length=200)
    notify_hour: int = Field(default=9, ge=0, le=23)
    notify_minute: int = Field(default=0, ge=0, le=59)
    repeat_interval: str = Field(default="none", max_length=32)
    is_archived: bool = False
    amount: float | None = None
    created_at: datetime
    is_deleted: bool = False
    client_updated_at: datetime


class PhotoMeta(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    reminder_id: uuid.UUID
    content_type: str
    size_bytes: int
    has_content: bool
    is_deleted: bool


class PushRequest(BaseModel):
    reminders: list[ReminderPayload] = Field(default_factory=list, max_length=500)


class PushResponse(BaseModel):
    # Sunucuda daha yeni bir sürüm bulunduğu için uygulanmayan kayıtlar.
    # İstemci bunları bir sonraki çekmede sunucu sürümüyle değiştirir.
    rejected_ids: list[uuid.UUID]
    cursor: int


class ChangesResponse(BaseModel):
    reminders: list[ReminderPayload]
    photos: list[PhotoMeta]
    cursor: int
    # Bu çekimde tüm değişiklikler dönmediyse istemci tekrar çağırmalıdır.
    has_more: bool


class PhotoUploadResponse(BaseModel):
    id: uuid.UUID
    size_bytes: int
    cursor: int
