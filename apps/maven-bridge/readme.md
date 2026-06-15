# Extension Provider Maven Bridge

A small Lucee Docker app that exposes a **Maven repository layout** backed by one or more legacy Lucee **REST extension providers** (`extension.lucee.org`, ForgeBox, or your own update server).

Use it while migrating Lucee 6-style extension providers to the Lucee 7+ Maven GroupId model.

## Why

Lucee 7 discovers extensions by:

1. Listing artifacts under a GroupId (HTML scrape, or group-level `maven-metadata.xml` on newer Lucee)
2. Reading `{artifactId}/maven-metadata.xml` for available versions
3. Downloading `{artifactId}-{version}.lex` from the repository

This bridge translates the REST provider API into that Maven layout.

## Quick start

```sh
cd apps/maven-bridge
docker compose up -d --build
```

Repository base URL: `http://localhost:8856/`

Health check: `http://localhost:8856/health.cfm`

Flush cache and resync from providers: `http://localhost:8856/health.cfm?flush=true`

Default group indexes:

| GroupId | Provider | URL |
|---------|----------|-----|
| `io.forgebox` | ForgeBox | `http://localhost:8856/io/forgebox/` |
| `org.lucee` | extension.lucee.org | `http://localhost:8856/org/lucee/` |

Example artifact metadata: `http://localhost:8856/org/lucee/redis-extension/maven-metadata.xml`

> On first request the bridge syncs Maven metadata files under `{webroot}/{groupId path}/`. The container listens on **`PORT` (default `8080`)** for Google Cloud Run — the entrypoint rewrites Tomcat's default port 8888 to match.

## Configure Lucee 7 to use the bridge

Point release repositories at the bridge (server or web context):

```json
{
  "extensionProviders": ["io.forgebox", "org.lucee"],
  "maven": {
    "repository": ["http://localhost:8856/"]
  }
}
```

Environment variables:

```
LUCEE_EXTENSIONPROVIDERS=io.forgebox,org.lucee
LUCEE_MVN_REPO_RELEASES=http://localhost:8856/
```

Or in Docker for a Lucee container on the same compose network:

```
LUCEE_MVN_REPO_RELEASES=http://maven-bridge:8080/
LUCEE_EXTENSIONPROVIDERS=io.forgebox,org.lucee
```

## Bridge environment

| Variable | Default | Description |
|----------|---------|-------------|
| `EXTENSION_PROVIDERS` | ForgeBox → `io.forgebox`, extension.lucee.org → `org.lucee` | Comma-separated `providerUrl\|groupId` pairs, or JSON array |
| `EXTENSION_PROVIDER` | — | Legacy single-provider mode (use with `GROUP_ID`) |
| `GROUP_ID` | — | Legacy single-provider Maven groupId |
| `CACHE_TTL_MINUTES` | `60` | How long to cache each provider index before automatic refresh |
| `TIMEOUT` | `300` | HTTP timeout (seconds) for provider requests and request timeout |
| `PORT` | `8080` | HTTP listen port (Tomcat); set by Google Cloud Run |
| `LUCEE_ADMIN_PASSWORD` | — | Lucee administrator password |

### Multiple providers

Pipe-separated pairs (recommended in Docker Compose):

```yaml
environment:
  EXTENSION_PROVIDERS: "https://www.forgebox.io|io.forgebox,https://extension.lucee.org|org.lucee"
```

JSON array:

```yaml
environment:
  EXTENSION_PROVIDERS: >-
    [
      {"provider":"https://www.forgebox.io","groupId":"io.forgebox"},
      {"provider":"https://extension.lucee.org","groupId":"org.lucee"}
    ]
```

Legacy single provider:

```yaml
environment:
  EXTENSION_PROVIDER: "http://update:8888"
  GROUP_ID: "org.lucee"
```

## Architecture

```
www/
  Application.cfc                         → config, sync repo files, route /org/* and /io/*
  index.cfm                               → root info
  org/lucee/                              → generated Maven tree (gitignored)
  io/forgebox/                            → generated Maven tree (gitignored)
  components/org/lucee/mavenbridge/
    BridgeRegistry.cfc                    → routes paths to provider/groupId mappings
    BridgeSupport.cfc                     → fetch REST index, sync + build responses
    proxy/BridgeProxy.cfc                 → HTTP dispatch for dynamic paths (.lex)
```

Data flow:

```mermaid
flowchart LR
  Lucee7[Lucee 7 Admin / Deploy]
  Bridge[Maven Bridge]
  Provider[REST Extension Provider]
  CDN[Extension CDN]

  Lucee7 -->|"GET /org/lucee/ (HTML)"| Bridge
  Lucee7 -->|"GET /io/forgebox/ (HTML)"| Bridge
  Lucee7 -->|"GET .../{artifactId}/maven-metadata.xml"| Bridge
  Lucee7 -->|"HEAD/GET .../*.lex"| Bridge
  Bridge -->|"GET /rest/extension/provider/info"| Provider
  Bridge -->|"302 to full/{id}"| Provider
  Provider --> CDN
```

## Group-level `maven-metadata.xml`

The bridge serves `{groupId path}/maven-metadata.xml` as a Lucee-specific artifact index (not standard Maven plugin metadata, but the same filename and layout convention):

```xml
<metadata>
  <groupId>org.lucee</groupId>
  <artifacts>
    <artifact>
      <artifactId>redis-extension</artifactId>
      <latest>3.0.0.51</latest>
      <release>3.0.0.51</release>
    </artifact>
  </artifacts>
  <lastUpdated>20260612153000</lastUpdated>
</metadata>
```

Older Lucee versions can keep using the HTML group index. Newer Lucee (LDEV-6405) can add a `GroupMetadataExtensionLister` that reads `<artifacts>` here and falls back to HTML scraping when the file is absent.

## Limitations

- Snapshot metadata is simplified (enough for basic `-SNAPSHOT` resolution)
- `.lex` downloads redirect through the REST provider's `/full/{id}` endpoint rather than proxying bytes
- ArtifactIds are derived from provider filenames (`redis.extension-1.2.3.lex` → `redis-extension`)

## Related

- [`apps/ai`](../ai/) — Docker template this app follows
- [Extension Provider recipe](https://docs.lucee.org/recipes/extension-provider.html)
- [Maven Based Extensions](https://docs.lucee.org/recipes/maven-based-extensions.html)
