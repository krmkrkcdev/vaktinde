from functools import lru_cache
from pathlib import Path

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    """Ortam değişkenlerinden okunan yapılandırma.

    Üretimde tüm sırlar .env dosyasından veya container ortamından gelir;
    kod içinde varsayılan sır bulunmaz.
    """

    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    # Zorunlu: en az 32 karakter rastgele dize.
    # Üretmek için:  openssl rand -hex 32
    jwt_secret: str

    database_url: str = "postgresql+psycopg://vaktinde:vaktinde@db:5432/vaktinde"

    access_token_minutes: int = 30
    # Kullanıcı yılda birkaç kez giriş yapsın diye uzun tutuldu.
    refresh_token_days: int = 180

    photo_dir: Path = Path("/data/photos")
    max_photo_bytes: int = 10 * 1024 * 1024  # 10 MB

    # Bir kullanıcı hesabının toplam fotoğraf kotası.
    max_photos_per_user: int = 500

    # Aynı e-posta/IP için art arda başarısız giriş sınırı.
    login_max_attempts: int = 10
    login_window_seconds: int = 300

    cors_origins: str = ""

    @property
    def cors_origin_list(self) -> list[str]:
        return [o.strip() for o in self.cors_origins.split(",") if o.strip()]


@lru_cache
def get_settings() -> Settings:
    return Settings()  # type: ignore[call-arg]
