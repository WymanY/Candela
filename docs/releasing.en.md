# Releasing Candela

Push a version tag and GitHub Actions publishes the direct DMG. The product homepage is [README.en.md](../README.en.md). 中文：[releasing.md](releasing.md)

The latest published release is **1.3.6**: <https://github.com/WymanY/Candela/releases/tag/1.3.6>, with `Candela-1.3.6-arm64.dmg`. Prefer the evergreen download URL: <https://github.com/WymanY/Candela/releases/latest>

## Automatic release

Push a version tag such as `1.3.7` and the `release` workflow builds an Apple Silicon (`arm64`) DMG and attaches it to a GitHub Release:

```sh
git tag 1.3.7
git push origin 1.3.7
```

The asset is `Candela-<version>-arm64.dmg` (direct / Developer ID scheme, not Mac App Store). Drag `Candela.app` into Applications.

## Manual Actions run

You can also run `release` from the Actions tab. Leave `tag` empty to upload an Actions artifact only, or enter an existing tag (for example `1.3.7`) to create or update that tag's GitHub Release.

## Signing and notarization

Publishing requires Developer ID signing and Apple notarization. The workflow stops before uploading a Release if either fails. Configure these repository secrets:

- `APPLE_CERTIFICATE_P12_BASE64`
- `APPLE_CERTIFICATE_PASSWORD`
- `APPLE_NOTARY_KEY`
- `APPLE_NOTARY_KEY_ID`
- `APPLE_NOTARY_ISSUER_ID`

Do not put the values in this document or commit them.

This is the direct GitHub download, not a Mac App Store upload. There is no shipping App Store listing yet.
