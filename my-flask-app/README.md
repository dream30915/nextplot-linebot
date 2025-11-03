# my-flask-app (Cloud Run ready)

Minimal Flask service ready to deploy from VS Code with Cloud Code.

## Files
- `app.py` — simple Flask app reading env vars
- `requirements.txt` — pinned deps
- `.env` — default values for MY_API_KEY, DATABASE_URL, PORT
- `Dockerfile` — 3.12 slim + gunicorn on port 8080
- `cloudrun.yaml` — Knative Service; Cloud Code substitutes `${VAR}` from `.env`

## Deploy from VS Code (Cloud Code)
1. Install the "Cloud Code" extension and sign in to Google Cloud.
2. Replace `YOUR_PROJECT_ID` in `cloudrun.yaml` with your GCP project id (or let Cloud Code prompt you).
3. Open `cloudrun.yaml` and run "Deploy to Cloud Run".
4. Pick project and region; wait for build + push + deploy.
5. Open the service URL to see `API_KEY=..., DB=...`.

## CLI alternative
If you already built and pushed an image:

```powershell
# Replace YOUR_PROJECT_ID and REGION
$env:MY_API_KEY = "example_key_123"
$env:DATABASE_URL = "postgres://user:pass@localhost:5432/dbname"
$env:PORT = "8080"

gcloud run deploy my-flask-app `
  --image gcr.io/YOUR_PROJECT_ID/my-flask-app `
  --region asia-southeast1 `
  --allow-unauthenticated `
  --set-env-vars "MY_API_KEY=$env:MY_API_KEY,DATABASE_URL=$env:DATABASE_URL,PORT=$env:PORT"
```

## Local run
```powershell
# Windows PowerShell
$env:PORT = "8080"
python -m venv .venv; .\.venv\Scripts\Activate.ps1
pip install -r requirements.txt
python app.py
```
