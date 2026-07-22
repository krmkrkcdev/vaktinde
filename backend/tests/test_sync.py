import uuid
from datetime import datetime, timedelta, timezone


def make_reminder(**overrides) -> dict:
    now = datetime.now(timezone.utc)
    payload = {
        "id": str(uuid.uuid4()),
        "category_id": "bill",
        "title": "Elektrik faturası",
        "note": None,
        "due_date": (now + timedelta(days=30)).isoformat(),
        "lead_days": "30,7,1",
        "notify_hour": 9,
        "notify_minute": 0,
        "repeat_interval": "monthly",
        "is_archived": False,
        "amount": 1250.5,
        "created_at": now.isoformat(),
        "is_deleted": False,
        "client_updated_at": now.isoformat(),
    }
    payload.update(overrides)
    return payload


def test_push_ve_changes_gidis_donusu(auth_client):
    reminder = make_reminder()
    r = auth_client.post("/sync/push", json={"reminders": [reminder]})
    assert r.status_code == 200
    assert r.json()["rejected_ids"] == []

    r = auth_client.get("/sync/changes", params={"since": 0})
    assert r.status_code == 200
    body = r.json()
    assert len(body["reminders"]) == 1
    donen = body["reminders"][0]
    assert donen["title"] == "Elektrik faturası"
    assert donen["amount"] == 1250.5
    assert donen["lead_days"] == "30,7,1"
    assert body["cursor"] > 0


def test_imlec_yalnizca_yeni_degisiklikleri_dondurur(auth_client):
    auth_client.post("/sync/push", json={"reminders": [make_reminder()]})
    cursor = auth_client.get("/sync/changes", params={"since": 0}).json()["cursor"]

    # İmleçten sonra değişiklik yok.
    assert auth_client.get("/sync/changes", params={"since": cursor}).json()[
        "reminders"
    ] == []

    auth_client.post("/sync/push", json={"reminders": [make_reminder(title="Su")]})
    yeni = auth_client.get("/sync/changes", params={"since": cursor}).json()
    assert len(yeni["reminders"]) == 1
    assert yeni["reminders"][0]["title"] == "Su"


def test_eski_degisiklik_reddedilir(auth_client):
    now = datetime.now(timezone.utc)
    reminder = make_reminder(client_updated_at=now.isoformat(), title="Yeni")
    auth_client.post("/sync/push", json={"reminders": [reminder]})

    # Aynı kayıt için daha eski bir düzenleme gelirse yok sayılmalı.
    eski = dict(reminder)
    eski["title"] = "Eski"
    eski["client_updated_at"] = (now - timedelta(hours=1)).isoformat()

    r = auth_client.post("/sync/push", json={"reminders": [eski]})
    assert r.json()["rejected_ids"] == [reminder["id"]]

    kayitli = auth_client.get("/sync/changes", params={"since": 0}).json()["reminders"][0]
    assert kayitli["title"] == "Yeni"


def test_daha_yeni_degisiklik_uygulanir(auth_client):
    now = datetime.now(timezone.utc)
    reminder = make_reminder(client_updated_at=now.isoformat(), title="Eski")
    auth_client.post("/sync/push", json={"reminders": [reminder]})

    yeni = dict(reminder)
    yeni["title"] = "Guncel"
    yeni["client_updated_at"] = (now + timedelta(hours=1)).isoformat()

    r = auth_client.post("/sync/push", json={"reminders": [yeni]})
    assert r.json()["rejected_ids"] == []

    kayitli = auth_client.get("/sync/changes", params={"since": 0}).json()["reminders"][0]
    assert kayitli["title"] == "Guncel"


def test_silme_mezar_tasi_olarak_yayilir(auth_client):
    reminder = make_reminder()
    auth_client.post("/sync/push", json={"reminders": [reminder]})

    silinmis = dict(reminder)
    silinmis["is_deleted"] = True
    silinmis["client_updated_at"] = datetime.now(timezone.utc).isoformat()
    auth_client.post("/sync/push", json={"reminders": [silinmis]})

    donen = auth_client.get("/sync/changes", params={"since": 0}).json()["reminders"]
    assert len(donen) == 1
    assert donen[0]["is_deleted"] is True


def test_kullanicilar_birbirinin_verisini_goremez(client):
    def kayit_ol():
        email = f"u-{uuid.uuid4().hex[:8]}@ornek.com"
        tokens = client.post(
            "/auth/register", json={"email": email, "password": "Sifre12345"}
        ).json()
        return {"Authorization": f"Bearer {tokens['access_token']}"}

    birinci = kayit_ol()
    ikinci = kayit_ol()

    client.post(
        "/sync/push",
        json={"reminders": [make_reminder(title="Gizli")]},
        headers=birinci,
    )

    gorunen = client.get("/sync/changes", params={"since": 0}, headers=ikinci).json()
    assert gorunen["reminders"] == []


def test_kimlik_dogrulamasiz_senkronizasyon_reddedilir(client):
    assert client.get("/sync/changes").status_code == 401
    assert client.post("/sync/push", json={"reminders": []}).status_code == 401
