## Local folder instead of S3 

create folders here for downloads, extensions, bundles

add them to your `.env` file in the root directory of the project, to work and test locally


```env
S3_CORE_ROOT=/var/local_s3/lucee_downloads/
S3_EXTENSIONS_ROOT=/var/local_s3/lucee_ext/
S3_BUNDLES_ROOT=/var/local_s3/lucee_bundles/
```

Under `local_s3`

- create `lucee_downloads` and place a few sample Lucee full `.jar` files
- create `lucee_ext` place some sample extension `.lex` files
- under `lucee_downloads` create `express-templates` and download the files listed at https://update.lucee.org/rest/update/provider/expressTemplates into that dir