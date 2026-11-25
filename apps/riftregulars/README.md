# Rift Regulars

- Origin: https://riftregulars.agusbravo.dev
- Source: https://github.com/agustinbravop/rift-regulars
- Image: `ghcr.io/agustinbravop/riftregulars:latest` (Bun 1.4.5, UID/GID 1000).
- One replica, Recreate, requests 100m/192Mi, limits 500m/384Mi. The limit is an
  initial guardrail, not a measured production peak. Expensive routes share a
  two-request in-flight cap; profile routes allow 2/s, burst 4, and the Riot proxy
  allows 10/s, burst 20. Limits are host-wide, not spoofable client-IP quotas.
- `ORIGIN`, `HOST` and `PORT` are explicit; the local preview preload is not used.
  Bun's connection-idle timeout is disabled for queued Riot calls; Cloudflare and
  other proxy timeouts can still expire them. Graceful shutdown has a 30-second
  drain deadline and 40-second pod termination grace. Updates have downtime.
- The read-only root filesystem and read-only `/app/data/featured` mount prevent
  application writes. The PVC is local-path/RWO, not a backup.
- `sealedsecret.yaml` contains the namespace/name-bound encrypted Riot key.
  Rotate it with kubeseal, never plaintext YAML, image arguments or workflow env.
  A valid deployment does not imply the Riot development key has not expired.
- Snapshot updates are operator-only: mount the PVC read-write in a temporary
  nonroot pod, validate public envelopes with the source app's
  `parseFeaturedProfile`, transfer public/identity gzip files, then regenerate
  card metadata from destination file stat identities. Use atomic replacement,
  UID/GID 1000 and mode 0600; `fsGroupChangePolicy: OnRootMismatch` avoids changing
  those file modes on normal app mounts. Never transfer private checkpoints or
  import from Riot as part of deployment. Do not publicly expose the PVC.

## Initial rollout status (2026-11-25)

DNS was created before any app resources. The namespace and bound 128Mi PVC are
prepared. Nine validated public/identity snapshots plus destination-bound cards
were transferred (27 gzip files, 1,816,706 bytes); no private histories or
plaintext credential files were transferred. The temporary seed pod was deleted.
Manifest server dry-runs and SealedSecret decryption validation passed.

The app image build/publish succeeded in GitHub Actions run `45666953540`, from
source commit `e8d890cfbd676c2c0dbfc44480b3b5b8f724aeda`. **Application rollout is
blocked:** anonymous GHCR image access returns HTTP 401, and no durable registry
pull credential is configured. Do not apply the Argo Application until the
package is public or an appropriate sealed `read:packages` credential is added
for both Kubernetes and Image Updater. Never use an expiring Actions job token
as a deployment credential. GitHub has no supported public API to change package
visibility; the owner can change it in package settings:
https://github.com/users/agustinbravop/packages/container/riftregulars/settings

After resolving image access, push these homelab changes and apply only
`infrastructure/argocd/riftregulars-{app,imageupdater}.yaml`. Verify the rollout,
cert-manager certificate, HTTPS homepage, legal pages, all nine featured links,
same-origin error handling, read-only/private paths and pod/node memory before
calling deployment complete. The Gatus target is prepared but not yet published,
to avoid monitoring a service that has not rolled out.
