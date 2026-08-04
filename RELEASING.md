# Releasing

All five GOAL API SDKs share one version number, so `1.4.0` means the same surface in
every language. Bump this repo in step with the others.

```bash
# 1. Bump the version in `pubspec.yaml`.
# 2. Add the CHANGELOG.md entry, then commit.
git commit -am "release 1.1.0"
git push

# 3. Tag it. The publish workflow refuses to run if the tag and the
#    committed version disagree.
git tag v1.1.0
git push --tags
```

To rehearse, run the `publish` workflow manually with `dry_run: true`: it builds,
validates and packs, then stops before uploading.

## One-time setup

### pub.dev automated publishing

1. Publish once by hand (`dart pub publish`) to claim the package name.
2. On pub.dev go to the package, then Admin, then Automated publishing, and enable
   GitHub Actions:
   - Repository: `goal-api/goal-api-dart`
   - Tag pattern: `v{{version}}`
   - Require the `pub.dev` environment.

pub.dev verifies the tag against the pubspec version, so `v1.1.0` must carry
`version: 1.1.0`.

## Package name

> The registry name in this repo is a placeholder pending confirmation. Check you own the
> namespace before the first publish; renaming after release is disruptive.

## Secrets

| Name | Environment | Needed for |
|---|---|---|
| `GOAL_API_KEY` | `live-api` | The live tests. They skip without it. |

No other secrets: pub.dev uses OIDC.
