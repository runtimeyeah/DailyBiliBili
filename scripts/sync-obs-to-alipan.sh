#! /bin/bash

# 同步obs到阿里云盘

OSS_BIN=/root/oss/ossutil
ALIPAN_BIN=/root/alipan/aliyunpan
export ALIYUNPAN_CONFIG_DIR=/root/alipan

# 创建临时目录
TMP_DIR="/tmp/oss"
mkdir -p "$TMP_DIR"

OSS_BUCKET="oss://runtimeerr-aigc"
# 要同步的OSS路径
OSS_PATHS=(
    "oss://runtimeerr-aigc/dailyenglish/bbc/audio"
    "oss://runtimeerr-aigc/dailyenglish/cnn/youtube/videos"
)

# 清理函数
cleanup() {
    echo "Cleaning up temporary files..."
    rm -rf "$TMP_DIR"
}

# 错误处理
set -e
trap cleanup EXIT

# 检查文件是否存在于阿里云盘
check_file_exists() {
    local alipan_path="$1"
    if grep -qP "audio/00|videos/00" <<< "$alipan_path"; then
        return 1
    fi

    # 检查输出中是否包含"指定目录不存在"
    if "$ALIPAN_BIN" ls "$alipan_path" 2>&1 | grep -q "不存在"; then
        return 1
    fi
    return 0
}

# 主同步逻辑
for oss_path in "${OSS_PATHS[@]}"; do
    echo "Processing OSS path: $oss_path"
    
    # 获取相对路径
    rel_path=$(echo "$oss_path" | sed 's|oss://runtimeerr-aigc/||')
    local_path="$TMP_DIR"
    alipan_path=""
    
    # 创建本地目录
    mkdir -p "$local_path"
    
    # 列出OSS中的文件
    echo "Listing files in $oss_path..."
    mapfile -t files < <("$OSS_BIN" ls "$oss_path" | grep -oP "(?<=oss://runtimeerr-aigc)(.*)")
    
    # 使用数组下标遍历
    for i in "${!files[@]}"; do
        file="${files[$i]}"
        
        # 跳过目录
        if [[ "$file" == */ ]]; then
            continue
        fi
        
        # 获取相对路径和文件名
        
        file_dir=$(dirname "$file")
        filename=$(basename "$file")
        
        # 创建对应的本地目录
        mkdir -p "$local_path/$file_dir"
        
        # 设置本地和阿里云盘路径
        local_file="$local_path/$file"
        alipan_file="$alipan_path/$file"
        alipan_file_dir=$(dirname "$alipan_file")
        
        # 检查文件是否已存在于阿里云盘
        if check_file_exists "$alipan_file"; then
            echo "File already exists in Aliyunpan: $alipan_file"
            continue
        fi
        
        # 下载文件（使用完整的OSS路径）
        echo "Downloading $file to $local_file..."
        "$OSS_BIN" cp "${OSS_BUCKET}${file}" "$local_file"
        
        # 上传到阿里云盘
        echo "Uploading $local_file to $alipan_file..."
        "$ALIPAN_BIN" upload "$local_file" "$alipan_file_dir"
        
        # 删除本地文件
        rm -f "$local_file"
    done

    # # 删除OSS中的2025开头的目录
    echo "Deleting 2025 directories from $oss_path..."
    mapfile -t dirs < <("$OSS_BIN" ls -d "$oss_path/" | grep -oP "(?<=oss://runtimeerr-aigc)(.*)" | grep "^.*/$(date +%Y).*/$")
    for dir in "${dirs[@]}"; do
        echo "Deleting directory: ${OSS_BUCKET}${dir}"
        "$OSS_BIN" rm -rf "${OSS_BUCKET}${dir}"
    done
done

echo "Sync completed successfully!"

