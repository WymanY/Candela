# 发布 Candela

打 tag 后由 GitHub Actions 出直装 DMG。产品首页见 [README.md](../README.md)。English: [releasing.en.md](releasing.en.md)

最新已发布版本是 **1.3.6**：<https://github.com/WymanY/Candela/releases/tag/1.3.6>，产物为 `Candela-1.3.6-arm64.dmg`。用户下载请用 evergreen 链接：<https://github.com/WymanY/Candela/releases/latest>

## 自动发布

推送一个版本 tag 后，`release` workflow 会打一份 Apple Silicon（arm64）的 DMG，并挂到对应的 GitHub Release。例如下一个补丁：

```sh
git tag 1.3.7
git push origin 1.3.7
```

产物是 `Candela-<version>-arm64.dmg`（店外直装 / Developer ID scheme，不是 Mac App Store）。把里面的 `Candela.app` 拖进「应用程序」。

## 手动跑 Actions

也可以在 Actions 里手动跑 `release`。留空 `tag` 只上传 Actions artifact；填写一个已有 tag（例如 `1.3.7`）则会为该 tag 创建或更新 GitHub Release。

## 签名和公证

发布必须完成 Developer ID 签名和 Apple 公证，否则 workflow 会停止且不会上传 Release。仓库 Secrets 需要：

- `APPLE_CERTIFICATE_P12_BASE64`
- `APPLE_CERTIFICATE_PASSWORD`
- `APPLE_NOTARY_KEY`
- `APPLE_NOTARY_KEY_ID`
- `APPLE_NOTARY_ISSUER_ID`

不要把这些值写进文档或提交进仓库。

这份直装包不是 Mac App Store 上架。App Store 列表也还没有发布。
