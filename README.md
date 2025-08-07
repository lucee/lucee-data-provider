# Lucee "Data provider"

This repo contains the application code for the following services:

* https://download.lucee.org
* https://update.lucee.org
* https://extension.lucee.org

https://luceeserver.atlassian.net/issues/?jql=labels%20%3D%20%22updates%22

# Local Development

By default, the data provider is configured to work in production.

Create an `.env file` with the following settings to work locally.

```env
ALLOW_RELOAD=true
S3_CORE_ROOT=/var/local_s3/lucee_downloads/
S3_EXTENSIONS_ROOT=/var/local_s3/lucee_ext/
S3_BUNDLES_ROOT=/var/local_s3/lucee_bundles/
UPDATE_PROVIDER=http://update:8888/rest/update/provider
EXTENSION_PROVIDER=http://update:8888/rest/extension/provider
```

Create folders under `local_s3` and place a few sample Lucee full jars in `lucee_downloads`, and extension lex files in `lucee_ext`

The run `docker compose up`