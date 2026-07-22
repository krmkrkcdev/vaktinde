FROM python:3.12-slim

# Python'un .pyc yazmasını ve çıktıyı tamponlamasını engelle: container
# günlükleri anında görünür.
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

WORKDIR /srv

RUN apt-get update \
    && apt-get install -y --no-install-recommends curl \
    && rm -rf /var/lib/apt/lists/*

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY app ./app

# Uygulama root olarak çalışmaz; fotoğraf volume'unun sahipliği compose
# tarafında bu kullanıcıya verilir.
RUN useradd --create-home --uid 10001 vaktinde \
    && mkdir -p /data/photos \
    && chown -R vaktinde:vaktinde /data
USER vaktinde

EXPOSE 8000

HEALTHCHECK --interval=30s --timeout=5s --start-period=20s --retries=3 \
    CMD curl -fsS http://127.0.0.1:8000/health || exit 1

CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000", "--proxy-headers", "--forwarded-allow-ips", "*"]
