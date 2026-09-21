# Homelab

## Static Site Deployment Template

For a static site named `<app>`:

1. In its repository, add a multi-stage `Dockerfile` that builds `dist/` and serves it with nginx.
2. Add a GitHub workflow that publishes `ghcr.io/agustinbravop/<app>:latest` on pushes to `main`.
3. Add `apps/<app>/{deployment,service,ingress,kustomization}.yaml`; route `<app>.agusbravo.dev` to port 80 with cert-manager TLS.
4. Add `infrastructure/argocd/<app>-{app,imageupdater}.yaml` and list both in `infrastructure/argocd/kustomization.yaml`.
5. Create the Cloudflare A record before deploying. Thereafter: push -> GHCR -> Image Updater -> ArgoCD rollout.
