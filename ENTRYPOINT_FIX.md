# Docker Entrypoint Fix - Pull Request Summary

## Changes Made

This PR fixes the Cloud Build failures by ensuring `docker-entrypoint.sh` is properly included in the build context and Docker image.

### Files Modified

1. **`.gcloudignore`** - Simplified and explicitly includes `docker-entrypoint.sh`
   - Removed overly broad exclusion patterns
   - Added explicit `!docker-entrypoint.sh` to ensure it's never ignored

2. **`Dockerfile`** - Switched to PHP-FPM base image for better Cloud Run compatibility
   - Changed from `php:8.2-apache` to `php:8.1-fpm`
   - Simplified build process
   - Ensures `docker-entrypoint.sh` is copied and made executable
   - Properly sets ENTRYPOINT to use the script

3. **`docker-entrypoint.sh`** - Updated to start PHP-FPM
   - Changed final command from `apache2-foreground` to `php-fpm`
   - Maintains all Laravel initialization logic (config cache, route cache, etc.)

## Why These Changes?

### Previous Issues

- Cloud Build was failing with "file not found" errors for `docker-entrypoint.sh`
- The `.gcloudignore` file had complex patterns that were accidentally excluding the entrypoint script
- Dockerfile placement of COPY commands was causing build context issues

### Solution

- **Simplified `.gcloudignore`**: Minimal exclusions with explicit inclusion of the entrypoint
- **Streamlined Dockerfile**: Clean PHP-FPM setup that copies the entrypoint early and ensures it's executable
- **Updated entrypoint**: Changed to work with PHP-FPM instead of Apache

## Testing Instructions

After merging this PR, re-run the Cloud Build:

```powershell
# From the repository root
gcloud builds submit --config cloudbuild.yaml --async
```

Monitor the build status:

```powershell
.\check-build-status.ps1 -Follow
```

Once the build succeeds (Status: SUCCESS), test the Cloud Run endpoint:

```powershell
# Test health endpoint
Invoke-WebRequest -Uri "https://nextplot-linebot-656d4rnjja-as.a.run.app/api/health"

# Should return 200 OK with JSON response
```

Then switch the LINE webhook to Cloud Run:

```powershell
.\switch-webhook.ps1 -Target cloudrun
```

## Expected Outcome

✅ Cloud Build completes successfully  
✅ Docker image includes `docker-entrypoint.sh` and uses it as ENTRYPOINT  
✅ Laravel application starts with proper runtime configuration  
✅ Cloud Run service responds with 200 OK (not 500 errors)  
✅ LINE webhook verification succeeds  

## Rollback Plan

If issues persist, the Vercel deployment remains fully functional as a backup:

```powershell
.\switch-webhook.ps1 -Target vercel
```

## Commit Details

**Commit**: `4209457`  
**Message**: Fix: Ensure docker-entrypoint.sh is included in build and switch to PHP-FPM  
**Branch**: master  
**Files Changed**: 3 (`.gcloudignore`, `Dockerfile`, `docker-entrypoint.sh`)  
**Lines**: +27 / -91 (net reduction of 64 lines)
