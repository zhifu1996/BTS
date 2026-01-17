# BTS Extract

从 Android target_files 包中提取镜像并生成设备指纹。

## 一键安装

```bash
curl -fsSL https://is.gd/skyworth_bts | bash
```

## 使用方法

```bash
bts_extract.sh <target_files.zip>
```

## 输出

- `bts_out/BTS_<时间戳>.zip` - 打包后的镜像文件 (boot/system/vendor/oem)
- `bts_out/fingerprint.txt` - 提取的设备指纹

## 依赖

| 依赖 | 类型 | 说明 |
|------|------|------|
| unzip | 必须 | 解压 target_files |
| zip | 必须 | 打包输出镜像 |
| python3 | 必须 | 解析 build.prop |
| simg2img | 可选 | 转换 sparse 镜像 |
| debugfs | 可选 | 读取 ext4 镜像内容 |

## 支持环境

- WSL1 / WSL2
- Ubuntu / Debian
- 其他基于 apt/dnf/yum/pacman/zypper 的 Linux 发行版
