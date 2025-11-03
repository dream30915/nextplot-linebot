from flask import Flask
import os

app = Flask(__name__)

API_KEY = os.environ.get("MY_API_KEY", "example_key_123")
DB_URL = os.environ.get("DATABASE_URL", "postgres://user:pass@localhost:5432/dbname")
PORT = int(os.environ.get("PORT", 8080))

@app.route("/")
def home():
    return f"API_KEY={API_KEY}, DB={DB_URL}"

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=PORT)
