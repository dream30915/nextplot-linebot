# Cloud Run Alerts Templates

This folder contains examples for:
- Log-based metrics (5xx error count, latency buckets)
- Alert policies for 5xx rate and high latency

Use these as a starting point and adapt the project, region, and service names.

## Quickstart

1) Create a 5xx request-count alert using Cloud Run metric:

```powershell
# Replace variables
$PROJECT = "<your-project-id>"
$SERVICE  = "nextplot-linebot"
$REGION   = "asia-southeast1"

# Suggestion: Use built-in request_count metric with 5xx filter
# See: https://cloud.google.com/run/docs/monitoring/metrics
# Create alert from JSON
 gcloud alpha monitoring policies create --project $PROJECT --policy-from-file .\alert-policy-5xx.json
```

2) Create a latency alert (p95 over threshold):

```powershell
 gcloud alpha monitoring policies create --project $PROJECT --policy-from-file .\alert-policy-latency.json
```

## Notes
- These JSONs demonstrate standard Monitoring metric-threshold alerts.
- For custom log-based metrics, prefer Cloud Run native metrics (request_count, request_latencies) when available.
- You can create and tune policies via Console then export JSON to version-control here.
