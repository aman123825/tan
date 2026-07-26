# HearBloom research API — production image (J1 deployment readiness).
#
#   docker build -t hearbloom-api .
#   docker run -p 8000:8000 -v hearbloom-data:/app/data \
#     -e HEARBLOOM_AUTH_KEY=... -e HEARBLOOM_CONTENT_KEY=... hearbloom-api
#
# Research software — not a medical device. See docs/DEPLOYMENT.md.
FROM python:3.12-slim

WORKDIR /app

# Install dependencies first so code changes reuse the cached layer.
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Only what the API needs at runtime (no Flutter app, no tests).
COPY services/ services/
COPY packages/ packages/
COPY ml/ ml/
COPY protocols/ protocols/
COPY stimuli/ stimuli/

ENV HEARBLOOM_DB=/app/data/hearbloom.db
RUN mkdir -p /app/data

EXPOSE 8000
HEALTHCHECK --interval=30s --timeout=5s \
  CMD python -c "import urllib.request;urllib.request.urlopen('http://127.0.0.1:8000/health')"

CMD ["uvicorn", "services.api.main:app", "--host", "0.0.0.0", "--port", "8000", "--workers", "2"]
