
# IPTV自动更新器

每周二自动更新的IPTV播放列表，已适配udpxy代理。

## 使用方法

1. 在OpenWRT/LEDE路由器上安装脚本
2. 修改脚本中的`UDPXY_HOST`和`UDPXY_PORT`为你的udpxy地址
3. 设置定时任务每周二执行

## 自动更新

本项目使用GitHub Actions每周二自动更新IPTV列表：
- 原始源：成都电信IPTV
- 更新频率：每周二
- 自动替换udpxy地址
- 自动优化EPG源顺序

## 文件说明

- `scripts/iptv_updater.sh` - 更新脚本
- `output/iptv.m3u8` - 处理后的播放列表
- `last_update.log` - 更新日志

## 手动更新

可以在GitHub仓库的Actions标签页手动触发更新。
