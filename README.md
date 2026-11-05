# 车辆数据 iOS App（CarDash）

从 Home Assistant 读取 6 项车辆数据，大字号卡片显示，前台每 2 秒刷新一次。

- 车速 `car_speed`（km/h）
- 转速 `car_rpm`（RPM）
- 油量 `car_fuel`（L）
- 电压 `car_voltage`（V）
- 水温 `car_water_temp`（°C）
- 总里程 `car_odometer`（km）

地址和令牌在 App 内填写，**不写进代码**（避免仓库公开后令牌泄露）。

---

## 一、上传到 GitHub

1. 在 GitHub 新建一个仓库（Private / Public 都行，Private 也能跑 Actions）。
2. 把这个文件夹里的这几样上传到**仓库根目录**：
   - `project.yml`
   - `Info.plist`
   - `Sources/`（里面的 `CarDashApp.swift`）
   - `.github/workflows/build.yml`

> `.github` 是隐藏文件夹。Mac 上在 Finder 按 `Cmd + Shift + .` 显示隐藏文件，再拖进去。
> 或者用 GitHub 网页：Add file → Create new file，文件名填 `.github/workflows/build.yml`，把内容粘进去。

## 二、云端编译

1. 打开仓库的 **Actions** 标签页
2. 左边选 **Build unsigned IPA** → 右边 **Run workflow** → 绿色按钮
3. 等 3~5 分钟变绿
4. 点进这次运行，页面底部 **Artifacts** → 下载 `CarDash-ipa`
5. 解压得到 **CarDash.ipa**（未签名）

## 三、签名安装

用你的轻松签导入 `CarDash.ipa`，用证书签名后安装即可。

> 免费 Apple ID 证书 **7 天过期**，过期重新签一次就行（IPA 不用重新编译，留着文件即可）。

## 四、首次打开

点右上角「设置」，填两项：

| 项 | 填什么 |
|---|---|
| Home Assistant 地址 | `http://你的HA地址:8123` |
| 长期访问令牌 | 你 HA 里生成的那个 `eyJhbGci...` |

保存关闭，卡片会自动开始刷新。顶部出现橙色提示说明连不上，看提示文字判断。

---

## 前提

数据来自 HA 的 6 个传感器。**车机端必须先跑通**——在 HA 里看 `sensor.carbridge_status` 是不是「已连接车机」。

如果车机还没上报，这个 App 打开只会显示 `--`。

## 改配色 / 布局

全部界面在 `Sources/CarDashApp.swift` 的 `CardView` 里，改字体大小、颜色、卡片圆角都在那几十行。
