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

The initial app image build/publish succeeded in GitHub Actions run `45666953540`,
from source commit `e8d890cfbd676c2c0dbfc44480b3b5b8f724aeda`. The owner made the
repository and GHCR package public; anonymous image-manifest access was then
verified as HTTP 200. No registry credential or expiring Actions job token is
needed in the cluster.

To register the app, push the homelab changes and apply only
`infrastructure/argocd/riftregulars-{app,imageupdater}.yaml`. Verify the rollout,
cert-manager certificate, HTTPS homepage, legal pages, all nine featured links,
same-origin error handling, read-only/private paths and pod/node memory before
calling deployment complete. Gatus currently uses its existing ConfigMap rather
than a registered Argo Application. Apply only `apps/gatus/configmap.yaml` in the
`gatus` namespace after checking the diff; it reloads the target without a pod
restart.

## Verified deployment (2026-11-25)

- Live URL: **https://riftregulars.agusbravo.dev**.
- GitHub Actions run `45669110696` successfully built/published source revision
  `dc3f63316423226612127510ac7ec062a7b14dc2`.
- Running image matches the public `latest` OCI index
  `sha256:eb7d82fcfb3fb6679c68d95ed05f3be44ae340f2bbf975af0ee2a59144c24d46`.
  Image Updater pinned this digest through Argo; one ready replica, zero restarts.
- Argo reported Synced/Healthy. The cert-manager certificate is Ready and expires
  on 2027-02-23. Public HTTPS verification succeeded.
- Homepage SSR exposes all nine featured links; all nine profiles returned
  encounter tables. Both legal pages are prerendered assets. The expected contact
  exists in origin HTML; Cloudflare obfuscates email links at the edge.
- Snapshot verification found 27 files with UID 1000/mode 0600, matching card
  stamps and 6,041 indexed account-games. Both root and snapshot mounts reject
  writes. No private checkpoints exist on the PVC.
- Static assets and probe returned 200; filesystem, environment, source/build
  internals and checkpoint URL attempts returned 404.
- API origin/content-type/input checks returned 403/415/400 JSON errors.
  A bounded invalid-input burst produced 400/429 responses, without Riot calls.
  One discovery-only lookup succeeded with HTTP 200; no match IDs or details
  were requested. Key validity is only verified at that moment.
- Gatus loaded the target and passed status 200, response time under two seconds,
  and certificate validity over seven days, without an unrelated pod rollout.
- Final local check had zero errors/warnings; all 116 Node tests and the Bun
  production build passed. No browser or sustained-load test was performed.
- Point-in-time metrics after verification: pod 33Mi/1m; node 3,147Mi (82%)/466m;
  Prometheus MemAvailable about 387Mi. These are not peak measurements or a memory
  budget. Node RAM remains tight; watch usage and OOM/restart events under real
  traffic. Recreate updates cause downtime, Riot development keys expire, and all
  visitors share the Riot quota.
