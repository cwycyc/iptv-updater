#!/bin/bash
# IPTV自动更新脚本 - GitHub Actions专用版
# 用于每周二自动更新IPTV列表并发布到GitHub Pages

set -e

# 配置变量
CONFIG_FILE="$(dirname "$0")/../config.json"

# 从配置文件加载设置
if [ -f "$CONFIG_FILE" ]; then
    # 读取JSON配置
    UDPXY_HOST=$(grep -o '"udpxy_host":"[^"]*"' "$CONFIG_FILE" | cut -d'"' -f4)
    UDPXY_PORT=$(grep -o '"udpxy_port":"[^"]*"' "$CONFIG_FILE" | cut -d'"' -f4)
    OUTPUT_DIR=$(grep -o '"output_dir":"[^"]*"' "$CONFIG_FILE" | cut -d'"' -f4)
    SOURCE_URLS=$(grep -o '"source_urls":\[[^]]*\]' "$CONFIG_FILE" | sed 's/.*\[//;s/\].*//' | tr -d '"')
else
    # 默认配置
    UDPXY_HOST="192.168.10.2"
    UDPXY_PORT="4022"
    OUTPUT_DIR="docs"
    SOURCE_URLS="https://raw.githubusercontent.com/0987363/iptv-chengdu/master/home/iptv.m3u8,https://cdn.jsdelivr.net/gh/0987363/iptv-chengdu@master/home/iptv.m3u8"
fi

# 构建udpxy地址
UDPXY_ADDR="http://${UDPXY_HOST}:${UDPXY_PORT}"

# 文件路径
LOCAL_FILE="iptv.m3u8"
BACKUP_FILE="iptv.m3u8.backup"
TEMP_FILE="/tmp/iptv_new.m3u8"
LOG_FILE="update.log"

# 确保输出目录存在
mkdir -p "$OUTPUT_DIR"

# 日志函数
log() {
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] $1" | tee -a "$LOG_FILE"
}

# 从URL列表下载文件
download_from_urls() {
    local urls="$1"
    IFS=',' read -ra url_array <<< "$urls"
    
    for url in "${url_array[@]}"; do
        log "尝试从URL下载: $url"
        
        if command -v curl &> /dev/null; then
            if curl -s -o "$TEMP_FILE" -L "$url"; then
                log "下载成功"
                return 0
            fi
        elif command -v wget &> /dev/null; then
            if wget -q -O "$TEMP_FILE" "$url"; then
                log "下载成功"
                return 0
            fi
        fi
        
        log "下载失败: $url"
    done
    
    return 1
}

# 验证M3U8文件
validate_m3u8() {
    local file="$1"
    
    if [ ! -f "$file" ]; then
        log "文件不存在: $file"
        return 1
    fi
    
    local size=$(stat -c%s "$file" 2>/dev/null || wc -c < "$file" 2>/dev/null)
    if [ "$size" -lt 1024 ]; then
        log "文件太小: ${size}字节"
        return 1
    fi
    
    if ! head -n 1 "$file" 2>/dev/null | grep -q "#EXTM3U"; then
        log "不是有效的M3U8文件"
        return 1
    fi
    
    local channel_count=$(grep -c "#EXTINF" "$file" 2>/dev/null || echo 0)
    if [ "$channel_count" -eq 0 ]; then
        log "未找到频道信息"
        return 1
    fi
    
    log "文件验证成功: ${channel_count}个频道"
    return 0
}

# 替换地址为本地udpxy地址
replace_addresses() {
    local file="$1"
    local temp_file="${file}.tmp"
    
    cp "$file" "$temp_file"
    
    log "开始替换地址为: $UDPXY_ADDR"
    
    # 记录原始地址示例
    log "原始地址示例:"
    grep -E "^http://[0-9.]+:[0-9]+/(rtp|udp)/" "$temp_file" | head -3 | while read line; do
        log "  $line"
    done
    
    # 替换播放地址
    sed -i "s|http://[0-9.]\+:[0-9]\+/rtp/|${UDPXY_ADDR}/udp/|g" "$temp_file"
    sed -i "s|http://[0-9.]\+:[0-9]\+/udp/|${UDPXY_ADDR}/udp/|g" "$temp_file"
    
    # 替换catchup-source地址
    sed -i "s|catchup-source=\"http://[0-9.]\+:[0-9]\+|catchup-source=\"${UDPXY_ADDR}|g" "$temp_file"
    
    # 调整EPG源顺序
    if grep -q "url-tvg=" "$temp_file"; then
        sed -i "s|url-tvg=\"https://epg\.51zmt\.top:8001/e\.xml,https://epg\.112114\.xyz/pp\.xml\"|url-tvg=\"https://epg.112114.xyz/pp.xml,https://epg.51zmt.top:8001/e.xml\"|" "$temp_file"
        log "已调整EPG源顺序"
    fi
    
    # 检查替换结果
    local replaced_count=$(grep -c "$UDPXY_ADDR" "$temp_file" 2>/dev/null || echo 0)
    log "已替换地址数量: $replaced_count"
    
    if [ "$replaced_count" -eq 0 ]; then
        log "警告: 未找到可替换的地址"
        # 恢复原文件
        mv "$temp_file" "$file"
        return 1
    fi
    
    # 显示替换后的示例
    log "替换后地址示例:"
    grep "$UDPXY_ADDR" "$temp_file" | head -3 | while read line; do
        log "  $line"
    done
    
    mv "$temp_file" "$file"
    return 0
}

# 创建索引文件
create_index() {
    local output_file="$OUTPUT_DIR/index.html"
    
    cat > "$output_file" << EOF
<!DOCTYPE html>
<html lang="zh-CN">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>IPTV播放列表</title>
    <style>
        body {
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
            max-width: 800px;
            margin: 0 auto;
            padding: 20px;
            line-height: 1.6;
            background-color: #f5f5f5;
            color: #333;
        }
        .container {
            background-color: white;
            border-radius: 10px;
            padding: 30px;
            box-shadow: 0 2px 10px rgba(0,0,0,0.1);
        }
        h1 {
            color: #2c3e50;
            border-bottom: 2px solid #3498db;
            padding-bottom: 10px;
        }
        .info {
            background-color: #f8f9fa;
            border-left: 4px solid #3498db;
            padding: 15px;
            margin: 20px 0;
        }
        .download-btn {
            display: inline-block;
            background-color: #3498db;
            color: white;
            padding: 12px 24px;
            text-decoration: none;
            border-radius: 5px;
            margin: 10px 0;
            transition: background-color 0.3s;
        }
        .download-btn:hover {
            background-color: #2980b9;
        }
        .stats {
            display: flex;
            justify-content: space-between;
            margin: 20px 0;
            flex-wrap: wrap;
        }
        .stat-box {
            background-color: #ecf0f1;
            padding: 15px;
            border-radius: 5px;
            text-align: center;
            flex: 1;
            margin: 5px;
            min-width: 150px;
        }
        .stat-value {
            font-size: 24px;
            font-weight: bold;
            color: #2c3e50;
        }
        .stat-label {
            font-size: 14px;
            color: #7f8c8d;
        }
        .update-time {
            color: #7f8c8d;
            font-size: 14px;
            margin-top: 30px;
            padding-top: 15px;
            border-top: 1px solid #eee;
        }
        @media (max-width: 600px) {
            body {
                padding: 10px;
            }
            .container {
                padding: 15px;
            }
        }
    </style>
</head>
<body>
    <div class="container">
        <h1>IPTV播放列表</h1>
        
        <div class="info">
            <p>这是一个自动更新的IPTV播放列表，每周二自动从源站获取最新频道信息，并适配本地udpxy代理。</p>
        </div>
        
        <div class="stats">
            <div class="stat-box">
                <div class="stat-value" id="channelCount">计算中...</div>
                <div class="stat-label">频道数量</div>
            </div>
            <div class="stat-box">
                <div class="stat-value" id="fileSize">计算中...</div>
                <div class="stat-label">文件大小</div>
            </div>
            <div class="stat-box">
                <div class="stat-value" id="updateStatus">自动</div>
                <div class="stat-label">更新类型</div>
            </div>
        </div>
        
        <a href="./iptv.m3u8" class="download-btn" download="iptv.m3u8">
            📥 下载IPTV播放列表
        </a>
        
        <p>使用说明：</p>
        <ul>
            <li>将此播放列表导入支持M3U8格式的播放器</li>
            <li>需要本地运行udpxy服务（${UDPXY_HOST}:${UDPXY_PORT}）</li>
            <li>列表已自动适配本地网络地址</li>
        </ul>
        
        <div class="update-time">
            <p>最后更新: <span id="lastUpdate">$(date '+%Y-%m-%d %H:%M:%S')</span></p>
            <p>更新频率: 每周二自动更新</p>
        </div>
    </div>
    
    <script>
        // 统计频道数量
        fetch('./iptv.m3u8')
            .then(response => response.text())
            .then(data => {
                const channelCount = (data.match(/#EXTINF/g) || []).length;
                document.getElementById('channelCount').textContent = channelCount;
                
                // 计算文件大小
                const fileSize = Math.round(data.length / 1024);
                document.getElementById('fileSize').textContent = fileSize + ' KB';
            })
            .catch(error => {
                console.error('加载统计信息失败:', error);
                document.getElementById('channelCount').textContent = '加载失败';
                document.getElementById('fileSize').textContent = '未知';
            });
        
        // 更新状态
        const urlParams = new URLSearchParams(window.location.search);
        if (urlParams.get('manual') === 'true') {
            document.getElementById('updateStatus').textContent = '手动';
        }
    </script>
</body>
</html>
EOF
    
    log "已创建索引页面: $output_file"
}

# 主函数
main() {
    log "="*60
    log "开始IPTV列表更新任务"
    log "="*60
    
    log "配置信息:"
    log "  UDPXY地址: $UDPXY_ADDR"
    log "  输出目录: $OUTPUT_DIR"
    log "  源URL列表: $SOURCE_URLS"
    
    # 清理临时文件
    rm -f "$TEMP_FILE" "$BACKUP_FILE"
    
    # 下载新列表
    if ! download_from_urls "$SOURCE_URLS"; then
        log "错误: 无法从任何源URL下载文件"
        exit 1
    fi
    
    # 验证下载的文件
    if ! validate_m3u8 "$TEMP_FILE"; then
        log "错误: 下载的文件无效"
        exit 1
    fi
    
    # 备份当前文件（如果存在）
    if [ -f "$OUTPUT_DIR/$LOCAL_FILE" ]; then
        cp "$OUTPUT_DIR/$LOCAL_FILE" "$BACKUP_FILE"
        log "已备份当前文件"
    fi
    
    # 替换地址
    if ! replace_addresses "$TEMP_FILE"; then
        log "警告: 地址替换可能失败"
    fi
    
    # 移动文件到输出目录
    mv "$TEMP_FILE" "$OUTPUT_DIR/$LOCAL_FILE"
    log "文件已保存到: $OUTPUT_DIR/$LOCAL_FILE"
    
    # 统计信息
    local old_channels=0
    if [ -f "$BACKUP_FILE" ]; then
        old_channels=$(grep -c "#EXTINF" "$BACKUP_FILE" 2>/dev/null || echo 0)
    fi
    local new_channels=$(grep -c "#EXTINF" "$OUTPUT_DIR/$LOCAL_FILE" 2>/dev/null || echo 0)
    local file_size=$(stat -c%s "$OUTPUT_DIR/$LOCAL_FILE" 2>/dev/null || wc -c < "$OUTPUT_DIR/$LOCAL_FILE" 2>/dev/null)
    
    log "更新统计:"
    log "  频道数量: ${old_channels} → ${new_channels}"
    log "  文件大小: $(($file_size/1024)) KB"
    
    # 创建索引页面
    create_index
    
    # 移动日志文件到输出目录
    if [ -f "$LOG_FILE" ]; then
        mv "$LOG_FILE" "$OUTPUT_DIR/$LOG_FILE"
    fi
    
    log "="*60
    log "IPTV列表更新完成"
    log "="*60
}

# 执行主函数
main "$@"
