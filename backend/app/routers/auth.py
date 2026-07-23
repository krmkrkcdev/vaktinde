from datetime import datetime, timedelta, timezone

import logging
import shutil

import jwt
from fastapi import APIRouter, Depends, HTTPException, Response, status
from sqlalchemy import delete, func, select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from ..config import get_settings
from ..database import get_db
from ..deps import current_user
from ..models import LoginAttempt, User
from ..schemas import (
    ChangePasswordRequest,
    DeleteAccountRequest,
    LoginRequest,
    RefreshRequest,
    RegisterRequest,
    TokenResponse,
    UserResponse,
)
from ..security import create_token, decode_token, hash_password, verify_password

router = APIRouter(prefix="/auth", tags=["auth"])
settings = get_settings()
logger = logging.getLogger("vaktinde")


def _tokens(user: User) -> TokenResponse:
    return TokenResponse(
        access_token=create_token(user.id, user.token_version, "access"),
        refresh_token=create_token(user.id, user.token_version, "refresh"),
    )


def _normalize(email: str) -> str:
    return email.strip().lower()


def _too_many_attempts(db: Session, email: str) -> bool:
    window_start = datetime.now(timezone.utc) - timedelta(
        seconds=settings.login_window_seconds
    )
    count = db.scalar(
        select(func.count())
        .select_from(LoginAttempt)
        .where(LoginAttempt.email == email, LoginAttempt.created_at >= window_start)
    )
    return (count or 0) >= settings.login_max_attempts


def _record_failure(db: Session, email: str) -> None:
    db.add(LoginAttempt(email=email))
    # Pencere dışındaki kayıtları biriktirmemek için temizle.
    cutoff = datetime.now(timezone.utc) - timedelta(
        seconds=settings.login_window_seconds * 4
    )
    db.execute(delete(LoginAttempt).where(LoginAttempt.created_at < cutoff))
    db.commit()


@router.post("/register", response_model=TokenResponse, status_code=201)
def register(body: RegisterRequest, db: Session = Depends(get_db)) -> TokenResponse:
    user = User(email=_normalize(body.email), password_hash=hash_password(body.password))
    db.add(user)
    try:
        db.commit()
    except IntegrityError:
        db.rollback()
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Bu e-posta adresi zaten kayıtlı",
        ) from None
    db.refresh(user)
    return _tokens(user)


@router.post("/login", response_model=TokenResponse)
def login(body: LoginRequest, db: Session = Depends(get_db)) -> TokenResponse:
    email = _normalize(body.email)

    if _too_many_attempts(db, email):
        raise HTTPException(
            status_code=status.HTTP_429_TOO_MANY_REQUESTS,
            detail="Çok fazla başarısız deneme. Birkaç dakika sonra tekrar deneyin.",
        )

    user = db.scalar(select(User).where(User.email == email))

    # Hesabın var olup olmadığını sızdırmamak için her iki durumda da aynı
    # yanıt döner ve şifre doğrulama maliyeti benzer tutulur.
    if user is None or not verify_password(body.password, user.password_hash):
        _record_failure(db, email)
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="E-posta veya şifre hatalı",
        )

    return _tokens(user)


@router.post("/refresh", response_model=TokenResponse)
def refresh(body: RefreshRequest, db: Session = Depends(get_db)) -> TokenResponse:
    try:
        user_id, token_version = decode_token(body.refresh_token, "refresh")
    except jwt.InvalidTokenError:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Oturum süresi doldu, tekrar giriş yapın",
        ) from None

    user = db.get(User, user_id)
    if user is None or token_version != user.token_version:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Oturum süresi doldu, tekrar giriş yapın",
        )

    return _tokens(user)


@router.get("/me", response_model=UserResponse)
def me(user: User = Depends(current_user)) -> User:
    return user


@router.delete("/me", status_code=status.HTTP_204_NO_CONTENT)
def delete_account(
    body: DeleteAccountRequest,
    user: User = Depends(current_user),
    db: Session = Depends(get_db),
) -> Response:
    """Hesabı ve tüm verilerini kalıcı olarak siler.

    App Store, hesap oluşturmaya izin veren uygulamaların hesap silmeyi de
    uygulama içinden sunmasını zorunlu tutuyor (Review Guideline 5.1.1).

    Hatırlatmalar ve fotoğraf kayıtları veritabanında ON DELETE CASCADE ile
    gider; fotoğraf DOSYALARI veritabanının dışında olduğu için ayrıca
    silinir. Dosyalar önce silinir: satır kalıp dosya kalmasındansa, silme
    yarıda kesilirse sahipsiz dosya kalmaması tercih edilir.
    """
    if not verify_password(body.password, user.password_hash):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Şifre doğrulanamadı",
        )

    shutil.rmtree(settings.photo_dir / str(user.id), ignore_errors=True)

    db.delete(user)
    db.commit()

    logger.info("Hesap silindi: %s", user.id)
    return Response(status_code=status.HTTP_204_NO_CONTENT)


@router.post("/change-password", response_model=TokenResponse)
def change_password(
    body: ChangePasswordRequest,
    user: User = Depends(current_user),
    db: Session = Depends(get_db),
) -> TokenResponse:
    if not verify_password(body.current_password, user.password_hash):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Mevcut şifre hatalı",
        )

    user.password_hash = hash_password(body.new_password)
    # Diğer cihazlardaki oturumları düşürür.
    user.token_version += 1
    db.commit()
    db.refresh(user)
    return _tokens(user)
