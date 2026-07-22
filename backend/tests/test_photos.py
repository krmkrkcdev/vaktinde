import uuid

from .test_sync import make_reminder

# Geçerli en küçük JPEG başlığı — içerik türü algılamayı tetikler.
JPEG = b"\xff\xd8\xff\xe0" + b"\x00" * 128
PNG = b"\x89PNG\r\n\x1a\n" + b"\x00" * 128


def _reminder_ekle(auth_client) -> str:
    reminder = make_reminder()
    auth_client.post("/sync/push", json={"reminders": [reminder]})
    return reminder["id"]


def test_fotograf_yukle_ve_indir(auth_client):
    reminder_id = _reminder_ekle(auth_client)
    photo_id = str(uuid.uuid4())

    r = auth_client.put(
        f"/photos/{photo_id}",
        params={"reminder_id": reminder_id},
        files={"file": ("belge.jpg", JPEG, "image/jpeg")},
    )
    assert r.status_code == 200, r.text
    assert r.json()["size_bytes"] == len(JPEG)

    indirilen = auth_client.get(f"/photos/{photo_id}")
    assert indirilen.status_code == 200
    assert indirilen.content == JPEG


def test_yuklenen_fotograf_changes_icinde_gorunur(auth_client):
    reminder_id = _reminder_ekle(auth_client)
    photo_id = str(uuid.uuid4())
    auth_client.put(
        f"/photos/{photo_id}",
        params={"reminder_id": reminder_id},
        files={"file": ("belge.png", PNG, "image/png")},
    )

    body = auth_client.get("/sync/changes", params={"since": 0}).json()
    assert len(body["photos"]) == 1
    assert body["photos"][0]["id"] == photo_id
    assert body["photos"][0]["reminder_id"] == reminder_id
    assert body["photos"][0]["has_content"] is True


def test_ayni_kimlikle_tekrar_yukleme_idempotent(auth_client):
    reminder_id = _reminder_ekle(auth_client)
    photo_id = str(uuid.uuid4())

    for _ in range(3):
        r = auth_client.put(
            f"/photos/{photo_id}",
            params={"reminder_id": reminder_id},
            files={"file": ("belge.jpg", JPEG, "image/jpeg")},
        )
        assert r.status_code == 200

    body = auth_client.get("/sync/changes", params={"since": 0}).json()
    assert len(body["photos"]) == 1


def test_resim_olmayan_dosya_reddedilir(auth_client):
    reminder_id = _reminder_ekle(auth_client)
    r = auth_client.put(
        f"/photos/{uuid.uuid4()}",
        params={"reminder_id": reminder_id},
        # Uzantı ve Content-Type resim diyor ama içerik değil.
        files={"file": ("kotu.jpg", b"#!/bin/sh\nrm -rf /", "image/jpeg")},
    )
    assert r.status_code == 415


def test_olmayan_hatirlatmaya_fotograf_eklenemez(auth_client):
    r = auth_client.put(
        f"/photos/{uuid.uuid4()}",
        params={"reminder_id": str(uuid.uuid4())},
        files={"file": ("belge.jpg", JPEG, "image/jpeg")},
    )
    assert r.status_code == 404


def test_baskasinin_fotografi_indirilemez(client):
    def kayit_ol():
        email = f"u-{uuid.uuid4().hex[:8]}@ornek.com"
        tokens = client.post(
            "/auth/register", json={"email": email, "password": "Sifre12345"}
        ).json()
        return {"Authorization": f"Bearer {tokens['access_token']}"}

    sahip = kayit_ol()
    yabanci = kayit_ol()

    reminder = make_reminder()
    client.post("/sync/push", json={"reminders": [reminder]}, headers=sahip)
    photo_id = str(uuid.uuid4())
    client.put(
        f"/photos/{photo_id}",
        params={"reminder_id": reminder["id"]},
        files={"file": ("belge.jpg", JPEG, "image/jpeg")},
        headers=sahip,
    )

    assert client.get(f"/photos/{photo_id}", headers=yabanci).status_code == 404


def test_silinen_fotograf_indirilemez_ve_mezar_tasi_birakir(auth_client):
    reminder_id = _reminder_ekle(auth_client)
    photo_id = str(uuid.uuid4())
    auth_client.put(
        f"/photos/{photo_id}",
        params={"reminder_id": reminder_id},
        files={"file": ("belge.jpg", JPEG, "image/jpeg")},
    )

    assert auth_client.delete(f"/photos/{photo_id}").status_code == 204
    assert auth_client.get(f"/photos/{photo_id}").status_code == 404

    photos = auth_client.get("/sync/changes", params={"since": 0}).json()["photos"]
    assert photos[0]["is_deleted"] is True


def test_hatirlatma_silinince_fotograflari_da_silinir(auth_client):
    reminder = make_reminder()
    auth_client.post("/sync/push", json={"reminders": [reminder]})
    photo_id = str(uuid.uuid4())
    auth_client.put(
        f"/photos/{photo_id}",
        params={"reminder_id": reminder["id"]},
        files={"file": ("belge.jpg", JPEG, "image/jpeg")},
    )

    from datetime import datetime, timezone

    silinmis = dict(reminder)
    silinmis["is_deleted"] = True
    silinmis["client_updated_at"] = datetime.now(timezone.utc).isoformat()
    auth_client.post("/sync/push", json={"reminders": [silinmis]})

    photos = auth_client.get("/sync/changes", params={"since": 0}).json()["photos"]
    assert photos[0]["is_deleted"] is True
