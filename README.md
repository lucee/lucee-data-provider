# Lucee Data provider

This repo contains the application code for the following services used by Lucee

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
UPDATE_PROVIDER=http://127.0.0.1:8889/rest/update/provider/
UPDATE_PROVIDER_INT=http://update:8888/rest/update/provider/ # internal docker networking
EXTENSION_PROVIDER=http://127.0.0.1:8889/rest/extension/provider/
EXTENSION_PROVIDER_INT=http://update:8888/rest/extension/provider/ # internal docker networking
DOWNLOADS_URL=http://download:8888/
```

Create folders under `local_s3`

- in `lucee_downloads` place a few sample Lucee full jars
- in `lucee_ext` place some sample extension lex files

The run `docker compose up`

Running locally, the downloads page is at http://127.0.0.1:8888/
and the update provider is http://127.0.0.1:8889/rest/update/provider/list?extended=true