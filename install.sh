#!/bin/bash
set -e

## 克隆仓库到本地
echo "clone repository..."
git clone -b main  --depth=1 https://github.com/hanglegehang/chatgpt-proxy-node-deploy.git chatgpt-proxy-node

## 进入目录
cd chatgpt-proxy-node

docker compose pull
docker compose up -d --remove-orphans

## 提示信息
echo "服务启动成功，请访问 http://ip:8100"