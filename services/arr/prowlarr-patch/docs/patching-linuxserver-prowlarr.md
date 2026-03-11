# Patching the LinuxServer Prowlarr Docker Image

This documents every step, failure, and fix involved in overlaying a patched Prowlarr build onto the `lscr.io/linuxserver/prowlarr:latest` Docker image.

## Background

**A note on naming:** [Byparr](https://github.com/ThePhaseless/Byparr) is a drop-in replacement for [FlareSolverr](https://github.com/FlareSolverr/FlareSolverr) that implements the same API. Prowlarr's code and UI refer to "FlareSolverr" everywhere (the proxy type, the C# class, the settings contract) because Prowlarr only knows about the FlareSolverr API. In this stack we run Byparr as the actual solver, but Prowlarr treats it identically. The bug and fix apply to both.

Prowlarr's FlareSolverr integration has a bug ([#2561](https://github.com/Prowlarr/Prowlarr/issues/2561)): after the solver (Byparr in our case) solves a Cloudflare challenge and returns the page HTML + cookies, Prowlarr ignores the HTML body and makes a second HTTP request using the cookies. This second request gets 403'd because Cloudflare's `cf_clearance` cookie is bound to the solver's TLS fingerprint, which .NET's HttpClient can't replicate.

The fix is a small change to `FlareSolverr.cs`: use the solved response body directly instead of re-requesting. The challenge is getting this fix into the LinuxServer Prowlarr Docker image without building the entire image from scratch.

## Approach 1: Compile-in-Docker DLL Overlay (the "hacks" branch)

### Idea

Clone the Prowlarr source inside a Docker build stage, overlay the patched file, compile just `Prowlarr.Core.dll`, and copy it into the base image.

### Dockerfile

```dockerfile
FROM mcr.microsoft.com/dotnet/sdk:8.0 AS builder
ARG PROWLARR_TAG=v2.3.0.5236
WORKDIR /src
RUN git clone --depth 1 --branch ${PROWLARR_TAG} https://github.com/Prowlarr/Prowlarr.git .
COPY FlareSolverr.cs src/NzbDrone.Core/IndexerProxies/FlareSolverr/FlareSolverr.cs
RUN dotnet build src/NzbDrone.Core/Prowlarr.Core.csproj -c Release

FROM lscr.io/linuxserver/prowlarr:latest
COPY --from=builder /src/src/NzbDrone.Core/bin/Release/net8.0/Prowlarr.Core.dll \
    /app/prowlarr/bin/Prowlarr.Core.dll
```

### Failure 1: StyleCop analyzer errors (507 errors)

```
error SA1200: Using directive should appear within a namespace declaration
```

The project has StyleCop analyzers configured to treat warnings as errors. Every `using` directive at the top of every file is a violation.

**Fix:** Add `-p:RunAnalyzers=false` to the build command. We only need a compiled DLL, not lint compliance.

### Failure 2: Wrong output path

```
"/src/src/NzbDrone.Core/bin/Release/net8.0/Prowlarr.Core.dll": not found
```

The build log showed output going to `/src/_output/net8.0/Prowlarr.Core.dll`. Prowlarr's `Directory.Build.props` sets a custom `OutputPath` of `_output/`.

**Fix:** Update the `COPY --from=builder` path to `/src/_output/net8.0/Prowlarr.Core.dll`.

### Failure 3: Assembly version mismatch

```
System.IO.FileNotFoundException: Could not load file or assembly
'Prowlarr.Common, Version=10.0.0.38886'
```

Our local build stamps a different assembly version on `Prowlarr.Common.dll` than Prowlarr's CI system does. The compiled `Prowlarr.Core.dll` references our version number, but the `Prowlarr.Common.dll` already in the base image has the CI's version number. .NET's assembly loader requires exact version matches.

**Fix:** Copy both `Prowlarr.Core.dll` AND `Prowlarr.Common.dll` from the build stage, so their versions are consistent with each other.

### Final working Dockerfile (hacks approach)

```dockerfile
FROM mcr.microsoft.com/dotnet/sdk:8.0 AS builder
ARG PROWLARR_TAG=v2.3.0.5236
WORKDIR /src
RUN git clone --depth 1 --branch ${PROWLARR_TAG} https://github.com/Prowlarr/Prowlarr.git .
COPY FlareSolverr.cs src/NzbDrone.Core/IndexerProxies/FlareSolverr/FlareSolverr.cs
RUN dotnet build src/NzbDrone.Core/Prowlarr.Core.csproj -c Release -p:RunAnalyzers=false

FROM lscr.io/linuxserver/prowlarr:latest
COPY --from=builder /src/_output/net8.0/Prowlarr.Core.dll \
    /src/_output/net8.0/Prowlarr.Common.dll \
    /app/prowlarr/bin/
```

### Drawbacks

- Slow builds (~15s compile + full SDK image download on first run)
- Fragile: must copy every DLL that has a version mismatch
- The SDK stage is 2GB+ and clones the full Prowlarr repo each time

This approach was preserved on the `prowlarr-hacks` branch.

## Approach 2: Pre-built tarball overlay (the clean approach)

### Idea

Build the full Prowlarr project on a separate machine using the official build process, publish as a GitHub release tarball, and overlay onto the base image. No SDK needed at build time.

### Building Prowlarr (done on a separate machine)

The Prowlarr project was built from the [`fix/flaresolverr-use-response-body`](https://github.com/quaintops/Prowlarr/tree/fix/flaresolverr-use-response-body) branch following their documented build process:

```bash
# Install .NET SDK 8.0.405 (version specified in global.json)
# Install Node.js 20.x
# Enable yarn via corepack

# Build frontend
yarn install
yarn build --env production

# Build backend for all platforms
dotnet msbuild -restore src/Prowlarr.sln -p:Configuration=Debug -p:Platform=Posix -t:PublishAllRids
```

The `PublishAllRids` target produces builds for all runtime identifiers: `linux-x64`, `linux-musl-x64`, `linux-arm64`, etc. These were packaged as tarballs and uploaded as a [GitHub release](https://github.com/quaintops/Prowlarr/releases/tag/v2.3.0.5236-flaresolverr-fix).

### Failure 4: Wrong runtime identifier (glibc vs musl)

First attempt used `Prowlarr.develop.2.3.0.5236.linux-x64.tar.gz`:

```
/bin/bash: line 1: /app/prowlarr/bin/Prowlarr: cannot execute: required file not found
```

The `linux-x64` build is linked against glibc (`ld-linux-x86-64.so.2`), but the LinuxServer Prowlarr image is based on Alpine Linux, which uses musl libc. The dynamic linker doesn't exist in the container.

**How to diagnose:** Check what linker the binary needs:
```bash
docker run --rm --entrypoint /bin/bash arr-prowlarr:latest \
    -c "strings /app/prowlarr/bin/Prowlarr | grep ld-linux"
# Output: /lib64/ld-linux-x86-64.so.2

docker run --rm --entrypoint /bin/bash arr-prowlarr:latest \
    -c "ls -la /lib64/ld-linux-x86-64.so.2"
# Output: No such file or directory
```

**Fix:** Use `linux-musl-x64` build instead.

### Failure 5: Full tarball overlay breaks .NET runtime (framework-dependent vs self-contained)

After switching to the musl build, used `ADD` to extract the entire tarball:

```dockerfile
FROM lscr.io/linuxserver/prowlarr:latest
ADD Prowlarr.develop.2.3.0.5236.linux-musl-x64.tar.gz /app/prowlarr/bin/
```

Result:
```
Framework: 'Microsoft.NETCore.App', version '8.0.12' (x64)
.NET location: /app/prowlarr/bin/
No frameworks were found.
```

**Root cause:** The tarball contains `Prowlarr.runtimeconfig.json` which overwrote the base image's version. The two files differ critically:

Base image (self-contained, runtime bundled in the image):
```json
{
  "runtimeOptions": {
    "includedFrameworks": [
      {"name": "Microsoft.NETCore.App", "version": "8.0.12"}
    ]
  }
}
```

Our build (framework-dependent, expects installed runtime):
```json
{
  "runtimeOptions": {
    "frameworks": [
      {"name": "Microsoft.NETCore.App", "version": "8.0.12"}
    ]
  }
}
```

The key difference is `includedFrameworks` (self-contained) vs `frameworks` (framework-dependent). When our tarball overwrites the runtimeconfig, .NET switches from looking for the bundled runtime to looking for an installed runtime, which doesn't exist in the Alpine container.

**Fix:** Don't overlay the entire tarball. Use a multi-stage build to extract the tarball, then selectively copy only the Prowlarr application DLLs and executable, preserving the base image's runtimeconfig and bundled .NET runtime.

### Failure 6: UI not found (404 on web interface)

After the selective DLL copy, Prowlarr started successfully but returned 404 for the web UI:

```
[Warn] IndexHtmlMapper: File /app/prowlarr/bin/../UI/index.html not found
```

**Root cause:** Our compiled `Prowlarr` executable resolves the UI directory as `../UI/` relative to its own location (`/app/prowlarr/bin/`), which means it looks at `/app/prowlarr/UI/`. But the LinuxServer image places the UI at `/app/prowlarr/bin/UI/`.

The original image's `Prowlarr` binary was compiled by the LinuxServer CI with a different `AppFolderInfo` resolution that knows the UI is in the same directory. Our build (from Prowlarr's source) assumes the standard layout where UI is one level up.

**Fix:** Add a symlink:
```dockerfile
RUN ln -s /app/prowlarr/bin/UI /app/prowlarr/UI
```

### Final working Dockerfile

```dockerfile
FROM alpine:latest AS extract
ADD Prowlarr.develop.2.3.0.5236.linux-musl-x64.tar.gz /build/

FROM lscr.io/linuxserver/prowlarr:latest
COPY --from=extract /build/Prowlarr.Common.dll /build/Prowlarr.Core.dll \
    /build/Prowlarr.dll /build/Prowlarr.Host.dll /build/Prowlarr.Http.dll \
    /build/Prowlarr.Mono.dll /build/Prowlarr.Api.V1.dll \
    /build/Prowlarr.SignalR.dll /build/Prowlarr.Windows.dll \
    /build/Prowlarr /app/prowlarr/bin/
RUN ln -s /app/prowlarr/bin/UI /app/prowlarr/UI
```

**Why this works:**
- Stage 1 (`alpine`): Extracts the tarball into `/build/` (Alpine is tiny and has tar built in)
- Stage 2 (`linuxserver/prowlarr`): Copies only the Prowlarr application binaries, leaving untouched:
  - `Prowlarr.runtimeconfig.json` (keeps self-contained runtime mode)
  - All .NET runtime DLLs (bundled framework)
  - `UI/` directory (frontend assets)
  - All third-party NuGet dependency DLLs (already in the base image, same versions)
- Symlink fixes the UI path resolution difference between our build and the LinuxServer layout

**Build time:** ~2 seconds (just layer extraction and file copy, no compilation).

## LinuxServer Prowlarr image internals

Key facts discovered during this process:

| Property | Value |
|---|---|
| Base OS | Alpine Linux (musl libc) |
| .NET deployment | Self-contained (`includedFrameworks` in runtimeconfig) |
| Binary location | `/app/prowlarr/bin/` |
| UI location | `/app/prowlarr/bin/UI/` |
| Init system | s6-overlay |
| Entrypoint | `s6-applyuidgid /app/prowlarr/bin/Prowlarr` |
| Runtime identifier | `linux-musl-x64` |
| .NET version | 8.0.12 |
| Prowlarr version | 2.3.0.5236 (as of `latest` tag, Feb 2026) |

## Files copied from the patched build

Only Prowlarr's own assemblies and the native executable are copied. Everything else (third-party NuGet packages, .NET runtime, frontend UI) comes from the base image.

| File | Purpose |
|---|---|
| `Prowlarr` | Native executable (ELF, musl-linked) |
| `Prowlarr.dll` | Main application assembly |
| `Prowlarr.Common.dll` | Shared utilities (must match Core's reference) |
| `Prowlarr.Core.dll` | Core logic (**contains the FlareSolverr fix**) |
| `Prowlarr.Host.dll` | Web host / Kestrel setup |
| `Prowlarr.Http.dll` | HTTP pipeline |
| `Prowlarr.Mono.dll` | POSIX platform support |
| `Prowlarr.Api.V1.dll` | REST API controllers |
| `Prowlarr.SignalR.dll` | Real-time notifications |
| `Prowlarr.Windows.dll` | Windows platform support (unused on Linux but referenced) |
