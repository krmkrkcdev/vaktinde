import uuid
from pathlib import Path

from fastapi import APIRouter, Depends, File, HTTPException, UploadFile, status
from fastapi.responses import FileResponse
from sqlalchemy import func, select
from sqlalchemy.orm import Session

from ..config import get_settings
from ..database import get_db, next_sync_seq
from ..deps import current_user
from ..models import Photo, Reminder, User
from ..schemas import PhotoUploadResponse

router = APIRouter(prefix="/photos", tags=["photos"])
settings = get_settings()

ALLOWED_TYPES = {"image/jpeg", "image/png", "image/webp", "image/heic"}

# İçerik türünü uzantıdan değil, dosyanın kendi imzasından belirleriz:
# istemcinin bildirdiği Content-Type güvenilmez.
_MAGIC = {
    b"\xff\xd8\xff": "image/jpeg",
    b"\x89PNG\r\n\x1a\n": "image/png",
}


def _detect_type(head: bytes) -> str | None:
    for magic, content_type in _MAGIC.items():
        if head.startswith(magic):
            return content_type
    if head[4:12] in (b"ftypheic", b"ftypmif1"):
        return "image/heic"
    if head[:4] == b"RIFF" and head[8:12] == b"WEBP":
        return "image/webp"
    return None


def _path_for(user_id: uuid.UUID, photo_id: uuid.UUID) -> Path:
    # Kullanıcı başına klasör: tek dizinde yüz binlerce dosya birikmesin ve
    # hesap silindiğinde tek hamlede temizlensin.
    directory = settings.photo_dir / str(user_id)
    directory.mkdir(parents=True, exist_ok=True)
    return directory / str(photo_id)


@router.put("/{photo_id}", response_model=PhotoUploadResponse)
async def upload(
    photo_id: uuid.UUID,
    reminder_id: uuid.UUID,
    file: UploadFile = File(...),
    user: User = Depends(current_user),
    db: Session = Depends(get_db),
) -> PhotoUploadResponse:
    """Fotoğraf içeriğini yükler.

    Kimlik istemci tarafından üretilir; aynı kimlikle tekrar yükleme
    idempotenttir (ağ koptuğunda istemci güvenle yeniden dener).
    """
    reminder = db.scalar(
        select(Reminder).where(Reminder.id == reminder_id, Reminder.user_id == user.id)
    )
    if reminder is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Hatırlatma bulunamadı; önce senkronize edin",
        )

    existing = db.get(Photo, photo_id)
    if existing is not None and existing.user_id != user.id:
        # Başka bir kullanıcının kimliğinin üzerine yazılamaz.
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Erişim yok")

    if existing is None:
        stored = db.scalar(
            select(func.count())
            .select_from(Photo)
            .where(Photo.user_id == user.id, Photo.is_deleted.is_(False))
        )
        if (stored or 0) >= settings.max_photos_per_user:
            raise HTTPException(
                status_code=status.HTTP_413_REQUEST_ENTITY_TOO_LARGE,
                detail="Fotoğraf kotanız doldu",
            )

    # Akışı parça parça okuyup sınırı aşınca durur: 10 MB'lık sınır için
    # 2 GB'lık bir gövdeyi belleğe almayız.
    target = _path_for(user.id, photo_id)
    temp = target.with_suffix(".part")
    total = 0
    head = b""
    try:
        with temp.open("wb") as out:
            while chunk := await file.read(64 * 1024):
                total += len(chunk)
                if total > settings.max_photo_bytes:
                    raise HTTPException(
                        status_code=status.HTTP_413_REQUEST_ENTITY_TOO_LARGE,
                        detail="Fotoğraf 10 MB sınırını aşıyor",
                    )
                if len(head) < 16:
                    head += chunk[: 16 - len(head)]
                out.write(chunk)

        content_type = _detect_type(head)
        if content_type is None or content_type not in ALLOWED_TYPES:
            raise HTTPException(
                status_code=status.HTTP_415_UNSUPPORTED_MEDIA_TYPE,
                detail="Yalnızca JPEG, PNG, WebP veya HEIC yüklenebilir",
            )

        temp.replace(target)
    except HTTPException:
        temp.unlink(missing_ok=True)
        raise

    seq = next_sync_seq(db)
    if existing is None:
        existing = Photo(id=photo_id, user_id=user.id, reminder_id=reminder_id)
        db.add(existing)

    existing.reminder_id = reminder_id
    existing.content_type = content_type
    existing.size_bytes = total
    existing.has_content = True
    existing.is_deleted = False
    existing.sync_seq = seq
    db.commit()

    return PhotoUploadResponse(id=photo_id, size_bytes=total, cursor=seq)


@router.get("/{photo_id}")
def download(
    photo_id: uuid.UUID,
    user: User = Depends(current_user),
    db: Session = Depends(get_db),
) -> FileResponse:
    photo = db.get(Photo, photo_id)
    # Var olmayan ve başkasına ait fotoğraf aynı yanıtı verir: kimlik
    # numarasının kullanımda olup olmadığı sızdırılmaz.
    if photo is None or photo.user_id != user.id or photo.is_deleted:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Bulunamadı")

    path = _path_for(user.id, photo_id)
    if not path.exists():
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Bulunamadı")

    return FileResponse(path, media_type=photo.content_type)


@router.delete("/{photo_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete(
    photo_id: uuid.UUID,
    user: User = Depends(current_user),
    db: Session = Depends(get_db),
) -> None:
    photo = db.get(Photo, photo_id)
    if photo is None or photo.user_id != user.id:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Bulunamadı")

    # Mezar taşı bırakılır ki diğer cihazlar silmeyi öğrensin; ikili içerik
    # hemen kaldırılır çünkü yer kaplayan asıl şey odur.
    photo.is_deleted = True
    photo.has_content = False
    photo.sync_seq = next_sync_seq(db)
    db.commit()

    _path_for(user.id, photo_id).unlink(missing_ok=True)
