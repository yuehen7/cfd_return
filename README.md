# 【CFD 反向回源一键脚本】

- 一个基于 Cloudflare Tunnel 的双向流量回源工具，支持 CentOS、Debian、Ubuntu、Alpine、OpenWRT 和 Kwrt 系统。
- 该项目fork自 **fscarmen** 大佬的项目 https://github.com/fscarmen/cfd_return
* * *

## 1. 支持的操作系统和架构

| | 系统 | 架构 |
| -- | -- | -- | 
| 服务端 | 类 CentOS,Debian,Ubuntu,OpenWRT | amd64 (x86_64),amd64 (x86_64),armv7 |
| 客户端 | 类 CentOS,Debian,Ubuntu,Alpine | amd64 (x86_64),amd64 (x86_64),armv7 |

## 2. 安装方法

### 2.1 服务端安装

#### 2.1.1 交互式安装：

```bash
bash <(wget -qO- https://raw.githubusercontent.com/yuehen7/cfd_return/main/cfd_return.sh)
```

#### 2.1.2 快捷参数安装：

```
bash <(wget -qO- https://raw.githubusercontent.com/yuehen7/cfd_return/main/cfd_return.sh) \
  -s \
  -p server-origin-port \
  -d your-domain.com \
  -w your-ws-path \
  -t 4 \
  -a 'your-cloudflare-auth'
```

### 2.2 客户端安装

#### 2.2.1 交互式安装：

```
bash <(wget -qO- https://raw.githubusercontent.com/yuehen7/cfd_return/main/cfd_return.sh)
```

#### 2.2.2 快捷参数安装：

```
bash <(wget -qO- https://raw.githubusercontent.com/yuehen7/cfd_return/main/cfd_return.sh) \
  -c \
  -r remote-socks5-port \
  -d your-domain.com \
  -w your-ws-path
```

## 3. 卸载方法

```
bash <(wget -qO- https://raw.githubusercontent.com/yuehen7/cfd_return/main/cfd_return.sh) -u
```

## 4. 命令行参数

| 参数 | 说明                    | 使用场景       |
| ---- | ----------------------- | -------------- |
| -h   | 显示帮助信息            | 服务端和客户端   |
| -u   | 卸载服务端和客户端      | 服务端和客户端   |
| -w   | WebSocket 路径          | 服务端和客户端 |
| -d   | Cloudflare Tunnel 域名  | 服务端和客户端 |
| -s   | 安装服务端              | 服务端         |
| -a   | Cloudflare Tunnel json 或 token 认证，注意值需要用单引号 | 服务端         |
| -t   | Cloudflared 优选 IP 列表 [4,6,d,n]，d是双栈，n是不进行优选，默认为双栈 d | 服务端 |
| -p   | 服务端端口              | 服务端         |
| -n   | 显示客户端安装命令      | 服务端         |
| -c   | 安装客户端              | 客户端         |
| -r   | 映射到服务端的 SOCKS5 端口  | 客户端         |

## 5. 使用示例

### 5.1 服务端完整安装示例：

```
bash <(wget -qO- https://raw.githubusercontent.com/yuehen7/cfd_return/main/cfd_return.sh) \
  -s \
  -p 20000 \
  -d cfd.example.com \
  -w 3b451552-e776-45c5-9b98-bde3ab99bf75 \
  -t 4 \
  -a 'eyJhIjoiOWN...'
```

### 5.2 客户端完整安装示例：

```
bash <(wget -qO- https://raw.githubusercontent.com/yuehen7/cfd_return/main/cfd_return.sh) \
  -c \
  -r 30000 \
  -d cfd.example.com \
  -w 3b451552-e776-45c5-9b98-bde3ab99bf75
```

### 5.3 查看客户端安装命令：

```
bash <(wget -qO- https://raw.githubusercontent.com/yuehen7/cfd_return/main/cfd_return.sh) -n
```

### 5.4 卸载所有组件：

```
bash <(wget -qO- https://raw.githubusercontent.com/yuehen7/cfd_return/main/cfd_return.sh) -u
```

## 6. 鸣谢
- [fscarmen](https://github.com/fscarmen)
