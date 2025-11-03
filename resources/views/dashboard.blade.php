<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>NextPlot Dashboard</title>
  <style>
    body { font-family: system-ui, -apple-system, Segoe UI, Roboto, Helvetica, Arial, sans-serif; margin: 2rem; }
    .card { border: 1px solid #e5e7eb; border-radius: 8px; padding: 1rem; max-width: 800px; }
    .muted { color: #6b7280; }
    pre { background: #f8fafc; padding: .75rem; border-radius: 6px; overflow:auto; }
  </style>
  </head>
<body>
  <h1>NextPlot Dashboard</h1>
  <p class="muted">Lightweight status page. For full operations, see scripts and Cloud Run console.</p>

  <div class="card">
    <h2>Health</h2>
    <pre>{{ json_encode($health, JSON_PRETTY_PRINT|JSON_UNESCAPED_UNICODE) }}</pre>
    <p class="muted">Source: <code>/api/health</code></p>
  </div>

  <p style="margin-top:1rem" class="muted">
    Useful links:
    <a href="{{ url('/api/health') }}" target="_blank">/api/health</a>
  </p>
</body>
</html>
