#!/bin/bash
# IPTV自动更新脚本 - GitHub Actions完整处理版
# 在云端完成所有处理，OpenWRT只需下载成品

set -e

# 配置参数（GitHub Secrets或直接设置）
# 注意：这里是您的本地udpxy地址，GitHub Actions会将其硬编码到文件中
UDPXY_HOST=${INPUT_UDPXY_HOST:-"192.168.10.2"}
UDPXY_PORT=${INPUT_UDPXY_PORT:-"4022"}
UDPXY_ADDR="http://${UDPXY_HOST}:${UDPXY_PORT}"

# 源URL列表
SOURCE_URLS=(
    "https://raw.githubusercontent.com/0987363/iptv-chengdu/master/home/iptv.m3u8"
    "https://cdn.jsdelivr.net/gh/0987363/iptv-chengdu@master/home/iptv.m3u8"
    "https://ghproxy.com/https://raw.githubusercontent.com/0987363/iptv-chengdu/master/home/iptv.m3u8"
)

# 文件路径
OUTPUT_DIR="docs"
PROCESSED_FILE="iptv_processed.m3u8"  # 处理后的文件
RAW_FILE="iptv_raw.m3u8"              # 原始文件备份
TEMP_FILE="/tmp/iptv_temp.m3u8"
LOG_FILE="update.log"

# 创建目录
mkdir -p "$OUTPUT_DIR"

# 日志函数
log() {
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local message="[$timestamp] $1"
    echo "$message"  # 输出到控制台
    echo "$message" >> "$LOG_FILE"  # 保存到日志文件
}

# 下载函数
download_from_urls() {
    log "开始下载IPTV列表"
    
    for url in "${SOURCE_URLS[@]}"; do
        log "尝试URL: $url"
        
        # 使用curl（GitHub Actions默认有curl）
        if curl -s -L -o "$TEMP_FILE" --connect-timeout 30 --max-time 60 "$url"; then
            if validate_m3u8 "$TEMP_FILE"; then
                log "✅ 下载成功"
                return 0
            else
                log "⚠️  文件验证失败"
            fi
        else
            log "❌ 下载失败"
        fi
        
        rm -f "$TEMP_FILE" 2>/dev/null
    done
    
    log "❌ 所有源都下载失败"
    return 1
}

# 验证M3U8文件
validate_m3u8() {
    local file="$1"
    
    if [ ! -f "$file" ] || [ ! -s "$file" ]; then
        return 1
    fi
    
    # 检查文件大小（至少1KB）
    local size
    if command -v stat &> /dev/null; then
        size=$(stat -c%s "$file" 2>/dev/null || echo 0)
    else
        size=$(wc -c < "$file" 2>/dev/null | awk '{print $1}' || echo 0)
    fi
    
    if [ "$size" -lt 1024 ]; then
        log "文件太小: ${size}字节"
        return 1
    fi
    
    # 检查M3U8头部
    if ! head -n 1 "$file" 2>/dev/null | grep -q "#EXTM3U"; then
        log "不是有效的M3U8文件"
        return 1
    fi
    
    # 检查频道数量
    local channel_count
    if command -v grep &> /dev/null; then
        channel_count=$(grep -c "#EXTINF" "$file" 2>/dev/null || echo 0)
    else
        channel_count=0
    fi
    
    if [ "$channel_count" -eq 0 ]; then
        log "未找到频道信息"
        return 1
    fi
    
    log "文件有效: ${channel_count}个频道, ${size}字节"
    return 0
}

# 备份原始文件
backup_raw_file() {
    if [ -f "$TEMP_FILE" ]; then
        cp "$TEMP_FILE" "$OUTPUT_DIR/$RAW_FILE"
        log "原始文件备份到: $OUTPUT_DIR/$RAW_FILE"
    fi
}

# 处理IPTV列表（替换地址）
process_iptv_list() {
    local input_file="$1"
    local output_file="$2"
    
    if [ ! -f "$input_file" ]; then
        log "❌ 输入文件不存在"
        return 1
    fi
    
    log "开始处理IPTV列表"
    log "将替换为udpxy地址: $UDPXY_ADDR"
    
    # 复制文件
    cp "$input_file" "$output_file"
    
    # 替换播放地址
    log "替换播放地址..."
    
    # 替换rtp地址
    if sed -i "s|http://[0-9.]\+:[0-9]\+/rtp/|${UDPXY_ADDR}/udp/|g" "$output_file"; then
        rtp_count=$(grep -c "${UDPXY_ADDR}/udp/" "$output_file" 2>/dev/null || echo 0)
        log "  rtp地址替换: 找到约 $rtp_count 个"
    fi
    
    # 替换udp地址
    if sed -i "s|http://[0-9.]\+:[0-9]\+/udp/|${UDPXY_ADDR}/udp/|g" "$output_file"; then
        udp_count=$(grep -c "${UDPXY_ADDR}/udp/" "$output_file" 2>/dev/null || echo 0)
        log "  udp地址替换: 找到约 $udp_count 个"
    fi
    
    # 替换catchup-source地址
    log "替换catchup-source地址..."
    if sed -i "s|catchup-source=\"http://[0-9.]\+:[0-9]\+|catchup-source=\"${UDPXY_ADDR}|g" "$output_file"; then
        catchup_count=$(grep -c "catchup-source=\"${UDPXY_ADDR}" "$output_file" 2>/dev/null || echo 0)
        log "  catchup-source替换: 找到约 $catchup_count 个"
    fi
    
    # 调整EPG源顺序（仅修改第一行）
    log "调整EPG源顺序..."
    if head -n 1 "$output_file" 2>/dev/null | grep -q "url-tvg="; then
        sed -i "1s|url-tvg=\"https://epg\.51zmt\.top:8001/e\.xml,https://epg\.112114\.xyz/pp\.xml\"|url-tvg=\"https://epg.112114.xyz/pp.xml,https://epg.51zmt.top:8001/e.xml\"|" "$output_file"
        log "  EPG源顺序已调整"
    fi
    
    # 验证处理结果
    local total_replaced
    total_replaced=$(grep -c "$UDPXY_ADDR" "$output_file" 2>/dev/null || echo 0)
    
    if [ "$total_replaced" -eq 0 ]; then
        log "⚠️  警告: 未找到可替换的地址"
        # 显示原始地址示例
        log "原始地址示例:"
        grep -E "^http://[0-9.]+:[0-9]+/" "$input_file" | head -2 | while read line; do
            log "  $line"
        done
    else
        log "✅ 地址替换完成: 共替换约 $total_replaced 个地址"
    fi
    
    return 0
}

# 生成统计信息
generate_stats() {
    local file="$1"
    local stats_file="$OUTPUT_DIR/stats.json"
    
    local channels=0
    local size=0
    
    if [ -f "$file" ]; then
        channels=$(grep -c "#EXTINF" "$file" 2>/dev/null || echo 0)
        
        if command -v stat &> /dev/null; then
            size=$(stat -c%s "$file" 2>/dev/null || echo 0)
        else
            size=$(wc -c < "$file" 2>/dev/null | awk '{print $1}' || echo 0)
        fi
    fi
    
    cat > "$stats_file" << EOF
{
    "channels": $channels,
    "file_size": $size,
    "update_time": "$(date '+%Y-%m-%d %H:%M:%S')",
    "udpxy_address": "$UDPXY_ADDR",
    "epg_sources": ["https://epg.112114.xyz/pp.xml", "https://epg.51zmt.top:8001/e.xml"]
}
EOF
    
    log "统计信息: $channels个频道, $(($size/1024))KB"
}

# 生成HTML页面
generate_html_page() {
    local html_file="$OUTPUT_DIR/index.html"
    
    cat > "$html_file" << 'EOF'
<!DOCTYPE html>
<html lang="zh-CN">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>IPTV播放列表 - 已处理版</title>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body {
            font-family: 'Segoe UI', 'Microsoft YaHei', sans-serif;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            min-height: 100vh;
            display: flex;
            justify-content: center;
            align-items: center;
            padding: 20px;
        }
        .container {
            background: rgba(255, 255, 255, 0.95);
            border-radius: 20px;
            padding: 40px;
            box-shadow: 0 20px 60px rgba(0, 0, 0, 0.3);
            max-width: 800px;
            width: 100%;
            backdrop-filter: blur(10px);
        }
        .header {
            text-align: center;
            margin-bottom: 30px;
        }
        .header h1 {
            color: #2c3e50;
            font-size: 2.5em;
            margin-bottom: 10px;
        }
        .header .subtitle {
            color: #7f8c8d;
            font-size: 1.1em;
        }
        .card {
            background: white;
            border-radius: 15px;
            padding: 30px;
            margin: 20px 0;
            box-shadow: 0 10px 30px rgba(0, 0, 0, 0.1);
            border: 1px solid rgba(0, 0, 0, 0.05);
        }
        .card-title {
            font-size: 1.4em;
            color: #3498db;
            margin-bottom: 20px;
            display: flex;
            align-items: center;
            gap: 10px;
        }
        .card-title i {
            font-size: 1.2em;
        }
        .download-btn {
            display: inline-block;
            background: linear-gradient(135deg, #3498db, #2ecc71);
            color: white;
            padding: 15px 30px;
            text-decoration: none;
            border-radius: 10px;
            font-size: 1.1em;
            font-weight: bold;
            transition: all 0.3s ease;
            border: none;
            cursor: pointer;
            text-align: center;
            width: 100%;
            margin: 10px 0;
        }
        .download-btn:hover {
            transform: translateY(-3px);
            box-shadow: 0 10px 20px rgba(52, 152, 219, 0.3);
        }
        .stats {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(150px, 1fr));
            gap: 20px;
            margin: 20px 0;
        }
        .stat-item {
            background: #f8f9fa;
            padding: 20px;
            border-radius: 10px;
            text-align: center;
        }
        .stat-value {
            font-size: 2em;
            font-weight: bold;
            color: #2c3e50;
        }
        .stat-label {
            color: #7f8c8d;
            margin-top: 5px;
        }
        .info-box {
            background: #e8f4fd;
            border-left: 4px solid #3498db;
            padding: 15px;
            margin: 20px 0;
            border-radius: 0 10px 10px 0;
        }
        .info-box h3 {
            color: #2c3e50;
            margin-bottom: 10px;
        }
        .info-box ul {
            padding-left: 20px;
        }
        .info-box li {
            margin: 5px 0;
            color: #555;
        }
        .footer {
            text-align: center;
            margin-top: 30px;
            color: #7f8c8d;
            font-size: 0.9em;
            padding-top: 20px;
            border-top: 1px solid #eee;
        }
        @media (max-width: 600px) {
            .container {
                padding: 20px;
            }
            .header h1 {
                font-size: 2em;
            }
            .stats {
                grid-template-columns: 1fr;
            }
        }
    </style>
    <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.0.0/css/all.min.css">
</head>
<body>
    <div class="container">
        <div class="header">
            <h1><i class="fas fa-tv"></i> IPTV播放列表</h1>
            <p class="subtitle">已处理版 - 适用于OpenWRT + udpxy</p>
        </div>
        
        <div class="card">
            <h2 class="card-title"><i class="fas fa-download"></i> 下载已处理文件</h2>
            <p>此文件已完成所有处理，可直接用于OpenWRT：</p>
            <a href="./iptv_processed.m3u8" class="download-btn" download="iptv.m3u8">
                <i class="fas fa-file-download"></i> 下载IPTV播放列表
            </a>
            <p style="text-align: center; margin-top: 10px; color: #666; font-size: 0.9em;">
                <i class="fas fa-info-circle"></i> 已自动替换地址为您的udpxy服务器
            </p>
        </div>
        
        <div class="stats">
            <div class="stat-item">
                <div class="stat-value" id="channelCount">--</div>
                <div class="stat-label">频道数量</div>
            </div>
            <div class="stat-item">
                <div class="stat-value" id="fileSize">--</div>
                <div class="stat-label">文件大小</div>
            </div>
            <div class="stat-item">
                <div class="stat-value" id="updateTime">--</div>
                <div class="stat-label">更新时间</div>
            </div>
        </div>
        
        <div class="info-box">
            <h3><i class="fas fa-info-circle"></i> 使用说明</h3>
            <ul>
                <li><strong>OpenWRT使用：</strong>下载后放入路由器，使用支持M3U8的播放器播放</li>
                <li><strong>udpxy地址：</strong>已替换为 <code id="udpxyAddr">192.168.10.2:4022</code></li>
                <li><strong>EPG源：</strong>已优化为 <code>112114.xyz</code> 优先</li>
                <li><strong>更新频率：</strong>每周二自动更新</li>
            </ul>
        </div>
        
        <div class="info-box">
            <h3><i class="fas fa-history"></i> 更新历史</h3>
            <ul>
                <li><strong>原始文件：</strong> <a href="./iptv_raw.m3u8">下载原始M3U8</a></li>
                <li><strong>更新日志：</strong> <a href="./update.log">查看更新日志</a></li>
                <li><strong>统计信息：</strong> <a href="./stats.json">查看JSON统计</a></li>
            </ul>
        </div>
        
        <div class="footer">
            <p><i class="fas fa-sync-alt"></i> 每周二自动更新 | <i class="fas fa-server"></i> GitHub Actions处理</p>
            <p>最后更新: <span id="lastUpdateTime">正在加载...</span></p>
        </div>
    </div>
    
    <script>
        // 加载统计数据
        fetch('./stats.json')
            .then(response => response.json())
            .then(data => {
                document.getElementById('channelCount').textContent = data.channels;
                document.getElementById('fileSize').textContent = Math.round(data.file_size / 1024) + ' KB';
                document.getElementById('updateTime').textContent = data.update_time.split(' ')[0];
                document.getElementById('udpxyAddr').textContent = data.udpxy_address;
                document.getElementById('lastUpdateTime').textContent = data.update_time;
            })
            .catch(error => {
                console.error('加载统计数据失败:', error);
                document.getElementById('lastUpdateTime').textContent = '加载失败';
            });
    </script>
</body>
</html>
EOF
    
    log "HTML页面已生成: $html_file"
}

# 主函数
main() {
    log "🚀 IPTV更新任务开始"
    log "========================================"
    
    # 1. 下载原始列表
    if ! download_from_urls; then
        log "❌ 无法下载IPTV列表，任务失败"
        exit 1
    fi
    
    # 2. 备份原始文件
    backup_raw_file
    
    # 3. 处理IPTV列表（替换地址）
    local processed_file="$OUTPUT_DIR/$PROCESSED_FILE"
    if ! process_iptv_list "$TEMP_FILE" "$processed_file"; then
        log "❌ 处理IPTV列表失败"
        exit 1
    fi
    
    # 4. 验证处理后的文件
    if ! validate_m3u8 "$processed_file"; then
        log "❌ 处理后的文件验证失败"
        exit 1
    fi
    
    # 5. 生成统计信息
    generate_stats "$processed_file"
    
    # 6. 生成HTML页面
    generate_html_page
    
    # 7. 移动日志文件
    if [ -f "$LOG_FILE" ]; then
        mv "$LOG_FILE" "$OUTPUT_DIR/$LOG_FILE"
    fi
    
    # 8. 清理临时文件
    rm -f "$TEMP_FILE" 2>/dev/null
    
    log "========================================"
    log "✅ IPTV更新任务完成"
    log "📁 输出目录: $OUTPUT_DIR/"
    log "📄 处理文件: $PROCESSED_FILE"
    log "📄 原始备份: $RAW_FILE"
    log "📄 更新日志: $LOG_FILE"
    log "🌐 访问地址: https://[你的用户名].github.io/[仓库名]/"
    
    # 最终统计
    if [ -f "$processed_file" ]; then
        local final_channels=$(grep -c "#EXTINF" "$processed_file" 2>/dev/null || echo 0)
        log "📊 最终统计: $final_channels 个频道"
    fi
}

# 执行主函数
main "$@"
