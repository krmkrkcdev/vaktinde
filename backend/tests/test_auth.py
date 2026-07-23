import uuid


def _email() -> str:
    return f"t-{uuid.uuid4().hex[:8]}@ornek.com"


def test_kayit_token_dondurur(client):
    r = client.post("/auth/register", json={"email": _email(), "password": "Sifre12345"})
    assert r.status_code == 201
    body = r.json()
    assert body["access_token"] and body["refresh_token"]


def test_ayni_eposta_ikinci_kez_kaydedilemez(client):
    email = _email()
    client.post("/auth/register", json={"email": email, "password": "Sifre12345"})
    r = client.post("/auth/register", json={"email": email, "password": "Baska12345"})
    assert r.status_code == 409


def test_eposta_buyuk_kucuk_harf_duyarsiz(client):
    email = _email()
    client.post("/auth/register", json={"email": email, "password": "Sifre12345"})
    r = client.post(
        "/auth/login", json={"email": email.upper(), "password": "Sifre12345"}
    )
    assert r.status_code == 200


def test_kisa_sifre_reddedilir(client):
    r = client.post("/auth/register", json={"email": _email(), "password": "kisa"})
    assert r.status_code == 422


def test_yanlis_sifre_reddedilir(client):
    email = _email()
    client.post("/auth/register", json={"email": email, "password": "Sifre12345"})
    r = client.post("/auth/login", json={"email": email, "password": "YanlisSifre"})
    assert r.status_code == 401


def test_olmayan_hesap_ve_yanlis_sifre_ayni_yaniti_verir(client):
    email = _email()
    client.post("/auth/register", json={"email": email, "password": "Sifre12345"})

    yanlis_sifre = client.post(
        "/auth/login", json={"email": email, "password": "YanlisSifre"}
    )
    olmayan_hesap = client.post(
        "/auth/login", json={"email": _email(), "password": "Sifre12345"}
    )

    # Hesabın var olup olmadığı sızdırılmamalı.
    assert yanlis_sifre.status_code == olmayan_hesap.status_code == 401
    assert yanlis_sifre.json()["detail"] == olmayan_hesap.json()["detail"]


def test_cok_fazla_deneme_sonrasi_kilitlenir(client):
    email = _email()
    client.post("/auth/register", json={"email": email, "password": "Sifre12345"})

    for _ in range(10):
        client.post("/auth/login", json={"email": email, "password": "Yanlis"})

    r = client.post("/auth/login", json={"email": email, "password": "Sifre12345"})
    assert r.status_code == 429


def test_token_olmadan_korunan_uc_reddedilir(client):
    assert client.get("/auth/me").status_code == 401


def test_gecersiz_token_reddedilir(client):
    r = client.get("/auth/me", headers={"Authorization": "Bearer uydurma.token.dizesi"})
    assert r.status_code == 401


def test_me_kullaniciyi_dondurur(auth_client):
    r = auth_client.get("/auth/me")
    assert r.status_code == 200
    assert r.json()["email"] == auth_client.email


def test_refresh_yeni_token_verir(client):
    email = _email()
    tokens = client.post(
        "/auth/register", json={"email": email, "password": "Sifre12345"}
    ).json()

    r = client.post("/auth/refresh", json={"refresh_token": tokens["refresh_token"]})
    assert r.status_code == 200
    assert r.json()["access_token"]


def test_access_token_refresh_olarak_kullanilamaz(client):
    email = _email()
    tokens = client.post(
        "/auth/register", json={"email": email, "password": "Sifre12345"}
    ).json()

    r = client.post("/auth/refresh", json={"refresh_token": tokens["access_token"]})
    assert r.status_code == 401


def test_sifre_degisince_eski_tokenlar_gecersizlesir(auth_client):
    r = auth_client.post(
        "/auth/change-password",
        json={"current_password": "GucluSifre123", "new_password": "YeniSifre456"},
    )
    assert r.status_code == 200

    # Eski access token artık kabul edilmemeli.
    eski = auth_client.tokens["access_token"]
    assert (
        auth_client.get("/auth/me", headers={"Authorization": f"Bearer {eski}"}).status_code
        == 401
    )
    # Eski refresh token da düşmeli — çalınmış oturum devam edemez.
    assert (
        auth_client.post(
            "/auth/refresh",
            json={"refresh_token": auth_client.tokens["refresh_token"]},
        ).status_code
        == 401
    )


def _register(client) -> tuple[str, str]:
    """Yeni hesap açar; (e-posta, access token) döndürür."""
    email = _email()
    r = client.post(
        "/auth/register", json={"email": email, "password": "Sifre12345"}
    )
    return email, r.json()["access_token"]


def test_hesap_silinince_giris_yapilamaz(client):
    email, token = _register(client)

    r = client.request(
        "DELETE",
        "/auth/me",
        json={"password": "Sifre12345"},
        headers={"Authorization": f"Bearer {token}"},
    )
    assert r.status_code == 204

    # Aynı bilgilerle artık giriş yapılamamalı.
    r = client.post("/auth/login", json={"email": email, "password": "Sifre12345"})
    assert r.status_code == 401


def test_hesap_silme_yanlis_sifreyle_reddedilir(client):
    _, token = _register(client)

    r = client.request(
        "DELETE",
        "/auth/me",
        json={"password": "YanlisSifre1"},
        headers={"Authorization": f"Bearer {token}"},
    )
    assert r.status_code == 401

    # Hesap durmalı: token hâlâ geçerli.
    r = client.get("/auth/me", headers={"Authorization": f"Bearer {token}"})
    assert r.status_code == 200


def test_hesap_silinince_hatirlatmalari_da_gider(client):
    _, token = _register(client)
    headers = {"Authorization": f"Bearer {token}"}

    client.post(
        "/sync/push",
        headers=headers,
        json={
            "reminders": [
                {
                    "id": str(uuid.uuid4()),
                    "category_id": "bill",
                    "title": "Elektrik",
                    "due_date": "2026-09-01T00:00:00Z",
                    "lead_days": "1",
                    "notify_hour": 9,
                    "notify_minute": 0,
                    "repeat_interval": "monthly",
                    "is_archived": False,
                    "amount": 100.0,
                    "created_at": "2026-07-01T00:00:00Z",
                    "is_deleted": False,
                    "client_updated_at": "2026-07-01T00:00:00Z",
                }
            ]
        },
    )

    r = client.request(
        "DELETE", "/auth/me", json={"password": "Sifre12345"}, headers=headers
    )
    assert r.status_code == 204

    # Silinen hesabın tokeni artık hiçbir kaynağa erişememeli.
    assert client.get("/sync/changes?since=0", headers=headers).status_code == 401


def test_token_olmadan_hesap_silinemez(client):
    r = client.request("DELETE", "/auth/me", json={"password": "Sifre12345"})
    assert r.status_code == 401
