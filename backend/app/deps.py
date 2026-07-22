import jwt
from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from sqlalchemy.orm import Session

from .database import get_db
from .models import User
from .security import decode_token

bearer_scheme = HTTPBearer(auto_error=False)

_UNAUTHORIZED = HTTPException(
    status_code=status.HTTP_401_UNAUTHORIZED,
    detail="Geçersiz veya süresi dolmuş oturum",
    headers={"WWW-Authenticate": "Bearer"},
)


def current_user(
    credentials: HTTPAuthorizationCredentials | None = Depends(bearer_scheme),
    db: Session = Depends(get_db),
) -> User:
    if credentials is None:
        raise _UNAUTHORIZED

    try:
        user_id, token_version = decode_token(credentials.credentials, "access")
    except jwt.InvalidTokenError:
        raise _UNAUTHORIZED from None

    user = db.get(User, user_id)
    if user is None:
        raise _UNAUTHORIZED

    # Şifre değişimi veya çıkış sonrası eski tokenlar reddedilir.
    if token_version != user.token_version:
        raise _UNAUTHORIZED

    return user
