import uuid
from datetime import datetime, timedelta, timezone
from typing import Literal

import bcrypt
import jwt

from .config import get_settings

_settings = get_settings()

ALGORITHM = "HS256"
TokenType = Literal["access", "refresh"]


def hash_password(password: str) -> str:
    # bcrypt girdiyi 72 bayta kırpar; sessiz kırpma yerine açıkça sınırlarız.
    return bcrypt.hashpw(_encode(password), bcrypt.gensalt()).decode()


def verify_password(password: str, password_hash: str) -> bool:
    try:
        return bcrypt.checkpw(_encode(password), password_hash.encode())
    except ValueError:
        # Bozuk hash — doğrulama başarısız sayılır.
        return False


def _encode(password: str) -> bytes:
    return password.encode("utf-8")[:72]


def create_token(
    user_id: uuid.UUID,
    token_version: int,
    token_type: TokenType,
) -> str:
    now = datetime.now(timezone.utc)
    lifetime = (
        timedelta(minutes=_settings.access_token_minutes)
        if token_type == "access"
        else timedelta(days=_settings.refresh_token_days)
    )
    payload = {
        "sub": str(user_id),
        "typ": token_type,
        "ver": token_version,
        "iat": now,
        "exp": now + lifetime,
    }
    return jwt.encode(payload, _settings.jwt_secret, algorithm=ALGORITHM)


def decode_token(token: str, expected_type: TokenType) -> tuple[uuid.UUID, int]:
    """Doğrulanmış tokendan (kullanıcı kimliği, sürüm) döndürür.

    Geçersiz, süresi dolmuş veya yanlış türde token için `jwt.InvalidTokenError`
    fırlatır.
    """
    payload = jwt.decode(token, _settings.jwt_secret, algorithms=[ALGORITHM])
    if payload.get("typ") != expected_type:
        raise jwt.InvalidTokenError("Beklenmeyen token türü")
    return uuid.UUID(payload["sub"]), int(payload.get("ver", 0))
