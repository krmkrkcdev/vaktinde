import uuid

from fastapi import APIRouter, Depends, Query
from sqlalchemy import select
from sqlalchemy.orm import Session

from ..database import get_db, next_sync_seq
from ..deps import current_user
from ..models import Photo, Reminder, User
from ..schemas import (
    ChangesResponse,
    PhotoMeta,
    PushRequest,
    PushResponse,
    ReminderPayload,
)

router = APIRouter(prefix="/sync", tags=["sync"])

# Tek çekimde dönen azami kayıt sayısı. İstemci `has_more` doğruyken
# imleci ilerleterek tekrar çağırır.
PAGE_SIZE = 200


def _to_payload(row: Reminder) -> ReminderPayload:
    return ReminderPayload(
        id=row.id,
        category_id=row.category_id,
        title=row.title,
        note=row.note,
        due_date=row.due_date,
        lead_days=row.lead_days,
        notify_hour=row.notify_hour,
        notify_minute=row.notify_minute,
        repeat_interval=row.repeat_interval,
        is_archived=row.is_archived,
        amount=row.amount,
        created_at=row.created_at,
        is_deleted=row.is_deleted,
        client_updated_at=row.client_updated_at,
    )


@router.post("/push", response_model=PushResponse)
def push(
    body: PushRequest,
    user: User = Depends(current_user),
    db: Session = Depends(get_db),
) -> PushResponse:
    """İstemcideki yerel değişiklikleri sunucuya yazar.

    Çakışma çözümü son yazan kazanır: gelen kaydın `client_updated_at` değeri
    saklanandan eski ise yazma atlanır ve kimlik `rejected_ids` içinde döner.
    İstemci bir sonraki çekimde sunucu sürümünü alır.
    """
    rejected: list[uuid.UUID] = []
    cursor = 0

    incoming_ids = [r.id for r in body.reminders]
    existing = {
        row.id: row
        for row in db.scalars(
            select(Reminder).where(
                Reminder.user_id == user.id, Reminder.id.in_(incoming_ids)
            )
        )
    }

    for payload in body.reminders:
        row = existing.get(payload.id)

        if row is not None and row.client_updated_at >= payload.client_updated_at:
            rejected.append(payload.id)
            continue

        seq = next_sync_seq(db)
        cursor = max(cursor, seq)

        if row is None:
            row = Reminder(id=payload.id, user_id=user.id, created_at=payload.created_at)
            db.add(row)

        row.category_id = payload.category_id
        row.title = payload.title
        row.note = payload.note
        row.due_date = payload.due_date
        row.lead_days = payload.lead_days
        row.notify_hour = payload.notify_hour
        row.notify_minute = payload.notify_minute
        row.repeat_interval = payload.repeat_interval
        row.is_archived = payload.is_archived
        row.amount = payload.amount
        row.is_deleted = payload.is_deleted
        row.client_updated_at = payload.client_updated_at
        row.sync_seq = seq

        # Hatırlatma silindiyse fotoğrafları da mezar taşına çevrilir; aksi
        # hâlde diğer cihazlar sahipsiz fotoğraflar görürdü.
        if payload.is_deleted:
            for photo in db.scalars(
                select(Photo).where(
                    Photo.user_id == user.id,
                    Photo.reminder_id == payload.id,
                    Photo.is_deleted.is_(False),
                )
            ):
                photo.is_deleted = True
                photo.sync_seq = next_sync_seq(db)
                cursor = max(cursor, photo.sync_seq)

    db.commit()
    return PushResponse(rejected_ids=rejected, cursor=cursor)


@router.get("/changes", response_model=ChangesResponse)
def changes(
    since: int = Query(0, ge=0, description="Son alınan imleç; ilk çekimde 0"),
    user: User = Depends(current_user),
    db: Session = Depends(get_db),
) -> ChangesResponse:
    """`since` imlecinden sonraki tüm değişiklikleri döndürür."""
    reminders = list(
        db.scalars(
            select(Reminder)
            .where(Reminder.user_id == user.id, Reminder.sync_seq > since)
            .order_by(Reminder.sync_seq)
            .limit(PAGE_SIZE)
        )
    )
    photos = list(
        db.scalars(
            select(Photo)
            .where(Photo.user_id == user.id, Photo.sync_seq > since)
            .order_by(Photo.sync_seq)
            .limit(PAGE_SIZE)
        )
    )

    has_more = len(reminders) == PAGE_SIZE or len(photos) == PAGE_SIZE

    # İmleç, iki listenin ortak güvenli sınırıdır. Sayfa dolmuşsa daha ileri
    # gitmeyiz; aksi hâlde henüz gönderilmemiş kayıtların üzerinden atlanır.
    seqs = [r.sync_seq for r in reminders] + [p.sync_seq for p in photos]
    if has_more:
        cursor = min(
            (reminders[-1].sync_seq if len(reminders) == PAGE_SIZE else max(seqs)),
            (photos[-1].sync_seq if len(photos) == PAGE_SIZE else max(seqs)),
        )
        reminders = [r for r in reminders if r.sync_seq <= cursor]
        photos = [p for p in photos if p.sync_seq <= cursor]
    else:
        cursor = max(seqs) if seqs else since

    return ChangesResponse(
        reminders=[_to_payload(r) for r in reminders],
        photos=[PhotoMeta.model_validate(p) for p in photos],
        cursor=cursor,
        has_more=has_more,
    )
