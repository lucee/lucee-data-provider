# Skill (Cloud Run app)

This is the Lucee container that used to serve `skill.lucee.io` and `skills.lucee.io` on Google Cloud
Run. It is kept in the repo while that service is still running; do not deploy it to Cloud Run any
more.

Live traffic is served by the Cloudflare Worker in [`../skill-worker`](../skill-worker):
`skill.lucee-services.com`, `skill.lucee.io` and `skills.lucee.io`.

For local use only:

```sh
docker compose up -d
# http://localhost:8055/
```
