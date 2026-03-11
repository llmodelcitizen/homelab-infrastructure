# Fix Prowlarr FlareSolverr Cloudflare Bypass

## Context

Prowlarr has a bug in its FlareSolverr integration: after FlareSolverr/Byparr solves a Cloudflare challenge and returns the page HTML + cookies, Prowlarr ignores the HTML body and makes a **second HTTP request** using the cookies. This second request gets 403'd because Cloudflare's `cf_clearance` cookie is bound to the browser's TLS fingerprint, which .NET's HttpClient can't replicate.

**Trace log proof** (`prowlarr.trace.txt`):
1. `IndexerHttpClient` GET linuxtracker.org → **403 Forbidden**
2. `FlareSolverr` detects Cloudflare, POSTs to Byparr → **200 OK** (265KB HTML)
3. `HttpClient` makes SECOND GET to linuxtracker.org with cookies → **403 Forbidden**
4. Reports "blocked by CloudFlare Protection"

The fix: use the HTML from step 2 directly, skip step 3.

## Changes

### 1. `FlareSolverr.cs`: patched source

Copy of `src/NzbDrone.Core/IndexerProxies/FlareSolverr/FlareSolverr.cs` from Prowlarr v2.3.0.5236 with the `PostResponse` method fixed. The change replaces:

```csharp
// OLD: makes a second request that gets 403'd
var finalResponse = _httpClient.Execute(newRequest);
return finalResponse;
```

With:

```csharp
// NEW: use FlareSolverr's response body directly
if (result.Solution.Response.IsNotNullOrWhiteSpace())
{
    return new HttpResponse(
        response.Request,
        response.Headers,
        response.Cookies,
        result.Solution.Response,
        response.ElapsedTime,
        HttpStatusCode.OK);
}

// Fallback: if FlareSolverr returned no body, try cookies (original behavior)
var finalResponse = _httpClient.Execute(newRequest);
return finalResponse;
```

Also fixed the existing bug on the error line that referenced `response.StatusCode` instead of `flaresolverrResponse.StatusCode`.

### 2. `Dockerfile`: multi-stage build

- **Stage 1** (`dotnet/sdk:8.0`): Clone Prowlarr at `v2.3.0.5236`, overlay patched `FlareSolverr.cs`, build `Prowlarr.Core.csproj`
- **Stage 2** (`linuxserver/prowlarr:latest`): Copy `Prowlarr.Core.dll` and `Prowlarr.Common.dll` from stage 1

Build notes discovered during implementation:
- Must pass `-p:RunAnalyzers=false` to avoid 507 StyleCop SA1200 errors (analyzer warnings treated as errors)
- Output goes to `_output/net8.0/` not `bin/Release/net8.0/` (custom output path in project)
- Must copy both `Prowlarr.Core.dll` AND `Prowlarr.Common.dll` because local build stamps different assembly versions than Prowlarr's CI, causing `FileNotFoundException` at runtime

### 3. `docker-compose.yml`: build prowlarr from Dockerfile

Replaced `image: lscr.io/linuxserver/prowlarr:latest` with `build: ./prowlarr-patch`.

### 4. `prowlarr-setup`: Byparr (FlareSolverr proxy) configuration

After the existing "Add Radarr as application" step, added:
1. Create a `byparr` tag
2. Add FlareSolverr indexer proxy pointing to `http://byparr:8191` with that tag

### 5. `README.md`: documentation

- Noted prowlarr uses a custom build
- Updated Byparr section: now configured automatically by `prowlarr-setup`
- Added note: indexers that need Cloudflare bypass must be tagged with `byparr`

## Verification

```bash
# Rebuild the patched Prowlarr image
cd services/arr && ./arrctl build prowlarr

# Restart the stack
./arrctl up -d

# Run setup (after radarr-setup)
./prowlarr-setup

# Test: Add LinuxTracker indexer with "byparr" tag
# Should succeed without Cloudflare error

# Check byparr logs for successful solve
./arrctl logs byparr --tail 20
```
