#!/bin/bash

CURRENT_DIR=$(
    cd "$(dirname "$0")"
    pwd
)

function log() {
    message="[Gateway Log]: $1 "
    echo -e "${message}" 2>&1 | tee -a ${CURRENT_DIR}/gateway-node-install.log
}


log "======================= 开始安装 ======================="

function Check_Root() {
  if [[ $EUID -ne 0 ]]; then
    echo "请使用 root 或 sudo 权限运行此脚本"
    exit 1
  fi
}


function Install_Docker(){
    if which docker >/dev/null 2>&1; then
        log "检测到 Docker 已安装，跳过安装步骤"
        log "启动 Docker "
        systemctl start docker 2>&1 | tee -a ${CURRENT_DIR}/install.log
    else
        log "... 在线安装 docker"

        if [[ $(curl -s ipinfo.io/country) == "CN" ]]; then
            sources=(
                "https://mirrors.aliyun.com/docker-ce"
                "https://mirrors.tencent.com/docker-ce"
                "https://mirrors.163.com/docker-ce"
                "https://mirrors.cernet.edu.cn/docker-ce"
            )

            get_average_delay() {
                local source=$1
                local total_delay=0
                local iterations=3

                for ((i = 0; i < iterations; i++)); do
                    delay=$(curl -o /dev/null -s -w "%{time_total}\n" "$source")
                    total_delay=$(awk "BEGIN {print $total_delay + $delay}")
                done

                average_delay=$(awk "BEGIN {print $total_delay / $iterations}")
                echo "$average_delay"
            }

            min_delay=${#sources[@]}
            selected_source=""

            for source in "${sources[@]}"; do
                average_delay=$(get_average_delay "$source")

                if (( $(awk 'BEGIN { print '"$average_delay"' < '"$min_delay"' }') )); then
                    min_delay=$average_delay
                    selected_source=$source
                fi
            done

            if [ -n "$selected_source" ]; then
                echo "选择延迟最低的源 $selected_source，延迟为 $min_delay 秒"
                export DOWNLOAD_URL="$selected_source"
                curl -fsSL "https://get.docker.com" -o get-docker.sh
                sh get-docker.sh 2>&1 | tee -a ${CURRENT_DIR}/install.log

                log "... 启动 docker"
                systemctl enable docker; systemctl daemon-reload; systemctl start docker 2>&1 | tee -a ${CURRENT_DIR}/install.log

                docker_config_folder="/etc/docker"
                if [[ ! -d "$docker_config_folder" ]];then
                    mkdir -p "$docker_config_folder"
                fi

                docker version >/dev/null 2>&1
                if [[ $? -ne 0 ]]; then
                    log "docker 安装失败"
                    exit 1
                else
                    log "docker 安装成功"
                fi
            else
                log "无法选择源进行安装"
                exit 1
            fi
        else
            log "非中国大陆地区，无需更改源"
            export DOWNLOAD_URL="https://download.docker.com"
            curl -fsSL "https://get.docker.com" -o get-docker.sh
            sh get-docker.sh 2>&1 | tee -a ${CURRENT_DIR}/install.log

            log "... 启动 docker"
            systemctl enable docker; systemctl daemon-reload; systemctl start docker 2>&1 | tee -a ${CURRENT_DIR}/install.log

            docker_config_folder="/etc/docker"
            if [[ ! -d "$docker_config_folder" ]];then
                mkdir -p "$docker_config_folder"
            fi

            docker version >/dev/null 2>&1
            if [[ $? -ne 0 ]]; then
                log "docker 安装失败"
                exit 1
            else
                log "docker 安装成功"
            fi
        fi
    fi
}

function Install_Compose(){
    docker-compose version >/dev/null 2>&1
    if [[ $? -ne 0 ]]; then
        log "... 在线安装 docker-compose"
        
        arch=$(uname -m)
		if [ "$arch" == 'armv7l' ]; then
			arch='armv7'
		fi
		curl -L https://resource.fit2cloud.com/docker/compose/releases/download/v2.22.0/docker-compose-$(uname -s | tr A-Z a-z)-$arch -o /usr/local/bin/docker-compose 2>&1 | tee -a ${CURRENT_DIR}/install.log
        if [[ ! -f /usr/local/bin/docker-compose ]];then
            log "docker-compose 下载失败，请稍候重试"
            exit 1
        fi
        chmod +x /usr/local/bin/docker-compose
        ln -s /usr/local/bin/docker-compose /usr/bin/docker-compose

        docker-compose version >/dev/null 2>&1
        if [[ $? -ne 0 ]]; then
            log "docker-compose 安装失败"
            exit 1
        else
            log "docker-compose 安装成功"
        fi
    else
        compose_v=`docker-compose -v`
        if [[ $compose_v =~ 'docker-compose' ]];then
            read -p "检测到已安装 Docker Compose 版本较低（需大于等于 v2.0.0 版本），是否升级 [y/n] : " UPGRADE_DOCKER_COMPOSE
            if [[ "$UPGRADE_DOCKER_COMPOSE" == "Y" ]] || [[ "$UPGRADE_DOCKER_COMPOSE" == "y" ]]; then
                rm -rf /usr/local/bin/docker-compose /usr/bin/docker-compose
                Install_Compose
            else
                log "Docker Compose 版本为 $compose_v，可能会影响应用商店的正常使用"
            fi
        else
            log "检测到 Docker Compose 已安装，跳过安装步骤"
        fi
    fi
}


function Set_Auth_Key(){
       DEFAULT_AUTH_KEY=`cat /dev/urandom | head -n 16 | md5sum | head -c 10`

       while true; do
           read -p "请设置AuthKey（默认为$DEFAULT_AUTH_KEY）：" AUTH_KEY

           if [[ "$AUTH_KEY" == "" ]];then
               AUTH_KEY=$DEFAULT_AUTH_KEY
           fi

           if [[ ! "$AUTH_KEY" =~ ^[a-zA-Z0-9_]{3,30}$ ]]; then
               echo "错误：仅支持字母、数字、下划线，长度 3-30 位"
               continue
           fi

           log "您设置的AuthKey为：$AUTH_KEY"
           break
       done
}

# function Set_Licence(){
#        while true; do
#            read -p "请设置授权Licence：" LICENCE

#            if [[ ! "$LICENCE" =~ ^[a-zA-Z0-9_]{3,30}$ ]]; then
#                echo "错误：仅支持字母、数字、下划线，长度 3-30 位"
#                continue
#            fi

#            log "您设置的授权Licence为：$LICENCE"
#            break
#        done
# }

function InitNode() {
      log "配置 gateway Node Service"
      git clone -b main  --depth=1 https://github.com/wm-chatgpt/chatgpt-gateway-node-deploy.git chatgpt-gateway-node
      cd chatgpt-gateway-node
      RUN_BASE_DIR=$(pwd)
      sed -i -e "s#BASE_DIR=.*#BASE_DIR=${RUN_BASE_DIR}#g" ./pnctl
      sed -i -e "s#AUTH_KEY:.*#AUTH_KEY: ${AUTH_KEY}#g" ./config.yaml
      # sed -i -e "s#LICENCE:.*#LICENCE: ${LICENCE}#g" ./config.yaml
      cp ./pnctl /usr/local/bin && chmod +x /usr/local/bin/pnctl
      docker compose pull
      docker compose up -d --remove-orphans

}

function Get_Ip(){
    active_interface=$(ip route get 8.8.8.8 | awk 'NR==1 {print $5}')
    if [[ -z $active_interface ]]; then
        LOCAL_IP="127.0.0.1"
    else
        LOCAL_IP=`ip -4 addr show dev "$active_interface" | grep -oP '(?<=inet\s)\d+(\.\d+){3}'`
    fi

    PUBLIC_IP=`curl -s https://api64.ipify.org`
    if [[ -z "$PUBLIC_IP" ]]; then
        PUBLIC_IP="N/A"
    fi
    if echo "$PUBLIC_IP" | grep -q ":"; then
        PUBLIC_IP=[${PUBLIC_IP}]
    fi
}

NODE_PORT=8100
function Show_Result(){
    log ""
    log "=================感谢您的耐心等待，安装已经完成=================="
    log ""
    log "网关地址: http://$PUBLIC_IP:$NODE_PORT"
    log "AuthKey: ${AUTH_KEY}"
    log "LICENCE: ${LICENCE}"
    log "安装日志: ${CURRENT_DIR}/gateway-node-install.log"
        
    log "如果使用的是云服务器，请至安全组开放 $NODE_PORT 端口"
    log ""
    log "================================================================"
}

function Do_Install(){
  Install_Docker
  Install_Compose
  Set_Auth_Key
  Set_Licence
  InitNode
  Get_Ip
  Show_Result
  }
function main(){
    Check_Root
    DIRECTORY="chatgpt-gateway-node"
    if [ -d "$DIRECTORY" ]; then
        # 目录存在，询问是否覆盖
        read -p "目录 '$DIRECTORY' 已存在。是否覆盖安装？(y/n): " choice
        if [[ $choice == "y" || $choice == "Y" ]]; then
            log "开始覆盖安装,config.yaml已经备份到当前目录"
            if [ -f "$DIRECTORY/config.yaml" ]; then
                # 文件存在，执行复制操作
                cp "$DIRECTORY/config.yaml" config.yaml
                echo "File copied to config.yaml"
            else
                # 文件不存在，跳过复制
                echo "Source file does not exist, skipping copy."
            fi
            rm -rf chatgpt-gateway-node
            Do_Install
        else
            log "覆盖安装已取消。"
            exit 1
        fi
    else
        # 目录不存在，继续安装
        log "目录不存在，继续安装..."
        # 这里添加安装命令
        # 例如: git clone <repository_url> $DIRECTORY
        Do_Install
    fi

}

main
