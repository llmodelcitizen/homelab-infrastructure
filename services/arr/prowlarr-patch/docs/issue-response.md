# Draft Response to Prowlarr/Prowlarr#2561

---

This is a real bug in Prowlarr's FlareSolverr integration, not a FlareSolverr/Byparr configuration issue. I've root-caused it and have a working fix.

## Root Cause

In `FlareSolverr.cs` → `PostResponse()`, after FlareSolverr/Byparr successfully solves the Cloudflare challenge and returns the full page HTML + cookies, Prowlarr **discards the response body** and makes a second HTTP request using only the returned cookies:

```csharp
// FlareSolverr.cs, PostResponse()
InjectCookies(newRequest, result);

// This second request gets 403'd:
var finalResponse = _httpClient.Execute(newRequest);
return finalResponse;
```

This second request fails because Cloudflare's `cf_clearance` cookie is bound to the **TLS fingerprint** of the browser that solved the challenge (FlareSolverr/Byparr's headless Chrome). .NET's `HttpClient` has a completely different TLS fingerprint, so Cloudflare rejects the cookie and returns 403.

This affects **every** indexer that uses Cloudflare's managed challenge, not just YTS. The "workaround" of trying different URLs only works when the alternate URL doesn't trigger a challenge at all.

@ilike2burnthing - the issue isn't that there's no challenge to solve. The trace logs clearly show FlareSolverr solving successfully (200 OK, full HTML body returned). The problem is that Prowlarr throws away that solved response and retries with cookies that can't work from a different TLS stack.

## Fix

The solved HTML body from FlareSolverr already contains everything Prowlarr needs. The fix is to use it directly instead of making the second request:

```csharp
InjectCookies(newRequest, result);

// Use FlareSolverr's response body directly - a second HTTP request would
// get 403'd because cf_clearance is bound to the solver's TLS fingerprint
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

There's also a minor existing bug on the error handling line: it reports `response.StatusCode` (the original Cloudflare 403) instead of `flaresolverrResponse.StatusCode` (the actual FlareSolverr response status).

## Verification

I've deployed this as a patched DLL overlay on `linuxserver/prowlarr:latest` (v2.3.0.5236) using Byparr. Tested with LinuxTracker (Cloudflare-protected). Byparr solves the challenge in ~7s and Prowlarr uses the response directly: no second request, no 403.

Happy to submit a PR if the team is open to it.
