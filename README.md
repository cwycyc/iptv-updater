# IPTV自动更新器

每周二自动更新的IPTV播放列表，适配本地udpxy代理，可通过GitHub Pages访问。

## 功能特性

- ✅ 每周二自动更新IPTV列表
- ✅ 自动替换地址为本地udpxy代理
- ✅ 调整EPG源顺序优化体验
- ✅ 生成美观的网页界面
- ✅ 支持GitHub Pages部署

## 使用方法

1. **配置参数**：编辑`config.json`文件：
   ```json
   {
       "udpxy_host": "你的路由器IP",
       "udpxy_port": "你的udpxy端口",
       "output_dir": "docs",
       "source_urls": ["源URL1", "源URL2"]
   }
