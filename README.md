# CLOUD-MAIL-Enhanced SMTP-to-HTTP 网关（Linux + Docker Compose）

这是一个小型 SMTP-to-HTTP 网关：旧项目继续使用 SMTP，网关把收到的 RFC 5322/MIME 邮件通过 HTTPS 转发到 Cloud Mail 的 `/api/smtp/send`。

```text
旧项目 / 邮件客户端 -- SMTP AUTH --> smtp-gateway -- HTTPS + Basic Auth --> Cloud Mail Worker
```

> **部署范围**：网关只支持 Linux + Docker Engine + Docker Compose。提供的 `install.sh` 只负责复制配置、构建 Docker 镜像、执行上游健康检查并启动 Compose 服务；它不会安装 Node.js、systemd 或其他宿主机服务。

## 一、功能和限制

- 支持 SMTP AUTH PLAIN 和 AUTH LOGIN。
- 接收普通文本、HTML、Cc、Bcc 和 MIME 附件。
- 上游 Cloud Mail 健康检查通过后才启动 SMTP 监听。
- 容器内置 Docker healthcheck，持续检查 Cloud Mail 上游是否正常。
- Compose 文件和安装脚本使用同一套健康检查命令；启动前检查失败不会继续启动，启动后 healthcheck 失败会被报告为 unhealthy。
- 上游返回成功后才向 SMTP 客户端返回成功；上游失败会让本次 SMTP DATA 失败，避免误报“已发送”。
- 默认监听 `2525`，不监听特权端口 `25`。
- 当前默认关闭 STARTTLS。生产环境请只在可信内网使用，或在网关前增加支持 TLS 的反向代理/SMTP 代理。
- 健康检查只验证配置、发件账号和 Cloud Mail 发信服务商，不发送真实邮件。

## 二、前置条件

在 Linux 服务器上准备：

- Docker Engine 20.10 或更高版本；
- Docker Compose v2（命令为 `docker compose`）；
- 已部署并可通过 HTTPS 访问的 Cloud Mail Worker；
- Cloud Mail 管理员账号；
- 一个已经在 Cloud Mail 中存在且可发信的默认发件账号；
- 防火墙只向需要使用 SMTP 的应用开放端口 `2525`。

检查 Docker：

```bash
docker --version
docker compose version
```

如果系统只有旧版 `docker-compose`，建议升级到 Docker Compose v2，不建议混用两种命令。

## 三、先配置 Cloud Mail

### 1. 管理员网页配置

1. 使用 Cloud Mail 管理员账号登录网页。
2. 打开“系统设置”。
3. 找到“SMTP-to-HTTP 网关”配置卡片。
4. 填写并保存：
   - **启用 SMTP HTTP**：启用后网关才能调用 Cloud Mail；
   - **SMTP 用户名**：网关访问 HTTP API 时使用的用户名；
   - **默认发件账号**：必须是 Cloud Mail 中已经存在的发件账号；
   - **SMTP API Key**：网关访问 Cloud Mail 的密钥；
   - **最大邮件大小**：默认 `10485760` 字节，即 10 MiB。
5. 点击“测试”，确认显示配置正常后再保存。

只有管理员账号可以读取、测试、保存 SMTP 配置。普通用户不会看到配置卡片，直接调用配置 API 也会返回 `403`。API Key 在网页和普通设置接口中只显示掩码。

### 2. Cloud Mail API 地址

假设 Cloud Mail 的公开地址为 `https://mail.example.com`：

```text
健康检查： https://mail.example.com/api/smtp/health
发信接口： https://mail.example.com/api/smtp/send
```

网关的 `upstream.user` 必须与 Cloud Mail 网页中的 SMTP 用户名一致，`upstream.apiKey` 使用同一个 SMTP API Key。不要把本地 SMTP 密码和 Cloud Mail API Key 设置成同一个值。

## 四、使用安装脚本部署网关

安装脚本只适用于 Linux，并且要求已经安装 Docker Engine 和 Docker Compose v2。脚本不会安装 Node.js，也不会创建 systemd 服务。

先把 `smtp-gateway` 目录复制到 Linux 服务器，然后进入目录：

```bash
cd smtp-gateway
chmod +x install.sh
```

### 方式 A：先准备配置，再执行安装

```bash
cp config.example.json config.json
sudo chown root:root config.json
chmod 640 config.json
vi config.json
sudo ./install.sh
```

### 方式 B：让脚本从指定文件复制配置

```bash
chmod 600 /path/to/cloud-mail-smtp.json
sudo ./install.sh --config /path/to/cloud-mail-smtp.json
```

如果还没有 `config.json`，脚本会自动创建模板并停止，不会启动网关。你必须填写真实的 Cloud Mail 地址、SMTP 用户名、API Key、本地 SMTP 密码和默认发件账号后，再次执行脚本。

安装脚本会严格按以下顺序执行：

1. 检查当前系统是否为 Linux；
2. 检查 Docker Engine 和 Docker Compose v2；
3. 复制网关文件并设置 `config.json` 为 `root:root`、`640`（容器以 UID 1000/GID 0 读取）；
4. 执行 `docker compose config`；
5. 构建 Docker 镜像；
6. 校验网关配置；
7. 调用 Cloud Mail `/api/smtp/health` 做真实上游连通性检查；
8. 只有健康检查成功，才执行 `docker compose up`；
9. 启动后等待 Docker healthcheck 变成 `healthy`。

任何一步失败，脚本都会退出，并且上游检查失败时不会启动 SMTP 网关。默认安装目录是 `/opt/cloud-mail-smtp-gateway`，可通过 `--dir` 修改：

```bash
sudo ./install.sh --dir /srv/cloud-mail-smtp-gateway
```

如果目标目录已有 `config.json`，脚本默认保留现有配置。使用 `--config` 替换配置时，需要确认；自动化部署可以使用 `--yes`：

```bash
sudo ./install.sh --config /path/to/cloud-mail-smtp.json --yes
```

安装成功后，脚本会打印 SMTP 映射地址和日志命令。常用管理命令：

```bash
cd /opt/cloud-mail-smtp-gateway
docker compose ps
docker compose logs -f smtp-gateway
docker compose stop
docker compose start
docker compose down
```

> `config.json` 包含密钥，不要提交 Git，不要通过工单、聊天或公开网盘分享。

配置示例：

```json
{
  "listen": {
    "host": "0.0.0.0",
    "port": 2525
  },
  "smtp": {
    "user": "legacy-app",
    "password": "change-me-local",
    "maxMessageSize": 10485760
  },
  "upstream": {
    "url": "https://mail.example.com/api/smtp/send",
    "healthUrl": "https://mail.example.com/api/smtp/health",
    "user": "smtp-client",
    "apiKey": "replace-with-cloud-mail-smtp-api-key",
    "timeoutMs": 15000
  }
}
```

字段说明：

| 字段 | 说明 |
| --- | --- |
| `listen.host` | 容器内监听地址，通常保持 `0.0.0.0`。 |
| `listen.port` | 容器内 SMTP 端口，默认 `2525`。不要改成 25，除非你明确了解 Linux 特权端口和 Docker 权限。 |
| `smtp.user` | 旧项目连接网关时使用的 SMTP 用户名。 |
| `smtp.password` | 旧项目连接网关时使用的本地 SMTP 密码；不是 Cloud Mail API Key。 |
| `smtp.maxMessageSize` | 单封邮件上限，默认 10 MiB，至少 1024 字节。 |
| `upstream.url` | Cloud Mail 的发信 API，必须是 HTTPS；仅允许 localhost 测试时使用 HTTP。 |
| `upstream.healthUrl` | Cloud Mail 的健康检查 API。 |
| `upstream.user` | Cloud Mail SMTP HTTP Basic Auth 用户名。 |
| `upstream.apiKey` | Cloud Mail SMTP API Key。 |
| `upstream.timeoutMs` | 单次上游请求超时时间，默认 15000 毫秒。 |

## 五、启动前验证上游连通性

先验证配置格式：

```bash
docker compose run --rm smtp-gateway node src/cli.js validate --config /app/config.json
```

再验证 Cloud Mail 是否可连接且发件服务是否正常：

```bash
docker compose run --rm smtp-gateway node src/cli.js test --config /app/config.json
```

只有同时满足以下条件，测试才会通过：

- DNS 和 HTTPS 可用；
- `upstream.user` 和 `upstream.apiKey` 正确；
- Cloud Mail SMTP HTTP 已启用；
- 默认发件账号存在且未删除；
- Cloudflare Email 绑定或 Resend 配置可用。

测试不会发送真实邮件，因此通过测试后仍建议用测试收件地址发送一封实际邮件。

## 六、启动、停止和查看日志

启动并后台运行：

```bash
docker compose up -d --build
```

查看容器和 health 状态：

```bash
docker compose ps
```

持续查看日志：

```bash
docker compose logs -f smtp-gateway
```

停止容器但保留容器：

```bash
docker compose stop
```

重新启动：

```bash
docker compose start
```

停止并删除容器（不会删除 `config.json`）：

```bash
docker compose down
```

配置或代码更新后重建：

```bash
docker compose up -d --build --force-recreate
```

查看最近 200 行日志：

```bash
docker compose logs --tail=200 smtp-gateway
```

Compose 已配置 `restart: unless-stopped`、以容器 UID 1000/GID 0 运行、只读根文件系统、只读配置挂载、临时 `/tmp`、丢弃 Linux capabilities 和 `no-new-privileges`。安装脚本会把配置设为宿主机上的 `root:root`、`640`，以便网关进程读取而不向其他普通用户开放。如果需要修改配置，先编辑宿主机的 `config.json`，再执行 `docker compose up -d --force-recreate`。

## 七、旧项目或邮件客户端的 SMTP 设置

把原来 SMTP 服务商的配置改为网关地址：

| 项目 | 值 |
| --- | --- |
| SMTP 主机 | 部署网关的 Linux 服务器地址或内网域名 |
| SMTP 端口 | `2525`（如果修改了 Compose 端口映射，以实际映射为准） |
| 用户名 | `config.json` 中的 `smtp.user` |
| 密码 | `config.json` 中的 `smtp.password` |
| 加密 | 当前网关默认不提供 STARTTLS |
| 认证 | AUTH PLAIN 或 AUTH LOGIN |

如果旧程序强制要求 TLS，请不要直接把它连接到当前 2525 端口；应在网关前增加 TLS SMTP 代理，或者等待后续实现 STARTTLS。

## 八、安全建议

1. 只在内网或 VPN 中暴露 SMTP 端口，不要直接把 2525 暴露到公网。
2. 使用高强度、随机的本地 `smtp.password`，并与 Cloud Mail API Key 分开。
3. 保持 `root:root` 和 `chmod 640 config.json`，并限制服务器上可以读取该文件的用户。
chmod 640 config.json`，并限制服务器上可以读取该文件的用户。
4. Cloud Mail API Key 只授予 SMTP 所需权限，泄露后立即在 Cloud Mail 管理员页面更换。
5. 使用防火墙限制来源 IP；不要让整个互联网都能访问 SMTP 端口。
6. 通过 HTTPS 访问 Cloud Mail，确认服务器时间、CA 证书和 DNS 正常。
7. 定期查看 `docker compose logs`，关注认证失败、上游失败和异常流量。
8. 不要把含有真实密钥的 `config.json` 放入镜像、Git 仓库或备份公开目录。
9. 当前没有 STARTTLS，邮件内容在网关与 SMTP 客户端之间不是加密传输；生产环境应使用 TLS 网络或可信内网。

## 九、常见问题

### 1. `Configuration is invalid`

检查 JSON 格式、端口范围、SMTP 用户名/密码、上游 URL、API Key 和超时时间。可以重新复制模板：

```bash
cp config.example.json config.json
sudo chown root:root config.json
chmod 640 config.json
```

### 2. `Upstream health check failed: 401`

通常是 `upstream.user` 或 `upstream.apiKey` 错误。确认使用的是 Cloud Mail 的 SMTP API Key，而不是登录密码或本地 SMTP 密码。

### 3. `Upstream health check failed: 503`

检查 Cloud Mail 的 SMTP HTTP 是否启用、默认发件账号是否存在、Cloudflare Email/Resend 是否已正确配置，并查看 Cloud Mail Worker 日志。

### 4. 容器不停重启

网关启动前必须通过健康检查。执行：

```bash
docker compose ps
docker compose logs --tail=200 smtp-gateway
docker compose run --rm smtp-gateway node src/cli.js test --config /app/config.json
```

### 5. SMTP 客户端认证失败

确认客户端使用的是 `smtp.user` 和 `smtp.password`，不是 `upstream.user` 和 `upstream.apiKey`。同时确认客户端启用了 SMTP AUTH PLAIN 或 LOGIN。

### 6. 邮件显示发送成功但收件人未收到

网关的“成功”只表示 Cloud Mail 接受了邮件。请继续检查 Cloud Mail 使用的 Cloudflare Email 或 Resend 服务商投递状态、收件人地址、垃圾邮件目录和域名 DNS。

### 7. 如何升级

备份配置后替换代码文件，再重新构建：

```bash
cp config.json config.json.bak
docker compose down
docker compose up -d --build --force-recreate
```

升级后先看日志，再使用测试收件地址发送一封小邮件。

## 十、目录说明

```text
smtp-gateway/
├── config.example.json   # 配置模板，不含真实密钥
├── docker-compose.yml     # Linux Docker Compose 部署文件
├── install.sh              # Linux 安装、健康检查和启动脚本
├── Dockerfile             # Node 20 Alpine 镜像
├── package.json            # 运行依赖和命令
├── src/config.js          # 配置加载与校验
├── src/server.js          # SMTP 服务与 HTTPS 转发
└── src/cli.js             # validate、test、start 命令
```

项目不提供 Windows 安装方式。`install.sh` 只支持 Linux，并且只调用 Docker Compose；它不会在宿主机安装 Node.js、systemd 或其他常驻服务。


## 十一、感谢

感谢 Cloud Mail 原项目作者和社区贡献者提供的开源基础。本网关是围绕 Cloud Mail SMTP HTTP 接口开发的独立增强组件，感谢所有参与测试、反馈问题和提出改进建议的朋友。

如果网关对你有帮助，欢迎访问并 Star [CLOUD-MAIL-Enhanced-smtp-gateway](https://github.com/maillab/CLOUD-MAIL-Enhanced-smtp-gateway)，也欢迎提交 Issue 和 Pull Request。