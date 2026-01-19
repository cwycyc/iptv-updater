#!/bin/bash
# IPTV自动更新脚本 - 保留前次文件版
# 新增EPG下载并本地化EPG地址

set -e

# 配置参数
UDPXY_HOST="192.168.10.2"
UDPXY_PORT="4022"
UDPXY_ADDR="http://${UDPXY_HOST}:${UDPXY_PORT}"
LOCAL_EPG_URL="http://192.168.10.254/epg.xml"  # OpenWRT本地EPG地址

# 源URL列表
SOURCES=(
    "https://raw.githubusercontent.com/0987363/iptv-chengdu/master/home/iptv.m3u8"
    "https://cdn.jsdelivr.net/gh/0987363/iptv-chengdu@master/home/iptv.m3u8"
    "https://ghproxy.com/https://raw.githubusercontent.com/0987363/iptv-chengdu/master/home/iptv.m3u8"
)

# 文件路径
OUTPUT_FILE="docs/iptv.m3u8"
EPG_FILE="docs/epg.xml"  # 新增EPG输出文件
TEMP_FILE="/tmp/iptv_temp.m3u8"
BACKUP_FILE="/tmp/iptv_backup.m3u8"
EPG_TEMP="/tmp/epg_temp.xml"

# 创建目录
mkdir -p docs

# 备份当前文件
if [ -f "$OUTPUT_FILE" ]; then
    cp "$OUTPUT_FILE" "$BACKUP_FILE"
fi

# ==================== 新增EPG下载部分 ====================
echo "开始下载EPG数据..."

# EPG源列表（按优先级）
EPG_SOURCES=(
    "https://epg.112114.xyz/pp.xml"
    "http://epg.51zmt.top:8000/e.xml"
)

EPG_DOWNLOADED=false
for epg_url in "${EPG_SOURCES[@]}"; do
    echo "尝试EPG源: $epg_url"
    
    if curl -s -L -o "$EPG_TEMP" --connect-timeout 30 --max-time 60 "$epg_url"; then
        # 验证EPG文件（简单检查是否为XML）
        if head -n 1 "$EPG_TEMP" 2>/dev/null | grep -q "<?xml" || grep -q "<tv>" "$EPG_TEMP"; then
            cp "$EPG_TEMP" "$EPG_FILE"
            echo "✅ EPG下载成功"
            EPG_DOWNLOADED=true
            break
        else
            echo "⚠️ EPG文件格式验证失败"
        fi
    else
        echo "❌ EPG源连接失败"
    fi
    rm -f "$EPG_TEMP"
done

if [ "$EPG_DOWNLOADED" = false ]; then
    echo "⚠️ 所有EPG源下载失败，将生成不含EPG的列表"
fi
# ==================== EPG下载部分结束 ====================

# 尝试下载
for url in "${SOURCES[@]}"; do
    echo "尝试下载IPTV列表: $url"
    
    if curl -s -L -o "$TEMP_FILE" --connect-timeout 30 --max-time 60 "$url"; then
        # 验证文件
        if head -n 1 "$TEMP_FILE" 2>/dev/null | grep -q "#EXTM3U" && \
           [ $(grep -c "#EXTINF" "$TEMP_FILE" 2>/dev/null || echo 0) -gt 0 ]; then
            
            # 处理文件
            sed -i "s|http://[0-9.]\+:[0-9]\+/rtp/|${UDPXY_ADDR}/udp/|g" "$TEMP_FILE"
            sed -i "s|http://[0-9.]\+:[0-9]\+/udp/|${UDPXY_ADDR}/udp/|g" "$TEMP_FILE"
            sed -i "s|catchup-source=\"http://[0-9.]\+:[0-9]\+|catchup-source=\"${UDPXY_ADDR}|g" "$TEMP_FILE"
           
            # ==================== 修改EPG地址为本地 ====================
            # 删除可能存在的url-tvg属性
            sed -i "s| url-tvg=\"[^\"]*\"||" "$TEMP_FILE"
            
            # 在#EXTM3U行末尾添加指向本地路由器的EPG地址
            # 注意：这里使用LOCAL_EPG_URL变量，指向OpenWRT本地地址
            sed -i "s|\(#EXTM3U.*\)|\1 url-tvg=\"$LOCAL_EPG_URL\"|" "$TEMP_FILE"
            echo "✅ EPG地址已替换为本地: $LOCAL_EPG_URL"
            # ==================== EPG地址修改结束 ====================
            
            # 检查是否有实际替换
            if grep -q "$UDPXY_ADDR" "$TEMP_FILE"; then
                # 保存文件
                cp "$TEMP_FILE" "$OUTPUT_FILE"
                
                # 输出统计
                CHANNELS=$(grep -c "#EXTINF" "$OUTPUT_FILE")
                SIZE=$(stat -c%s "$OUTPUT_FILE" 2>/dev/null || wc -c < "$OUTPUT_FILE")
                echo "✅ 更新成功: $CHANNELS个频道, $(($SIZE/1024))KB"
                
                # 如果EPG下载成功，也输出EPG信息
                if [ "$EPG_DOWNLOADED" = true ] && [ -f "$EPG_FILE" ]; then
                    EPG_SIZE=$(stat -c%s "$EPG_FILE" 2>/dev/null || wc -c < "$EPG_FILE")
                    echo "✅ EPG文件大小: $(($EPG_SIZE/1024))KB"
                fi
                
                rm -f "$TEMP_FILE" "$BACKUP_FILE" "$EPG_TEMP"
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
    # 注意：不恢复EPG文件，因为它没有独立备份
else
    echo "警告: 无备份文件可恢复"
fi

exit 1
