# CLOUD-MAIL-Enhanced SMTP-to-HTTP 网关

这是一个 Linux + Docker Compose 网关：旧项目继续使用 SMTP，网关接收 RFC 5322/MIME 邮件后，通过 HTTPS 转发到 CLOUD-MAIL 的 SMTP HTTP API。

```text
邮件客户端/旧项目 -- SMTP AUTH --> 网关 -- HTTPS + Basic Auth --> CLOUD-MAIL
```

## 1. 重要说明

- 仅支持 Linux、Docker Engine 和 Docker Compose v2；不提供 Windows 安装程序。
- 安装向导会生成真实的 `config.json`，并生成 Docker 使用的 `.env`。
- SMTP 监听地址和端口是**宿主机发布地址**。例如填写：
  - 地址：`127.0.0.1`
  - 端口：`12525`
  - 实际映射：`127.0.0.1:12525 -> 容器内 2525`
- `127.0.0.1` 只允许本机访问；需要远程项目访问时使用服务器内网地址或 `0.0.0.0`，并配合防火墙限制来源。
- 当前网关未实现 SMTP STARTTLS，因此旧项目中的“使用 TLS/为 SMTP 连接启用 TLS 加密”必须关闭。网关到 CLOUD-MAIL 的 HTTPS 通信仍然使用 TLS 加密。
- Docker bridge 网络本身不是额外加密层；真正的上游传输加密来自 `https://`。

## 2. CLOUD-MAIL 网页配置

使用 CLOUD-MAIL 管理员账号登录网页，在 SMTP-to-HTTP 网关设置中：

1. 启用 SMTP HTTP 功能；
2. 设置默认发件账号；
3. 设置 SMTP 用户名和 SMTP API Key；
4. 点击测试并保存。

只有管理员可以读取、测试和保存 SMTP 配置；普通用户没有设置权限，接口也会拒绝非管理员请求。

## 3. 从 Git 仓库安装

```bash
git clone https://github.com/aichenshidelibing/CLOUD-MAIL-Enhanced-smtp-gateway.git
cd CLOUD-MAIL-Enhanced-smtp-gateway
chmod +x install.sh
sudo ./install.sh
```

安装脚本支持中英文：

```bash
sudo ./install.sh --language zh
sudo ./install.sh --language en
# 或：sudo ./install.sh --lang en
```

默认安装目录：`/opt/cloud-mail-smtp-gateway`。也可以指定：

```bash
sudo ./install.sh --dir /srv/cloud-mail-smtp-gateway
```

## 4. 安装向导

首次运行会依次询问：

1. SMTP 宿主机监听地址；
2. SMTP 宿主机监听端口；
3. 单封邮件大小上限；
4. **Cloud Mail 根地址**；
5. Cloud Mail SMTP 用户名；
6. Cloud Mail SMTP API Key；
7. 请求超时时间。

Cloud Mail 根地址可以填写任意一种：

```text
mail.example.com
https://mail.example.com
```

脚本会自动补全协议，并自动生成：

```text
https://mail.example.com/api/smtp/send
https://mail.example.com/api/smtp/health
```

外部 CLOUD-MAIL 地址必须使用 HTTPS；仅 localhost 测试允许 HTTP。Cloud Mail 用户名和 API Key 会同时作为本地 SMTP 网关的用户名和密码，不会再重复询问本地 SMTP 凭据。

## 5. 安装检查顺序

安装脚本严格按以下顺序执行：

1. 检查 Linux、Docker 和 Docker Compose；
2. 生成 `config.json`；
3. 根据 `listen.host` 和 `listen.port` 生成 `.env`，确保端口设置实际生效；
4. **在创建或启动 Docker 网关容器之前**，使用宿主机 `curl` 访问 Cloud Mail 健康检查 URL；
5. 校验 HTTP 状态码并确认响应包含 `ok=true`；
6. 预检查失败时立即退出，不构建、不启动网关容器；
7. 预检查成功后校验 Compose、构建镜像并启动容器；
8. 启动后等待 Docker healthcheck 变为 `healthy`。

健康检查会使用 Cloud Mail SMTP 用户名/API Key 认证，但不会发送真实邮件。

## 6. 非交互安装

推荐使用一个 Cloud Mail 根地址：

```bash
sudo env \
  CLOUD_MAIL_LANGUAGE=en \
  CLOUD_MAIL_LISTEN_HOST=127.0.0.1 \
  CLOUD_MAIL_LISTEN_PORT=12525 \
  CLOUD_MAIL_ADDRESS=https://mail.example.com \
  CLOUD_MAIL_UPSTREAM_USER=my-app \
  CLOUD_MAIL_UPSTREAM_API_KEY='replace-with-real-key' \
  ./install.sh --non-interactive --yes
```

旧版变量仍兼容：

```text
CLOUD_MAIL_UPSTREAM_URL
CLOUD_MAIL_UPSTREAM_HEALTH_URL
CLOUD_MAIL_SMTP_USER
CLOUD_MAIL_SMTP_PASSWORD
```

## 7. 配置文件和端口映射

安装目录中的关键文件：

```text
config.json  # 真实配置，包含 API Key，不提交 Git
.env         # Docker 端口映射，不提交 Git
docker-compose.yml
```

示例配置：

```json
{
  "listen": {
    "host": "127.0.0.1",
    "port": 12525,
    "containerHost": "0.0.0.0",
    "containerPort": 2525
  }
}
```

`listen.host` 和 `listen.port` 控制宿主机映射；容器内部固定监听 `0.0.0.0:2525`。因此改完向导中的地址和端口后，脚本会把它们写入 `.env`，Compose 不会再回到默认的 `0.0.0.0:2525`。

## 8. 管理命令

```bash
cd /opt/cloud-mail-smtp-gateway
docker compose ps
docker compose logs -f smtp-gateway
docker compose restart
docker compose stop
docker compose start
docker compose down
```

重新配置：

```bash
sudo ./install.sh --reconfigure
```

脚本会先备份旧的 `config.json`。配置或代码更新后：

```bash
docker compose up -d --build --force-recreate
```

## 9. 手工验证

安装脚本已自动完成宿主机预检查。容器启动后可以手工验证：

```bash
docker compose run --rm --no-deps smtp-gateway node src/cli.js validate --config /app/config.json
docker compose run --rm --no-deps smtp-gateway node src/cli.js test --config /app/config.json
```

## 10. SMTP 客户端配置

| 项目 | 设置 |
| --- | --- |
| SMTP 主机 | 网关所在 Linux 服务器地址 |
| SMTP 端口 | 安装时填写的宿主机端口，例如 `12525` |
| 用户名 | Cloud Mail SMTP 用户名 |
| 密码 | Cloud Mail SMTP API Key |
| 认证 | AUTH PLAIN 或 AUTH LOGIN |
| 使用 TLS | **关闭** |

关闭“使用 TLS”只针对客户端到本地 SMTP 网关这一段。网关到 CLOUD-MAIL 的请求仍然使用 HTTPS/TLS。若需要公网 SMTP，请在网关前增加支持 TLS 的 SMTP 代理或反向代理，不要直接暴露当前 2525 端口。

## 11. 安全建议

- 不要把真实 `config.json`、`.env` 或 API Key 提交到 Git。
- 让 `config.json` 只允许 root 或网关服务账号读取。
- 使用防火墙限制 SMTP 来源 IP。
- CLOUD-MAIL 使用正式 HTTPS 证书、正确 DNS 和有效 CA 链。
- API Key 泄露后立即在 CLOUD-MAIL 管理员页面撤销并重新生成。

## 12. Git 升级教程

```bash
cd /opt/cloud-mail-smtp-gateway
sudo cp config.json config.json.bak.$(date +%Y%m%d%H%M%S)
git pull --ff-only
sudo ./install.sh --dir /opt/cloud-mail-smtp-gateway --config config.json --yes
docker compose up -d --build --force-recreate
docker compose ps
docker compose logs --tail=100 smtp-gateway
```

如果使用 `--config`，请确保指定的是包含真实配置的安全文件；不要用仓库中的 `config.example.json` 覆盖真实配置。

## 感谢

感谢 CLOUD-MAIL 原项目作者和社区贡献者提供的开源基础，也感谢所有参与测试、反馈问题和提出改进建议的朋友。