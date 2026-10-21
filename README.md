# 噪音定位 NoiseMonitor

一个免费、无广告、不收费的 iOS 小工具：用 iPhone 麦克风找出家里**低频噪音的频率**，再拿着手机在房子里走动，找到它**最强的位置**。

## 能做什么

- **找频率**：实时分析 20–400 Hz，读出最明显的那个频率，精度约 0.1 Hz
- **锁定寻源**：锁定频率后只看它的强度，越靠近声源数值越大、震动越快
- **位置对比**：在各个位置测 10 秒取平均，按强弱排行
- **判断来源**：频率是否正好是 50 Hz 的整数倍、是否稳定、有没有谐波，帮你区分电器嗡声（变压器、配电）和机械（水泵、风机、压缩机）

声音只在手机上实时分析，不录音、不上传。

## 构建

需要 Xcode 和 [XcodeGen](https://github.com/yonaskolb/XcodeGen)：

```bash
xcodegen generate
open NoiseMonitor.xcodeproj
```

在 `project.yml` 里把 `DEVELOPMENT_TEAM` 换成你自己的 Team ID，然后装到 iPhone 上运行。模拟器拿不到 Mac 麦克风的声音，需要用真机。

## 局限

- 强度是相对值（手机麦克风没校准），同一部手机前后对比是准的
- iPhone 麦克风对 30 Hz 以下不灵敏，20 Hz 以下基本测不到
