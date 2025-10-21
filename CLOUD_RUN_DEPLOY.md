# Cloud Run Deployment Guide

## Overview

Google Cloud Run is the **canonical and only** deployment target for the NextPlot LINE Bot. This project uses Cloud Run exclusively for production deployments.

**Note:** Azure Web App is **not used** in this project. All deployment workflows and infrastructure are focused on Google Cloud Run only.

## Deployment Methods

### Method 1: Using Cloud Build (Recommended)

```bash
gcloud builds submit --config cloudbuild.yaml
```

This will:
1. Build the Docker image
2. Push it to Google Container Registry
3. Deploy to Cloud Run automatically

### Method 2: Direct Deployment

```bash
gcloud run deploy nextplot-linebot --source .
```

## Cloud Run Configuration

The service is configured with:
- **Region:** asia-southeast1
- **Platform:** managed
- **Max Instances:** 3
- **Timeout:** 300 seconds
- **CPU:** 1 vCPU
- **Memory:** 512Mi
- **Authentication:** Allow unauthenticated (for LINE webhook)

## Environment Variables

The following environment variables are configured via Cloud Run:
- `APP_ENV=production`
- `APP_DEBUG=false`
- `SUPABASE_BUCKET_NAME=nextplot`

Secrets are managed through Google Secret Manager:
- `APP_KEY`
- `LINE_CHANNEL_ACCESS_TOKEN`
- `LINE_CHANNEL_SECRET`
- `SUPABASE_URL`
- `SUPABASE_SERVICE_ROLE`

## Monitoring

Check deployment logs:
```bash
gcloud run logs read nextplot-linebot --limit 50
```

Check service status:
```bash
gcloud run services describe nextplot-linebot --region asia-southeast1
```

## Free Tier Limits

Google Cloud Run provides:
- 2M requests/month
- 360,000 GB-seconds of memory/month
- 180,000 vCPU-seconds/month

## Additional Resources

- [DEPLOYMENT.md](DEPLOYMENT.md) - Full deployment and failover guide
- [README.md](README.md) - Project overview and quick start
- [cloudbuild.yaml](cloudbuild.yaml) - Cloud Build configuration file
