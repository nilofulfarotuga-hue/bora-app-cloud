FROM python:3.12-slim
RUN apt-get update && apt-get install -y --no-install-recommends ffmpeg gcc \
    && rm -rf /var/lib/apt/lists/*
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt && apt-get purge -y gcc && apt-get autoremove -y
COPY central.py .
USER nobody
CMD ["python", "-u", "central.py"]
