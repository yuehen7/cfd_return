#!/usr/bin/env bash

# 当前脚本更新日期 （2025.01.23）

# GitHub 代理地址
GH_PROXY='https://hub.gitmirror.com/'

# 工作和临时目录
SERVER_WORK_DIR='/etc/cfd_return_server'
CLIENT_WORK_DIR='/etc/cfd_return_client'
TMP_DIR='/tmp/cfd_return'


# 当脚本被中断时，清理临时文件
trap "rm -rf ${TMP_DIR}; exit" INT

# 项目说明
description() {
  clear
  echo -e "\n项目说明: 通过 Cloudflare Tunnel 的全球 CDN 网络回源，网络实现高速、稳定的数据传输。"
  echo -e "\n项目地址: https://github.com/yenhen7/cfd_return\n"
}

# 检查操作系统类型
check_os() {
  if [ "$(type -p apt)" ]; then
    OS='debian'
  elif [ "$(type -p dnf)" ]; then
    OS='centos'
  elif [ "$(type -p apk)" ]; then
    OS='alpine'
  elif [ "$(type -p opkg)" ]; then
    OS='openwrt'
  else
    [ -s /etc/os-release ] && OS=$(awk -F \" '/^NAME/{print $2}' /etc/os-release)
    echo "Error: 当前操作系统是: ${OS}，只支持 CentOS, Debian, Ubuntu, Alpine, OpenWRT。" && exit 1
  fi
}

# 检查是否已安装服务端或客户端
check_install() {
  [ -d ${SERVER_WORK_DIR} ] && IS_INSTALL_SERVER=installed || IS_INSTALL_SERVER=uninstall
  [ -d ${CLIENT_WORK_DIR} ] && IS_INSTALL_CLIENT=installed || IS_INSTALL_CLIENT=uninstall
}

# 检查系统架构
check_arch() {
  local ARCHITECTURE=$(uname -m)
  case "$ARCHITECTURE" in
    aarch64 | arm64)
      ARCH=arm64
      ;;
    x86_64 | amd64)
      cat /proc/cpuinfo | grep -q avx2 && IS_AMD64V3=v3
      ARCH=amd64
      ;;
    armv7*)
      ARCH=arm
      ;;
    *)
      echo "Error: 当前架构是: ${ARCHITECTURE}，只支持 amd64, armv7 和 arm64" && exit 1
      ;;
  esac
}

# 服务端安装函数
server_install() {
  # 生成 10000-65535 的随机空闲端口号
  search_idle_ramdom_port() {
    [ "$(type -p ss)" ] && local CMD=ss || local CMD=netstat
    while true; do
      local PORT=$(( (RANDOM % 55536) + 10000 ))
      ! $CMD -nlutp | grep -q ":$PORT" && echo "$PORT" && break
    done
  }

  # 检查端口是否可用
  check_port_inuse() {
    local PORT=$1
    [[ "$PORT" -lt 1 || "$PORT" -gt 65535 ]] && echo -e "\nError: 请输入 1-65535 之间的端口。" && return
    [ "$(type -p ss)" ] && local CMD=ss || local CMD=netstat
    $CMD -nlutp | grep -q ":$PORT" && echo -e "\nError: 端口 $PORT 已被占用，请更换。" || { echo -e "\n端口 $PORT 可用。" && PORT_USABLE='port_usable'; }
  }

  echo "$OS" | egrep -qiv "CentOS|Debian|OpenWrt" && echo "Error: 当前操作系统是: ${OS}，服务端只支持 CentOS, Debian, Ubuntu 和 OpenWRT。" && exit 1

  [ ! -d ${TMP_DIR} ] && mkdir -p ${TMP_DIR}

  until [[ "$CFD_PORT" =~ ^[0-9]+$ ]]; do
    echo ""
    [ -z "$CFD_PORT_INPUT" ] && read -rp "请输入 Cloudflared tunnel 回源的端口 [1-65535]，不填写则使用 10000-65535 的随机端口: " CFD_PORT_INPUT
    if [ -z "$CFD_PORT_INPUT" ]; then
      CFD_PORT=$(search_idle_ramdom_port)
    else
      check_port_inuse $CFD_PORT_INPUT
      echo "$PORT_USABLE" | grep -qwv 'port_usable' && unset CFD_PORT_INPUT || CFD_PORT=$CFD_PORT_INPUT
    fi
  done

  echo ""
  [ -z "$CFD_DOMAIN_INPUT" ] && read -rp "请输入 Cloudflare tunnel 的域名: " CFD_DOMAIN_INPUT
  CFD_DOMAIN=$(echo "$CFD_DOMAIN_INPUT" | sed 's/^[ ]*//; s/[ ]*$//')

  echo ""
  [ -z "$CFD_AUTH_INPUT" ] && echo -e "\n用户通过以下网站轻松获取 json: https://fscarmen.cloudflare.now.cc\n" && read -rp "请输入 Cloudflare tunnel 的 json 或 token : " CFD_AUTH_INPUT

  # 根据 CFD_AUTH_INPUT 的内容，自行判断是 Json 还是 Token
  if echo "$CFD_AUTH_INPUT" | grep -q 'TunnelSecret'; then
    local CFD_JSON=${CFD_AUTH_INPUT//[ ]/}
    echo $CFD_JSON > ${TMP_DIR}/tunnel.json
    cat > ${TMP_DIR}/tunnel.yml << EOF
tunnel: $(echo "$CFD_JSON" | awk -F '"' '{print $12}')
credentials-file: ${SERVER_WORK_DIR}/tunnel.json

ingress:
  - hostname: ${CFD_DOMAIN}
    service: http://localhost:${CFD_PORT}
  - service: http_status:404
EOF
    local CFD_ARGS="tunnel --logfile /tmp/cloudflared.log --edge-ip-version auto --config ${SERVER_WORK_DIR}/tunnel.yml run"
  elif echo "$CFD_AUTH_INPUT" | egrep -q '[A-Z0-9a-z=]{120,250}$'; then
    local CFD_TOKEN=$(echo "$CFD_AUTH_INPUT" | sed 's/^[ ]*//; s/[ ]*$//' | awk -F ' ' '{print $NF}')
    local CFD_ARGS="tunnel --logfile /tmp/cloudflared.log --edge-ip-version auto run --token ${CFD_TOKEN}"
  fi

  echo ""
  WS_PATH_DEFAULT=$(cat /proc/sys/kernel/random/uuid)
  [ -z "$WS_PATH_INPUT" ] && read -rp "请输入 ws 路径 [默认为 $WS_PATH_DEFAULT]: " WS_PATH_INPUT
  WS_PATH=$(echo $WS_PATH_INPUT | sed 's#^/##')
  [ -z "$WS_PATH" ] && WS_PATH=$WS_PATH_DEFAULT

  echo ""
  [ -z "$STACK_INPUT" ] && read -rp "请输入优选 IP 列表 [4,6,d,n]，d是双栈，n是不进行优选，默认为双栈 d: " STACK_INPUT
  case "$STACK_INPUT" in
    4|6 )
      local STACK=$STACK_INPUT
      ;;
    n )
      local IS_CFD=no_cfd
      ;;
    * )
      local STACK='d'
      ;;
    esac

  local CLOUDFLARED_URL="https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-${ARCH}"

  local GOST_API_URL="https://api.github.com/repos/go-gost/gost/releases/latest"

  local GOST_URL_DEFAULT="https://github.com/go-gost/gost/releases/download/v3.0.0/gost_3.0.0_linux_${ARCH}${IS_AMD64V3}.tar.gz"

  local CFD_URL="https://github.com/yuehen7/cfd_return/blob/main/cfd/cfd-linux-${ARCH}"

  local IP_URL="https://raw.githubusercontent.com/yuehen7/cfd_return/refs/heads/main/cfd/ip.txt"

  if [ "$(type -p wget)" ]; then
    echo -e "\n下载 Cloudflared"
    wget --no-check-certificate -O ${TMP_DIR}/cloudflared ${GH_PROXY}${CLOUDFLARED_URL}

    echo -e "\n下载 gost"
    local GOST_URL=$(wget --no-check-certificate -qO- ${GH_PROXY}${GOST_API_URL} | sed -n "s/.*browser_download_url.*\"\(https:.*linux_${ARCH}${IS_AMD64V3}.tar.gz\)\"/\1/gp")
    GOST_URL=${GOST_URL:-${GOST_URL_DEFAULT}}
    wget --no-check-certificate -O- ${GH_PROXY}${GOST_URL} | tar xzv -C ${TMP_DIR} gost

    if [ "$IS_CFD" != 'no_cfd' ]; then
      echo -e "\n下载 cfd 及 IP 列表"
      wget --no-check-certificate -O ${TMP_DIR}/cfd ${GH_PROXY}${CFD_URL}
      case "$STACK" in
        4 )
          wget --no-check-certificate -O- ${GH_PROXY}${IP_URL} | grep '/24' > ${TMP_DIR}/ip
          ;;
        6 )
          wget --no-check-certificate -O- ${GH_PROXY}${IP_URL} | grep '/124' > ${TMP_DIR}/ip
          ;;
        d )
          wget --no-check-certificate -O- ${GH_PROXY}${IP_URL} > ${TMP_DIR}/ip
          ;;
      esac
      wget --no-check-certificate -O- ${GH_PROXY}${IP_URL} | grep '/24' > ${TMP_DIR}/ip
    fi

  elif [ "$(type -p curl)" ]; then
    echo -e "\n下载 Cloudflared"
    curl -Lo ${TMP_DIR}/cloudflared ${GH_PROXY}${CLOUDFLARED_URL}

    echo -e "\n下载 gost"
    local GOST_URL=$(curl -sSL ${GH_PROXY}${GOST_API_URL} | sed -n "s/.*browser_download_url.*\"\(https:.*linux_${ARCH}${IS_AMD64V3}.tar.gz\)\"/\1/gp")
    GOST_URL=${GOST_URL:-${GOST_URL_DEFAULT}}
    curl -L ${GH_PROXY}${GOST_URL} | tar xzv -C ${TMP_DIR} gost

    if [ "$IS_CFD" != 'no_cfd' ]; then
      echo -e "\n下载 cfd 及 IP 列表"
      curl -Lo ${TMP_DIR}/cfd ${GH_PROXY}${CFD_URL}
      case "$STACK" in
        4 )
          curl -sLo- ${GH_PROXY}${IP_URL} | grep '/24' > ${TMP_DIR}/ip
          ;;
        6 )
          curl -sLo- ${GH_PROXY}${IP_URL} | grep '/124' > ${TMP_DIR}/ip
          ;;
        d )
          curl -sLo- ${GH_PROXY}${IP_URL} > ${TMP_DIR}/ip
          ;;
      esac
    fi
  fi

  if [[ -s ${TMP_DIR}/gost && -s ${TMP_DIR}/cloudflared ]]; then
    chmod +x ${TMP_DIR}/gost ${TMP_DIR}/cloudflared
    mkdir -p ${SERVER_WORK_DIR}
    mv ${TMP_DIR}/gost ${TMP_DIR}/cloudflared ${SERVER_WORK_DIR}
    [ -s ${TMP_DIR}/tunnel.json ] && mv ${TMP_DIR}/tunnel* ${SERVER_WORK_DIR}/
  fi

  [[ -s ${TMP_DIR}/cfd && -s ${TMP_DIR}/ip ]] && chmod +x ${TMP_DIR}/cfd && mv ${TMP_DIR}/cfd ${TMP_DIR}/ip ${SERVER_WORK_DIR}

  rm -rf ${TMP_DIR}

  if echo "$OS" | grep -qi 'openwrt'; then
    cat >/etc/init.d/cfd_server <<EOF
#!/bin/sh /etc/rc.common

START=99
STOP=10

NAME="cfd-return"

CFD_PORT=${CFD_PORT}
WS_PATH=${WS_PATH}
EOF

    if echo "$CFD_JSON" | grep -q '.'; then
      cat >>/etc/init.d/cfd_server <<EOF
CFD_JSON=${CFD_JSON}
EOF
    elif echo "$CFD_TOKEN" | grep -q '.'; then
      cat >>/etc/init.d/cfd_server <<EOF
CFD_TOKEN=${CFD_TOKEN}
EOF
    fi

    cat >>/etc/init.d/cfd_server <<EOF

GOST_PROG="${SERVER_WORK_DIR}/gost"
GOST_ARGS="-D -L relay+ws://:\${CFD_PORT}?path=/\${WS_PATH}&bind=true"
GOST_PID="/var/run/gost.pid"

CFD_PROG="${SERVER_WORK_DIR}/cloudflared"
CFD_ARGS="${CFD_ARGS}"
CFD_PID="/var/run/cfd.pid"

EOF

    if [ "$IS_CFD" != 'no_cfd' ]; then
      cat >>/etc/init.d/cfd_server <<EOF
CFD_ENDPOINT_PROG="${SERVER_WORK_DIR}/cfd"
CFD_ENDPOINT_ARGS="-file ${SERVER_WORK_DIR}/ip"
CFD_ENDPOINT_PID="/var/run/cfd_endpoint.pid"

EOF
    fi

    cat >>/etc/init.d/cfd_server <<EOF
start_progs() {
  echo -e "\nStarting gost listener on port \${CFD_PORT}..."
  \$GOST_PROG \$GOST_ARGS >/dev/null 2>&1 &
  echo \$! > \$GOST_PID

  echo -e "\nStarting Cloudflared..."
  \$CFD_PROG \$CFD_ARGS >/dev/null 2>&1 &
  echo \$! > \$CFD_PID
EOF
  if [ "$IS_CFD" != 'no_cfd' ]; then
    cat >>/etc/init.d/cfd_server <<EOF

  echo -e "\nStarting cfd best endpoint..."
  \$CFD_ENDPOINT_PROG \$CFD_ENDPOINT_ARGS >/dev/null 2>&1 &
  echo \$! > \$CFD_ENDPOINT_PID
EOF
  fi

  cat >>/etc/init.d/cfd_server <<EOF
}

stop_progs() {
  echo "Stopping gost listener on port \${CFD_PORT}..."
  {
    kill \$(cat \$GOST_PID)
    rm \$GOST_PID
  }
  echo "Stopping Cloudflared..."
  {
    kill \$(cat \$CFD_PID)
    rm \$CFD_PID
  }
EOF
  if [ "$IS_CFD" != 'no_cfd' ]; then
    cat >>/etc/init.d/cfd_server <<EOF
  echo "Stopping cfd best endpoint..."
  {
    kill \$(cat \$CFD_ENDPOINT_PID)
    rm \$CFD_ENDPOINT_PID
  }
EOF
  fi
  cat >>/etc/init.d/cfd_server <<EOF
}

start() {
  start_progs
}

stop() {
  stop_progs
}

restart(){
 stop
 start
}
EOF
    chmod +x /etc/init.d/cfd_server

  elif echo "$OS" | egrep -qi 'debian|centos'; then
    cat >/etc/systemd/system/cfd_server.service <<EOF
[Unit]
Description=CFD Return Service
After=network.target

[Service]
Type=forking
ExecStart=${SERVER_WORK_DIR}/start.sh start
ExecStop=${SERVER_WORK_DIR}/start.sh stop
PIDFile=/var/run/gost.pid

[Install]
WantedBy=multi-user.target
EOF

    cat >${SERVER_WORK_DIR}/start.sh <<EOF
#!/bin/bash

CFD_PORT=${CFD_PORT}
WS_PATH=${WS_PATH}
EOF
    if echo "$CFD_JSON" | grep -q '.'; then
      cat >>${SERVER_WORK_DIR}/start.sh <<EOF
CFD_JSON='${CFD_JSON}'
EOF
    elif echo "$CFD_TOKEN" | grep -q '.'; then
      cat >>${SERVER_WORK_DIR}/start.sh <<EOF
CFD_TOKEN=${CFD_TOKEN}
EOF
    fi

  cat >>${SERVER_WORK_DIR}/start.sh <<EOF
GOST_PROG="${SERVER_WORK_DIR}/gost"
GOST_ARGS="-D -L relay+ws://:\${CFD_PORT}?path=/\${WS_PATH}&bind=true"
GOST_PID="/var/run/gost.pid"

CFD_PROG="${SERVER_WORK_DIR}/cloudflared"
CFD_ARGS="${CFD_ARGS}"
CFD_PID="/var/run/cfd.pid"

EOF
  if [ "$IS_CFD" != 'no_cfd' ]; then
    cat >>${SERVER_WORK_DIR}/start.sh <<EOF
CFD_ENDPOINT_PROG="${SERVER_WORK_DIR}/cfd"
CFD_ENDPOINT_ARGS="-file ${SERVER_WORK_DIR}/ip"
CFD_ENDPOINT_PID="/var/run/cfd_endpoint.pid"

EOF
  fi

  cat >>${SERVER_WORK_DIR}/start.sh <<EOF
start() {
  echo -e "\nStarting gost listener on port \${CFD_PORT}..."
  \$GOST_PROG \$GOST_ARGS >/dev/null 2>&1 &
  echo \$! > \$GOST_PID

  echo -e "\nStarting Cloudflared..."
  \$CFD_PROG \$CFD_ARGS >/dev/null 2>&1 &
  echo \$! > \$CFD_PID
EOF

  if [ "$IS_CFD" != 'no_cfd' ]; then
    cat >>${SERVER_WORK_DIR}/start.sh <<EOF

  echo -e "\nStarting cfd best endpoint..."
  \$CFD_ENDPOINT_PROG \$CFD_ENDPOINT_ARGS >/dev/null 2>&1 &
  echo \$! > \$CFD_ENDPOINT_PID
EOF
  fi

  cat >>${SERVER_WORK_DIR}/start.sh <<EOF
}

stop() {
  echo "Stopping gost listener on port \${CFD_PORT}..."
  if [ -f "\$GOST_PID" ]; then
    kill \$(cat \$GOST_PID)
    rm \$GOST_PID
  fi

  echo "Stopping Cloudflared..."
  if [ -f "\$CFD_PID" ]; then
    kill \$(cat \$CFD_PID)
    rm \$CFD_PID
  fi
EOF
  if [ "$IS_CFD" != 'no_cfd' ]; then
    cat >>${SERVER_WORK_DIR}/start.sh <<EOF

  echo "Stopping cfd best endpoint..."
  if [ -f "\$CFD_ENDPOINT_PID" ]; then
    kill \$(cat \$CFD_ENDPOINT_PID)
    rm \$CFD_ENDPOINT_PID
  fi
EOF
  fi
  cat >>${SERVER_WORK_DIR}/start.sh <<EOF
}

case "\$1" in
  start)
    start
    ;;
  stop)
    stop
    ;;
  restart)
    stop
    start
    ;;
  *)
    echo "Usage: \$0 {start|stop|restart}"
    exit 1
    ;;
esac

exit 0
EOF

    chmod +x ${SERVER_WORK_DIR}/start.sh
  fi

  cat >${SERVER_WORK_DIR}/config.json <<EOF
{
  "WS_PATH": "${WS_PATH}",
  "CFD_PORT": ${CFD_PORT},
  "CFD_DOMAIN": "${CFD_DOMAIN}",
EOF

  if echo "$CFD_JSON" | grep -q '.'; then
    cat >>${SERVER_WORK_DIR}/config.json <<EOF
  "CFD_JSON": ${CFD_JSON}
}
EOF
  elif echo "$CFD_TOKEN" | grep -q '.'; then
    cat >>${SERVER_WORK_DIR}/config.json <<EOF
  "CFD_TOKEN": "${CFD_TOKEN}"
}
EOF
  fi
}

# 服务端卸载函数
server_uninstall() {
  if echo "$OS" | grep -qi 'openwrt'; then
    [ -s /etc/init.d/cfd_server ] && {
      /etc/init.d/cfd_server stop
      /etc/init.d/cfd_server disable
      rm -f /etc/init.d/cfd_server
    }
    [ -d ${SERVER_WORK_DIR} ] && rm -rf ${SERVER_WORK_DIR} /tmp/cloudflared.log
  elif echo "$OS" | egrep -qi 'debian|centos'; then
    [ -s /etc/systemd/system/cfd_server.service ] && {
      systemctl disable --now cfd_server
      rm -f /etc/systemd/system/cfd_server.service
    }
    [ -d ${SERVER_WORK_DIR} ] && rm -rf ${SERVER_WORK_DIR} /tmp/cloudflared.log
  else
    echo "Error: 未知的操作系统。" && exit 1
  fi
  echo "cfd_return 服务端已卸载。"
}

# 服务端启动函数
server_start() {
  if echo "$OS" | grep -qi 'openwrt'; then
    /etc/init.d/cfd_server enable
    /etc/init.d/cfd_server start
  elif echo "$OS" | egrep -qi 'debian|centos'; then
    systemctl enable --now cfd_server
  else
    echo "Error: 未知的操作系统。" && exit 1
  fi
  echo -e "\n服务端已启动。"
  echo -e "\nCloudflare tunnel 运行日志: /tmp/cloudflared.log"
  show_client_cmd
}

# 服务端停止函数
server_stop() {
  if echo "$OS" | grep -qi 'openwrt'; then
    /etc/init.d/cfd_server stop
    /etc/init.d/cfd_server disable
  elif echo "$OS" | egrep -qi 'debian|centos'; then
    systemctl stop cfd_server
    systemctl disable cfd_server
  else
    echo "Error: 未知的操作系统。" && exit 1
  fi
  echo -e "\n服务端已停止。"
}

# 获取配置信息
get_config() {
  if [ -s ${SERVER_WORK_DIR}/config.json ]; then
    CONFIG=$(cat ${SERVER_WORK_DIR}/config.json)
    WS_PATH=$(echo "$CONFIG" | awk -F '"' '/WS_PATH/{print $4}')
    CFD_PORT=$(echo "$CONFIG" | sed -n "/CFD_PORT/s/.*: \([^,]\+\),/\1/gp")
    CFD_DOMAIN=$(echo "$CONFIG" | awk -F '"' '/CFD_DOMAIN/{print $4}')
    CFD_TOKEN=$(echo "$CONFIG" | awk -F '"' '/CFD_TOKEN/{print $4}')
    CFD_JSON=$(echo "$CONFIG" | sed -n '/CFD_JSON/s/.*\({.*}\).*/\1/p')
  else
    echo "Error: 未找到配置文件。" && exit 1
  fi
}

# 显示客户端安装命令
show_client_cmd() {
  get_config
  echo -e "\n客户端安装命令：\nbash <(wget --no-check-certificate -qO- https://raw.githubusercontent.com/yuehen7/cfd_return/main/cfd_return.sh) -c -d $CFD_DOMAIN -w $WS_PATH -r <映射服务端使用的socks5端口>\n"
}

# 客户端安装函数
client_install() {
  echo "$OS" | egrep -qiv "debian|centos|alpine" && echo "Error: 当前操作系统是: ${OS}，服务端只支持 CentOS, Debian, Ubuntu 和 Alpine。" && exit 1

  echo ""
  [ -z "$CFD_DOMAIN_INPUT" ] && read -rp "请输入回源到服务端的 Cloudflare tunnel 域名: " CFD_DOMAIN_INPUT
  CFD_DOMAIN=$(echo "$CFD_DOMAIN_INPUT" | sed 's/^[ ]*//; s/[ ]*$//')
  [ -z "$CFD_DOMAIN" ] && echo "Error: 请输入服务端的域名。" && exit 1

  until [[ "$REMOTE_PORT_INPUT" =~ ^[0-9]+$ && "$REMOTE_PORT_INPUT" -ge 1 && "$REMOTE_PORT_INPUT" -le 65535 ]]; do
    echo ""
    unset REMOTE_PORT_INPUT
    [ -z "$REMOTE_PORT_INPUT" ] && read -rp "请输入服务端的端口: " REMOTE_PORT_INPUT
  done
  REMOTE_PORT=$REMOTE_PORT_INPUT
  [ -z "$REMOTE_PORT" ] && echo "Error: 请输入服务端的端口。" && exit 1

  echo ""
  [ -z "$WS_PATH_INPUT" ] && read -rp "请输入服务端的 ws 路径: " WS_PATH_INPUT
  WS_PATH=$(echo "$WS_PATH_INPUT" | sed 's/^[ ]*//; s/[ ]*$//')
  [ -z "$WS_PATH" ] && echo "Error: 请输入服务端的 ws 路径。" && exit 1

  [ "$(type -p netstat)" ] && local CMD=netstat || local CMD=ss

  # 查找未被占用的端口
  local START_PORT=10000
  local END_PORT=65535
  local SOCKS5_PORT

  for ((SOCKS5_PORT = $START_PORT; SOCKS5_PORT <= $END_PORT; SOCKS5_PORT++)); do
    ! $CMD -tuln | grep -q ":$SOCKS5_PORT" && break
  done

  local GOST_API_URL="https://api.github.com/repos/go-gost/gost/releases/latest"

  local GOST_URL_DEFAULT="https://github.com/go-gost/gost/releases/download/v3.0.0/gost_3.0.0_linux_${ARCH}${IS_AMD64V3}.tar.gz"

  [ ! -d ${TMP_DIR} ] && mkdir -p ${TMP_DIR}

  if [ "$(type -p wget)" ]; then
    echo -e "\n下载 gost"
    local GOST_URL=$(wget --no-check-certificate -qO- ${GH_PROXY}${GOST_API_URL} | sed -n "s/.*browser_download_url.*\"\(https:.*linux_${ARCH}${IS_AMD64V3}.tar.gz\)\"/\1/gp")
    GOST_URL=${GOST_URL:-${GOST_URL_DEFAULT}}
    wget --no-check-certificate -O- ${GH_PROXY}${GOST_URL} | tar xzv -C ${TMP_DIR} gost

  elif [ "$(type -p curl)" ]; then
    echo -e "\n下载 gost"
    local GOST_URL=$(curl -sSL ${GH_PROXY}${GOST_API_URL} | sed -n "s/.*browser_download_url.*\"\(https:.*linux_${ARCH}${IS_AMD64V3}.tar.gz\)\"/\1/gp")
    GOST_URL=${GOST_URL:-${GOST_URL_DEFAULT}}
    curl -L ${GH_PROXY}${GOST_URL} | tar xzv -C ${TMP_DIR} gost
  fi

  [ -s ${TMP_DIR}/gost ] && chmod +x ${TMP_DIR}/gost && mkdir -p ${CLIENT_WORK_DIR} && mv ${TMP_DIR}/gost ${CLIENT_WORK_DIR}/gost && rm -rf ${TMP_DIR} || { echo "Error: 下载 gost 失败。" && exit 1; }

  if echo "$OS" | grep -qi 'alpine'; then
    cat >/etc/init.d/cfd_client <<EOF
#!/sbin/openrc-run

name="cfd_client"
description="CFD Return Client Service"

SOCKS5_PORT=${SOCKS5_PORT}
REMOTE_PORT=${REMOTE_PORT}
CFD_DOMAIN=${CFD_DOMAIN}
WS_PATH=${WS_PATH}

: \${cfgfile:=${CLIENT_WORK_DIR}}

command="${CLIENT_WORK_DIR}/gost"
command_args_local="-D -L socks5://[::1]:\${SOCKS5_PORT}"
command_args_remote="-D -L rtcp://:\${REMOTE_PORT}/[::1]:\${SOCKS5_PORT} -F relay+ws://\${CFD_DOMAIN}:80?path=/\${WS_PATH}&host=\${CFD_DOMAIN}"

pidfile_local="/var/run/gost-local.pid"
pidfile_remote="/var/run/gost-remote.pid"

depend() {
  need net
  after firewall
}

start_pre() {
  # 检查进程是否已经在运行
  if [ -f "\$pidfile_local" ] && kill -0 \$(cat "\$pidfile_local") 2>/dev/null; then
    eerror "Local SOCKS5 proxy is already running"
    return 1
  fi
  if [ -f "\$pidfile_remote" ] && kill -0 \$(cat "\$pidfile_remote") 2>/dev/null; then
    eerror "Remote RTCP proxy is already running"
    return 1
  fi
}

start() {
  ebegin "Starting CFD Return Client"

  # Start local SOCKS5 proxy
  start-stop-daemon --start --background \
    --make-pidfile --pidfile "\$pidfile_local" \
    --exec "\$command" -- \$command_args_local
  local ret1=\$?

  # Start remote RTCP proxy
  start-stop-daemon --start --background \
    --make-pidfile --pidfile "\$pidfile_remote" \
    --exec "\$command" -- \$command_args_remote
  local ret2=\$?

  # 检查两个进程是否都成功启动
  if [ \$ret1 -eq 0 ] && [ \$ret2 -eq 0 ]; then
    eend 0
  else
    eend 1
  fi
}

stop() {
  ebegin "Stopping CFD Return Client"

  local ret=0

  # Stop local SOCKS5 proxy
  if [ -f "\$pidfile_local" ]; then
    start-stop-daemon --stop --pidfile "\$pidfile_local" --retry TERM/30/KILL/5
    if [ \$? -eq 0 ]; then
      rm -f "\$pidfile_local"
    else
      ret=1
    fi
  fi

  # Stop remote RTCP proxy
  if [ -f "\$pidfile_remote" ]; then
    start-stop-daemon --stop --pidfile "\$pidfile_remote" --retry TERM/30/KILL/5
    if [ \$? -eq 0 ]; then
      rm -f "\$pidfile_remote"
    else
      ret=1
    fi
  fi

  eend \$ret
}

status() {
  local ret=0

  if [ -f "\$pidfile_local" ]; then
      einfo "Local SOCKS5 proxy status:"
      if kill -0 \$(cat "\$pidfile_local") 2>/dev/null; then
        einfo "Running"
      else
        ewarn "Not running (stale pidfile)"
        ret=1
      fi
  else
      ewarn "Local SOCKS5 proxy is not running"
      ret=1
  fi

  if [ -f "\$pidfile_remote" ]; then
    einfo "Remote RTCP proxy status:"
    if kill -0 \$(cat "\$pidfile_remote") 2>/dev/null; then
      einfo "Running"
    else
      ewarn "Not running (stale pidfile)"
      ret=1
    fi
  else
    ewarn "Remote RTCP proxy is not running"
    ret=1
  fi

  return \$ret
}
EOF
    chmod +x /etc/init.d/cfd_client

  elif echo "$OS" | egrep -qi 'debian|centos'; then
    cat >${CLIENT_WORK_DIR}/start.sh <<EOF
#!/bin/bash

SOCKS5_PORT=${SOCKS5_PORT}
REMOTE_PORT=${REMOTE_PORT}
CFD_DOMAIN=${CFD_DOMAIN}
WS_PATH=${WS_PATH}
GOST_PROG="${CLIENT_WORK_DIR}/gost"
GOST_LOCAL_PID="/var/run/gost-local.pid"
GOST_REMOTE_PID="/var/run/gost-remote.pid"

start() {
  echo "Starting local SOCKS5 proxy..."
  \$GOST_PROG -D -L socks5://[::1]:\${SOCKS5_PORT} >/dev/null 2>&1 &
  echo \$! > \$GOST_LOCAL_PID

  echo "Starting remote RTCP proxy..."
  \$GOST_PROG -D -L rtcp://:\${REMOTE_PORT}/[::1]:\${SOCKS5_PORT} -F "relay+ws://\${CFD_DOMAIN}:80?path=/\${WS_PATH}&host=\${CFD_DOMAIN}" >/dev/null 2>&1 &
  echo \$! > \$GOST_REMOTE_PID
}

stop() {
  echo "Stopping local SOCKS5 proxy..."
  if [ -f "\$GOST_LOCAL_PID" ]; then
    kill \$(cat \$GOST_LOCAL_PID)
    rm \$GOST_LOCAL_PID
  fi

  echo "Stopping remote RTCP proxy..."
  if [ -f "\$GOST_REMOTE_PID" ]; then
    kill \$(cat \$GOST_REMOTE_PID)
    rm \$GOST_REMOTE_PID
  fi
}

case "\$1" in
  start)
    start
    ;;
  stop)
    stop
    ;;
  restart)
    stop
    start
    ;;
  *)
    echo "Usage: \$0 {start|stop|restart}"
    exit 1
    ;;
esac

exit 0
EOF
    chmod +x ${CLIENT_WORK_DIR}/start.sh

    cat >/etc/systemd/system/cfd_client.service <<EOF
[Unit]
Description=CFD Return Client Service
After=network.target

[Service]
Type=forking
ExecStart=${CLIENT_WORK_DIR}/start.sh start
ExecStop=${CLIENT_WORK_DIR}/start.sh stop
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF
  fi
}

# 客户端卸载函数
client_uninstall() {
  client_stop
  if echo "$OS" | grep -qi 'alpine'; then
    [ -d ${CLIENT_WORK_DIR} ] && rm -rf ${CLIENT_WORK_DIR} /etc/init.d/cfd_client
  elif echo "$OS" | egrep -qi 'debian|centos'; then
    [ -s /etc/systemd/system/cfd_client.service ] && {
      systemctl disable --now cfd_client
      rm -f /etc/systemd/system/cfd_client.service
    }
    [ -d ${CLIENT_WORK_DIR} ] && rm -rf ${CLIENT_WORK_DIR}
  else
    echo "Error: 未知的操作系统。" && exit 1
  fi
  echo "cfd_return 客户端已卸载。"
}

# 客户端启动函数
client_start() {
  if echo "$OS" | grep -qi 'alpine'; then
    rc-update add cfd_client default
    rc-service cfd_client start
  elif echo "$OS" | egrep -qi 'debian|centos'; then
    systemctl enable --now cfd_client
  else
    echo "Error: 未知的操作系统。" && exit 1
  fi
  echo -e "\n客户端已启动。"
}

# 客户端停止函数
client_stop() {
  if echo "$OS" | grep -qi 'alpine'; then
    rc-service cfd_client stop
    rc-update del cfd_client default
  elif echo "$OS" | egrep -qi 'debian|centos'; then
    systemctl disable --now cfd_client
  else
    echo "Error: 未知的操作系统。" && exit 1
  fi
  echo -e "\n客户端已停止。"
}

# 主程序开始

# 检查系统环境
check_os
check_install
check_arch

# 处理命令行参数
while getopts ":uhscnd:a:p:w:r:t:" OPTNAME; do
  case "${OPTNAME,,}" in
    'h' )
      echo -e "\n用法: bash <(wget --no-check-certificate -qO- https://raw.githubusercontent.com/yuehen7/cfd_return/main/cfd_return.sh) [选项]"
      echo -e "\n选项:"
      echo -e "  -h\t\t显示帮助信息"
      echo -e "  -u\t\t卸载 cfd_return (服务端和客户端)"
      echo -e "  -w\t\t服务端的 ws 路径 (服务端和客户端)"
      echo -e "  -d\t\t服务端的 Cloudflare tunnel 域名 (服务端和客户端)"
      echo -e "  -s\t\t安装服务端"
      echo -e "  -a\t\t服务端的 Cloudflare tunnel json 或 token 认证(服务端)，注意需要有单引号"
      echo -e "  -t\t\t服务端的优选 IP 列表 (服务端),可选 [4,6,d,n]，d是双栈，n是不进行优选，默认为双栈 d"
      echo -e "  -p\t\t服务端的端口 (服务端)"
      echo -e "  -n\t\t显示客户端安装命令 (服务端)"
      echo -e "  -c\t\t安装客户端"
      echo -e "  -r\t\t映射服务端使用的 socks5 端口 (客户端)"
      echo -e "\n示例:"
      echo -e "  安装服务端: bash <(wget --no-check-certificate -qO- https://raw.githubusercontent.com/yuehen7/cfd_return/main/cfd_return.sh) -s -p 20000 -d cfd.argo.com -w 3b451552-e776-45c5-9b98-bde3ab99bf75 -t 4 -a 'eyJhIjoiOWN...'"
      echo -e "\n  安装客户端: bash <(wget --no-check-certificate -qO- https://raw.githubusercontent.com/yuehen7/cfd_return/main/cfd_return.sh) -c -r 30000 -d cfd.argo.com -w 3b451552-e776-45c5-9b98-bde3ab99bf75"
      echo -e "\n  卸载 cfd_return: bash <(wget --no-check-certificate -qO- https://raw.githubusercontent.com/yuehen7/cfd_return/main/cfd_return.sh) -u"
      echo ""
      exit 0
      ;;
    'u' )
      echo $IS_INSTALL_SERVER | grep -q 'installed' && server_uninstall
      echo $IS_INSTALL_CLIENT | grep -q 'installed' && client_uninstall
      exit 0
      ;;
    's' )
      CHOOSE=1
      ;;
    'c' )
      CHOOSE=2
      ;;
    'd' )
      CFD_DOMAIN_INPUT="$OPTARG"
      ;;
    'a' )
      CFD_AUTH_INPUT="$OPTARG"
      ;;
    'p' )
      CFD_PORT_INPUT="$OPTARG"
      ;;
    'w' )
      WS_PATH_INPUT="$OPTARG"
      ;;
    'r' )
      REMOTE_PORT_INPUT="$OPTARG"
      ;;
    'n' )
      show_client_cmd
      exit 0
      ;;
    't' )
      STACK_INPUT="$OPTARG"
      ;;
  esac
done

# 主菜单逻辑
if [[ "${IS_INSTALL_SERVER}@${IS_INSTALL_CLIENT}" =~ 'installed' ]]; then
  # 已安装情况下的菜单选项
  until echo "$CHOOSE" | egrep -qiw '[1-6]'; do
    description
    echo -e "\n检测到已安装 cfd_return\n1. 开启服务端\n2. 停止服务端\n3. 开启客户端\n4. 停止客户端\n5. 卸载服务端和服务端\n6. 退出" && read -rp "请选择: " CHOOSE
    echo "$CHOOSE" | egrep -qiw '[1-6]' && break || { echo "Error: 请输入正确的数字。" && sleep 1; }
  done
  case "$CHOOSE" in
    1 )
      server_start
      exit 0
      ;;
    2 )
      server_stop
      exit 0
      ;;
    3 )
      client_start
      exit 0
      ;;
    4 )
      client_stop
      exit 0
      ;;
    5 )
      echo $IS_INSTALL_SERVER | grep -q 'installed' && server_uninstall
      echo $IS_INSTALL_CLIENT | grep -q 'installed' && client_uninstall
      exit 0
      ;;
    6 )
      exit 0
      ;;
  esac
else
  # 未安装情况下的菜单选项
  until echo "$CHOOSE" | egrep -qiw '[1-3]'; do
    description
    echo -e "\n1. 安装服务端\n2. 安装客户端\n3. 退出" && read -rp "请选择: " CHOOSE
    echo "$CHOOSE" | egrep -qiw '[1-3]' && break || { echo "Error: 请输入正确的数字。" && sleep 1; }
  done
  case "$CHOOSE" in
    1 )
      server_install
      server_start
      exit 0
      ;;
    2 )
      client_install
      client_start
      exit 0
      ;;
    3 )
      exit 0
      ;;
  esac
fi
