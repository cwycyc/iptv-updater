#!/bin/bash
# IPTV自动更新脚本 - 保留前次文件版
# 仅当成功下载时才覆盖M3U8文件

set -e

# 配置参数
UDPXY_HOST="192.168.10.2"
UDPXY_PORT="4022"
UDPXY_ADDR="http://${UDPXY_HOST}:${UDPXY_PORT}"

# 源URL列表
SOURCES=(
    "https://raw.githubusercontent.com/0987363/iptv-chengdu/master/home/iptv.m3u8"
    "https://cdn.jsdelivr.net/gh/0987363/iptv-chengdu@master/home/iptv.m3u8"
    "https://ghproxy.com/https://raw.githubusercontent.com/0987363/iptv-chengdu/master/home/iptv.m3u8"
)

# 文件路径
OUTPUT_FILE="docs/iptv.m3u8"
TEMP_FILE="/tmp/iptv_temp.m3u8"
BACKUP_FILE="/tmp/iptv_backup.m3u8"

# 创建目录
mkdir -p docs

# 备份当前文件
if [ -f "$OUTPUT_FILE" ]; then
    cp "$OUTPUT_FILE" "$BACKUP_FILE"
fi

# 尝试下载
for url in "${SOURCES[@]}"; do
    echo "尝试下载: $url"
    
    if curl -s -L -o "$TEMP_FILE" --connect-timeout 30 --max-time 60 "$url"; then
        # 验证文件
        if head -n 1 "$TEMP_FILE" 2>/dev/null | grep -q "#EXTM3U" && \
           [ $(grep -c "#EXTINF" "$TEMP_FILE" 2>/dev/null || echo 0) -gt 0 ]; then
            
            # 处理文件
            sed -i "s|http://[0-9.]\+:[0-9]\+/rtp/|${UDPXY_ADDR}/udp/|g" "$TEMP_FILE"
            sed -i "s|http://[0-9.]\+:[0-9]\+/udp/|${UDPXY_ADDR}/udp/|g" "$TEMP_FILE"
            sed -i "s|catchup-source=\"http://[0-9.]\+:[0-9]\+|catchup-source=\"${UDPXY_ADDR}|g" "$TEMP_FILE"
            sed -i "1s|url-tvg=\"https://epg\.51zmt\.top:8001/e\.xml,https://epg\.112114\.xyz/pp\.xml\"|url-tvg=\"https://epg.112114.xyz/pp.xml,https://epg.51zmt.top:8001/e.xml\"|" "$TEMP_FILE"
            
            # 检查是否有实际替换
            if grep -q "$UDPXY_ADDR" "$TEMP_FILE"; then
                # 保存文件
                cp "$TEMP_FILE" "$OUTPUT_FILE"
                
                # 输出统计
                CHANNELS=$(grep -c "#EXTINF" "$OUTPUT_FILE")
                SIZE=$(stat -c%s "$OUTPUT_FILE" 2>/dev/null || wc -c < "$OUTPUT_FILE")
                echo "✅ 更新成功: $CHANNELS个频道, $(($SIZE/1024))KB"
                rm -f "$TEMP_FILE" "$BACKUP_FILE"
                exit 0
            else
                echo "⚠️ 文件验证通过但未找到可替换地址"
            fi
        else
            echo "❌ 文件验证失败"
        fi
    else
        echo "❌ 下载失败"
    fi
    
    rm -f "$TEMP_FILE"
done

# 所有源都失败，恢复备份
echo "❌ 所有源都失败，保留原文件"
if [ -f "$BACKUP_FILE" ]; then
    mv "$BACKUP_FILE" "$OUTPUT_FILE"
    echo "已恢复上次的文件"
else
    echo "警告: 无备份文件可恢复"
fi

exit 1
