# GRAIN 交付内容

- `GRAIN-build63/GRAIN-unsigned.ipa`：1.1 (63)、arm64、未签名的可重签 IPA。
- `GRAIN-build63/GRAIN-unsigned.sha256`：对应 IPA 的 SHA-256 校验值。
- `GRAIN-prototype.html`：可直接在浏览器打开的交互原型，支持实时胶片预览、分组参数、导出面板和定位开关。
- `GRAIN/`：可导入 Xcode 的 iPhone SwiftUI 工程源码。
- `GRAIN-demo.jpg`：网页预览使用用户提供的 Sony ZV-E10 JPEG 样片。
- `GRAIN-preview.png`：1.1 单页编辑器预览。
- `GRAIN-icon.png`：新版动画相机概念主屏幕图标。
- `GRAIN-export-preview.png`：最高规格导出设置预览。

网页原型不能解码 Sony ARW，也不能真正写入 HEIC 元数据；这两部分由 Xcode 工程内的 Core Image RAW 与 ImageIO 管线实现。主页照片图库会通过 iCloud 原始资源导入 RAW。
