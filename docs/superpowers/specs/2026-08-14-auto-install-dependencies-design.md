# 自动安装运行依赖设计规格

日期：2026-08-14
项目：CLOUD-MAIL-Enhanced-smtp-gateway

## 1. 目标

改进 Linux 安装脚本，使其在执行网关安装前自动检测运行依赖；当推荐依赖不存在时，在用户明确以 root/sudo 运行安装脚本的前提下自动安装并启动服务。安装完成前必须再次验证 Docker Engine、Docker Compose Plugin 和相关命令可用。

## 2. 支持范围

- 首选并自动处理 Debian 和 Ubuntu。
- 仅支持 `apt-get`，不自动修改其他发行版的包管理器配置。
- 非 Debian/Ubuntu 系统显示当前发行版、缺失依赖和手动安装提示，然后安全退出。
- Windows 不在本安装脚本支持范围内；网关仍使用 Linux + Docker Compose。

## 3. 自动检测的依赖

### 基础命令

- `curl`
- `openssl`
- `getent`
- `awk`
- `sort`
- `tr`
- `cut`
- `hostname`
- `ss`（来自 `iproute2`）
- `mktemp`
- `install`

### Docker 运行时

优先安装 Docker 官方组件：

- `docker-ce`
- `docker-ce-cli`
- `containerd.io`
- `docker-buildx-plugin`
- `docker-compose-plugin`

不使用过时的 `docker-compose` v1，也不使用不受信任的第三方安装脚本。Docker 官方 GPG key 使用 `/etc/apt/keyrings/docker.asc`，软件源使用系统检测到的架构和发行版代号，并保持 `signed-by` 校验。

### Let’s Encrypt 条件依赖

只有启用 Let’s Encrypt 时才检测/安装 `certbot`。webroot 模式不自动占用或停止 TCP 80；现有 Nginx/Apache/Caddy 的路径映射仍由用户负责并由安装脚本进行公网挑战检查。

## 4. 安装流程

1. 解析命令行和环境变量中的语言、Let’s Encrypt、安装目录等设置。
2. 检查 Linux、root 权限和 `/etc/os-release`。
3. 识别 Debian/Ubuntu 及代号，检测 `apt-get`。
4. 检测基础工具；缺失时执行安全的 `apt-get update` 和 `apt-get install`。
5. 检测 Docker Engine、Docker CLI、Compose v2；缺失或版本不满足时配置 Docker 官方 APT 源并安装官方组件。
6. 启动 Docker 服务并设置开机自启；兼容 `systemctl` 和无 systemd 的 `service` 场景。
7. 用 `docker version`、`docker compose version` 和一个无副作用的 Docker CLI 检查确认运行时可用。
8. 如果启用 Let’s Encrypt，检测/安装 certbot；APT 源错误必须明确输出，不能关闭签名校验或删除全部软件源。
9. 继续现有 CLOUD-MAIL 配置、上游健康检查、STARTTLS 证书、Compose 构建、容器健康检查和 SMTP AUTH 测试流程。

## 5. 安全和幂等要求

- 自动安装仅在 root 下执行；普通用户收到 `sudo` 提示并退出。
- 所有 APT 操作使用 `DEBIAN_FRONTEND=noninteractive`，不使用 `--allow-unauthenticated`、不关闭 apt 签名校验、不使用 `curl | sh`。
- Docker 官方源和 key 的写入是幂等的，重复安装不会重复添加同一个源。
- 不自动删除或注释用户已有的 APT 源；如果已有失效源导致 `apt-get update` 失败，输出准确路径和修复命令。
- 不自动停止用户现有 Web 服务或 Docker 容器。
- 依赖安装失败时，不创建网关容器，不宣称安装成功。
- 增加 `--no-auto-install` 选项，便于严格环境只做检测而不改系统。

## 6. 语言和输出

依赖安装过程沿用现有 `--language zh|en` / `--lang` 选项。每个安装步骤输出：

- 正在检测的工具/组件；
- 将要安装的软件包；
- 安装失败的原因和可复制的手动命令；
- Docker 服务状态和 Compose 版本。

## 7. 测试方案

先增加失败回归检查，再实现：

- shell 语法检查；
- 安装脚本帮助信息包含自动依赖安装选项；
- 静态检查包含 Docker 官方源、`docker-compose-plugin`、`certbot` 条件检测和非 Debian/Ubuntu 退出分支；
- 使用隔离的 mock `command`/`apt-get`/`systemctl` 验证：已安装依赖不会重复安装、缺失依赖会安装、APT 失败不会继续创建 Docker 容器；
- 发布目录和源码目录的测试一致；
- `git diff --check`。

## 8. 不在本次范围内

- 自动配置用户未知的 Nginx/Apache/Caddy 虚拟主机；
- 自动修复用户已有的失效 APT 软件源；
- 自动申请 Cloudflare API、DNS-01 凭据；
- Windows 原生安装包；
- 在没有用户授权的情况下修改防火墙、安全组、云平台网络规则。