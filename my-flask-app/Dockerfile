FROM python:3.12-slim

WORKDIR /app

# Prevents Python from writing pyc files to disk and buffering stdout/stderr
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

COPY requirements.txt ./
RUN pip install --no-cache-dir -r requirements.txt

COPY . .

EXPOSE 8080

# Run via gunicorn for production
CMD ["gunicorn", "-b", "0.0.0.0:8080", "app:app"]
