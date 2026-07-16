# CI/CD scripts

| Script | Purpose |
|--------|---------|
| `generate-version.sh` | Compute next `name_X.Y.Z[-devN]` git tag for dev/main |
| `bump-homebrew-vpn-node-builder.sh` | Update `novassist-ai/homebrew-tap` formula `url`/`sha256` for a `vpnb_X.Y.Z` tag |

## Homebrew formula bump (prod only)

Invoked by `.github/workflows/build-vpn-node-builder-prod.yml` after the
`vpnb_X.Y.Z` tag is pushed. Requires repository secret `HOMEBREW_TAP_TOKEN`
(classic or fine-grained PAT with `contents: write` on `novassist-ai/homebrew-tap`).

Dev builds publish `:dev` only; they do not bump the stable formula. Users refresh
containers with `vpnb update` / `vpnb-dev update`.
