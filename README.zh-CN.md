<p align="center">
  <img src="Design/Brand/Bilby-app-icon.png" width="128" alt="Bilby logo">
</p>

<h1 align="center">Bilby</h1>

<p align="center"><a href="README.md">English</a> | 简体中文</p>

<p align="center">给 Mac 状态栏留一点空白。</p>

原生 macOS 状态栏图标管理工具，按应用选择显示或隐藏。

当前仅在真机上适配过 **macOS 27.2 · Apple Silicon**，用于管理第三方应用图标。

## 使用

首次运行需在系统设置中授予辅助功能权限。点击状态栏中的 Bilby 图标即可管理。

## 从源码构建

需要完整的 Xcode 和 Python 3。

```sh
git clone https://github.com/Evenss/Bilby.git
cd Bilby
Tools/build.sh
```

将构建产物 `build/Bilby.app` 移入“应用程序”后打开。

[MIT 许可证](LICENSE) · [第三方声明](THIRD_PARTY_NOTICES.md) · [参与贡献](CONTRIBUTING.md)
