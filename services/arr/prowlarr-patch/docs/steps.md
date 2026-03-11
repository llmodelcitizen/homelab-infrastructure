# Execution Steps

Step-by-step record of what was done to implement the Prowlarr FlareSolverr patch.

## 1. Diagnosed the bug

Read Prowlarr trace logs showing the three-step failure:
1. Prowlarr's `IndexerHttpClient` GETs an indexer URL → 403 (Cloudflare)
2. FlareSolverr/Byparr solves the challenge → 200 OK with full HTML body
3. Prowlarr ignores the body, makes a **second** GET with the returned cookies → 403 again

The root cause: `cf_clearance` cookies are bound to the solver's TLS fingerprint. .NET's HttpClient has a different fingerprint, so the cookie is rejected.

## 2. Fetched the original source

Downloaded `FlareSolverr.cs` from the Prowlarr v2.3.0.5236 tag:
```
https://raw.githubusercontent.com/Prowlarr/Prowlarr/v2.3.0.5236/src/NzbDrone.Core/IndexerProxies/FlareSolverr/FlareSolverr.cs
```

Also checked `Prowlarr.Core.csproj` to confirm the target framework (`net8.0`).

## 3. Created `prowlarr-patch/FlareSolverr.cs`

Copied the original file and made two changes to the `PostResponse` method:

**Fix 1: use FlareSolverr's response body directly:**

Before the existing `_httpClient.Execute(newRequest)` call, added a check: if FlareSolverr returned a response body, construct an `HttpResponse` from it and return immediately, skipping the second HTTP request.

**Fix 2: error message bug:**

Changed `response.StatusCode` to `flaresolverrResponse.StatusCode` in the error throw, so the reported status code is from the FlareSolverr response, not the original Cloudflare-blocked response.

## 4. Created `prowlarr-patch/Dockerfile`

Multi-stage Docker build:
- **Stage 1:** `dotnet/sdk:8.0`, clones Prowlarr at the pinned tag, overlays the patched file, builds `Prowlarr.Core.csproj`
- **Stage 2:** `linuxserver/prowlarr:latest`, copies the compiled DLLs over the originals

## 5. Build attempt 1: StyleCop analyzer failures

```
507 Error(s), all SA1200 "Using directive should appear within a namespace declaration"
```

Prowlarr's project treats StyleCop warnings as errors. Fixed by adding `-p:RunAnalyzers=false` to the `dotnet build` command. We only need a compiled DLL, not lint compliance.

## 6. Build attempt 2: wrong output path

```
"/src/src/NzbDrone.Core/bin/Release/net8.0/Prowlarr.Core.dll": not found
```

The build log showed output going to `/src/_output/net8.0/Prowlarr.Core.dll`. Prowlarr's project has a custom `OutputPath`. Updated the `COPY --from=builder` path.

## 7. Build attempt 3: assembly version mismatch

```
System.IO.FileNotFoundException: Could not load file or assembly 'Prowlarr.Common, Version=10.0.0.38886'
```

Our local build stamps a different assembly version on `Prowlarr.Common.dll` than Prowlarr's CI does. The compiled `Prowlarr.Core.dll` references our version, but the base image has the CI version. Fixed by copying both `Prowlarr.Core.dll` and `Prowlarr.Common.dll` from the build stage.

## 8. Build attempt 4: success

Image built and Prowlarr started cleanly:
```
[Info] Microsoft.Hosting.Lifetime: Now listening on: http://[::]:9696
```

## 9. Updated `docker-compose.yml`

Replaced `image: lscr.io/linuxserver/prowlarr:latest` with `build: ./prowlarr-patch`.

## 10. Updated `prowlarr-setup`

Added Byparr configuration after the existing Radarr application setup:
1. Create a `byparr` tag via the Prowlarr API
2. Add a FlareSolverr indexer proxy pointing to `http://byparr:8191` with that tag

## 11. Updated `README.md`

- Marked Prowlarr as "custom build" in the services table
- Added Byparr proxy to the `prowlarr-setup` script description
- Replaced the manual Byparr setup steps with documentation of the patch and tagging instructions

## 12. Deployed and verified

```bash
./arrctl build prowlarr    # built patched image
./arrctl up -d             # started stack
./prowlarr-setup           # configured auth, Radarr app, Byparr proxy
```

Added LinuxTracker indexer with the `byparr` tag. Byparr logs confirmed a successful solve:
```
INFO: Done https://linuxtracker.org/... in 7.13s
INFO: 172.24.0.4:57838 - "POST /v1 HTTP/1.1" 200 OK
```

## 13. Committed and pushed

```
Patch Prowlarr to fix FlareSolverr Cloudflare bypass
```
