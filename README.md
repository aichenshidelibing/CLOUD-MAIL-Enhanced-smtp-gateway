# CLOUD-MAIL-Enhanced SMTP-to-HTTP Gateway

一个面向 Linux + Docker 的小型 SMTP-to-HTTP 网关：业务系统通过标准 SMTP 提交邮件，网关在本地完成 SMTP AUTH 和 STARTTLS，然后通过 HTTPS + Basic Auth 调用 **CLOUD-MAIL-Enhanced** 的 SMTP HTTP API。

> 本项目感谢 [CLOUD-MAIL](https://github.com/maillab/cloud-mail) 原项目作者和所有贡献者提供的开源基础，也感谢参与测试、反馈和改进建议的朋友。

## 1. 工作方式

```text
业务项目 / 业务 Docker 容器
        │ SMTP AUTH + STARTTLS
        ▼
cloud-mail-smtp-gateway:2525
        │ HTTPS + Basic Auth
        ▼
CLOUD-MAIL-Enhanced /api/smtp/send
```

网关默认要求：**先 STARTTLS，再 AUTH**。网关到 CLOUD-MAIL 的链路始终使用 HTTPS（只有 localhost 测试才允许 HTTP）。

## 2. 最重要的 Docker 连接说明

如果业务项目也是 Docker，业务容器中的 `127.0.0.1` 指向业务容器自己，不是宿主机，因此不能写：

```text
SMTP_HOST=127.0.0.1
SMTP_PORT=12525
```

### 推荐：使用共享 Docker 网络

安装脚本会创建名为 `cloud-mail-smtp` 的 Docker 网络。将业务容器加入该网络：

```bash
docker network connect cloud-mail-smtp <业务容器名>
```

然后业务项目使用：

```text
SMTP_HOST=smtp-gateway
SMTP_PORT=2525
SMTP_USERNAME=<CLOUD-MAIL SMTP 用户名>
SMTP_PASSWORD=<CLOUD-MAIL SMTP API Key>
SMTP_USE_TLS=true
SMTP_USE_STARTTLS=true
SMTP_TLS_MODE=starttls
```

注意：同一 Docker 网络内使用网关容器端口 `2525`，不要使用宿主机映射端口 `12525`。

如果业务项目使用自己的 `docker-compose.yml`，加入：

```yaml
networks:
  cloud-mail-smtp:
    external: true

services:
  your-app:
    networks:
      - default
      - cloud-mail-smtp
```

安装网关后，确认网络存在：

```bash
docker network inspect cloud-mail-smtp
```

### 备用：通过宿主机内网 IP

如果业务容器不能加入共享网络，可以把网关监听地址设为 `0.0.0.0`，并使用宿主机内网 IP：

```text
SMTP_HOST=<宿主机内网IP>
SMTP_PORT=12525
```

例如 `192.168.1.50:12525`。请使用防火墙只允许业务服务器访问该端口，不要直接暴露到公网。

## 3. STARTTLS 和证书

这是普通 SMTP + STARTTLS，不是 SMTPS/隐式 TLS：

| 项目 | 设置 |
| --- | --- |
| SMTP 端口 | 2525（共享 Docker 网络）或安装时映射的宿主机端口 |
| TLS 模式 | STARTTLS |
| SMTPS/SSL 465 | 不支持，不要选择隐式 TLS |
| AUTH | AUTH PLAIN 或 AUTH LOGIN |
| TLS 最低版本 | TLS 1.2 |
| AUTH 时机 | STARTTLS 成功后再认证 |

安装脚本默认生成自签名证书：

```text
/opt/cloud-mail-smtp-gateway/tls/server.crt
/opt/cloud-mail-smtp-gateway/tls/server.key
```

证书 SAN 默认包含 `smtp-gateway`、`localhost`、`127.0.0.1`，并尽量包含服务器内网 IP。也可以指定证书主机名：

```bash
sudo env CLOUD_MAIL_SMTP_TLS_HOSTNAME='smtp-gateway,mail-gateway,192.168.1.50' \
  ./install.sh --language zh
```

生产环境建议使用受信任 CA 签发的证书和私钥：

```bash
sudo env \
  CLOUD_MAIL_SMTP_TLS_CERT_FILE=/secure/certs/smtp-gateway.crt \
  CLOUD_MAIL_SMTP_TLS_KEY_FILE=/secure/certs/smtp-gateway.key \
  ./install.sh --reconfigure --yes
```

安装脚本不会在普通重新安装时覆盖已有证书。替换证书后执行：

```bash
cd /opt/cloud-mail-smtp-gateway
docker compose restart
```

使用自签名证书时，SMTP 客户端应信任 `tls/server.crt`。测试阶段可以关闭“验证服务器证书”，但生产环境不建议关闭证书校验。业务容器使用共享网络时，TLS 主机名应填写 `smtp-gateway`。

## 4. 安装

仅支持 Linux + Docker Compose v2，不提供 Windows 安装程序。

```bash
git clone https://github.com/aichenshidelibing/CLOUD-MAIL-Enhanced-smtp-gateway.git
cd CLOUD-MAIL-Enhanced-smtp-gateway
chmod +x install.sh
sudo ./install.sh
```

安装向导支持中文和英文：

```bash
sudo ./install.sh --language zh
sudo ./install.sh --language en
```

默认安装目录：`/opt/cloud-mail-smtp-gateway`。

向导会询问：

1. 宿主机 SMTP 监听地址；
2. 宿主机 SMTP 监听端口；
3. 邮件大小上限；
4. CLOUD-MAIL 根地址；
5. CLOUD-MAIL SMTP 用户名；
6. CLOUD-MAIL SMTP API Key；
7. 请求超时时间。

CLOUD-MAIL 地址可以写成：

```text
mail.example.com
https://mail.example.com
```

脚本会自动补全 `https://`，并生成 `/api/smtp/send` 与 `/api/smtp/health`。

本地 SMTP 用户名和密码自动跟随 CLOUD-MAIL SMTP 用户名/API Key，不会重复询问。

## 5. 安装顺序和失败行为

脚本按以下顺序执行：

1. 检查 Linux、Docker、Docker Compose、curl 和 openssl；
2. 复制网关文件；
3. 生成或保留 STARTTLS 证书；
4. 生成 `config.json` 和 `.env`；
5. 在创建网关容器前，由宿主机 curl 检查 CLOUD-MAIL 健康接口；
6. 健康接口必须返回 2xx 且响应包含 `ok=true`，否则立即退出，不创建或启动网关容器；
7. 创建共享 Docker 网络并校验 Compose；
8. 构建镜像；
9. 在容器创建前完成配置文件静态校验；
10. 启动网关并等待 Docker healthcheck 为 `healthy`；
11. 安装完成前执行真实 SMTP TCP 连接、STARTTLS 握手和 AUTH PLAIN 验证。

因此，如果 CLOUD-MAIL 地址、账号、API Key 或证书配置不正确，安装不会显示成功。

## 6. 非交互安装

```bash
sudo env \
  CLOUD_MAIL_LANGUAGE=en \
  CLOUD_MAIL_LISTEN_HOST=0.0.0.0 \
  CLOUD_MAIL_LISTEN_PORT=12525 \
  CLOUD_MAIL_ADDRESS=https://mail.example.com \
  CLOUD_MAIL_UPSTREAM_USER=my-app \
  CLOUD_MAIL_UPSTREAM_API_KEY='replace-with-real-key' \
  CLOUD_MAIL_SMTP_TLS_HOSTNAME='smtp-gateway' \
  ./install.sh --non-interactive --yes
```

支持的 TLS 变量：

```text
CLOUD_MAIL_SMTP_TLS_HOSTNAME     额外的证书 DNS/IP，逗号分隔，默认 smtp-gateway
CLOUD_MAIL_SMTP_TLS_CERT_FILE    外部证书文件；设置后不会自动覆盖证书 SAN
CLOUD_MAIL_SMTP_TLS_KEY_FILE     外部私钥文件
CLOUD_MAIL_SMTP_TLS_DAYS         自动证书有效期，默认 825 天
CLOUD_MAIL_SMTP_TLS_REGENERATE   设置为 1 强制重新生成自签名证书，默认 0
```

默认自签名证书会自动把以下地址写入 Subject Alternative Name（SAN）：

- `smtp-gateway`、`localhost`、`127.0.0.1`；
- `hostname -I` 和 `ip -4 addr` 检测到的所有非回环 IPv4；
- 安装服务器通过公网 IP 查询服务检测到的公网 IPv4（网络允许时）；
- `CLOUD_MAIL_SMTP_TLS_HOSTNAME` 中显式指定的 DNS/IP。

重新安装时，脚本会检查已有自签名证书是否包含当前自动检测到的 SAN。缺少地址时，会先生成带时间戳的 `.bak.*` 备份，再重新生成证书；已有 `config.json`、`.env` 和私钥不会因普通更新被删除。若使用 `CLOUD_MAIL_SMTP_TLS_CERT_FILE`/`CLOUD_MAIL_SMTP_TLS_KEY_FILE` 提供正式证书，脚本会原样复制，不会替换为自签名证书。

如果公网 IP 没有被自动查询到，可以显式指定（示例）：

```bash
CLOUD_MAIL_SMTP_TLS_HOSTNAME='smtp-gateway,38.246.245.105' \
  sudo ./install.sh --dir /opt/cloud-mail-smtp-gateway --yes
```

旧变量仍兼容：`CLOUD_MAIL_UPSTREAM_URL`、`CLOUD_MAIL_UPSTREAM_HEALTH_URL`、`CLOUD_MAIL_SMTP_USER`、`CLOUD_MAIL_SMTP_PASSWORD`。

## 7. 配置文件和端口映射

安装目录中的重要文件：

```text
config.json                 # 真实配置，含 API Key，不提交 Git
.env                        # 宿主机端口映射，不提交 Git
tls/server.crt              # STARTTLS 证书，不提交 Git
tls/server.key              # STARTTLS 私钥，不提交 Git
docker-compose.yml
```

如果向导输入：

```text
SMTP 监听地址：127.0.0.1
SMTP 监听端口：12525
```

`.env` 会写成：

```dotenv
SMTP_BIND_HOST=127.0.0.1
SMTP_PORT=12525
```

这只控制宿主机映射；容器内部始终监听 `0.0.0.0:2525`。业务 Docker 容器若加入共享网络，直接使用 `smtp-gateway:2525`，不受宿主机映射影响。

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

脚本会备份原有 `config.json`。代码或配置更新后：

```bash
docker compose up -d --build --force-recreate
```

## 9. 手工检查

检查上游：

```bash
docker compose run --rm --no-deps smtp-gateway node src/cli.js test --config /app/config.json
```

检查配置：

```bash
docker compose run --rm --no-deps smtp-gateway node src/cli.js validate --config /app/config.json
```

检查 STARTTLS 和 AUTH：

```bash
docker compose exec -T smtp-gateway node src/cli.js smtp-test --config /app/config.json
```

查看端口：

```bash
docker compose port smtp-gateway 2525
ss -lntp | grep 12525
```

## 10. Git 更新教程

推荐把 Git 仓库和运行目录分开。仓库用于更新代码，运行目录保存真实的 `config.json`、`.env` 和 TLS 证书：

```bash
cd /root/CLOUD-MAIL-Enhanced-smtp-gateway
git pull --ff-only
sudo ./install.sh --dir /opt/cloud-mail-smtp-gateway --yes
```

安装脚本会保留运行目录中的真实配置和证书，并重新复制代码、构建镜像、启动容器和执行健康检查。

如果要彻底重新生成配置，使用：

```bash
cd /root/CLOUD-MAIL-Enhanced-smtp-gateway
sudo ./install.sh --dir /opt/cloud-mail-smtp-gateway --reconfigure --yes
```

注意：不要在 `/opt/cloud-mail-smtp-gateway` 中直接执行 `git pull`，除非你明确把该目录初始化成 Git 仓库。只有当配置文件来自另一个路径时才使用 `--config /path/to/config.json`；不要把 `--config` 指向安装目录中的同一个 `config.json`，也不要用仓库中的 `config.example.json` 覆盖生产配置。
## 11. 安全建议

- 不要提交 `config.json`、`.env`、API Key、私钥或自签名证书。
- `config.json` 和私钥仅允许 root/网关服务账号读取。
- Docker bridge 网络本身不是加密层；STARTTLS 才负责 SMTP 链路加密。
- 仅允许可信业务容器或内网 IP 访问 SMTP 端口。
- 不要把 2525/12525 直接暴露到公网。
- CLOUD-MAIL 必须使用有效 HTTPS 证书；API Key 泄露后应立即在管理员页面撤销并重新生成。
- 生产环境使用受信任 CA 证书，客户端开启服务器证书校验。

## 12. 故障排查

### `dial tcp 127.0.0.1:12525: connect: connection refused`

这是因为调用方在 Docker 容器中，`127.0.0.1` 指向调用方容器自身。将调用方加入 `cloud-mail-smtp` 网络并改用：

```text
smtp-gateway:2525
```

或者改用宿主机内网 IP + `12525`。

### `STARTTLS is required before AUTH`

客户端没有启用 STARTTLS，或选择了错误的 SMTPS/SSL 模式。请使用普通 SMTP 端口，并打开 STARTTLS。

### 证书验证失败

测试环境信任 `/opt/cloud-mail-smtp-gateway/tls/server.crt`。生产环境更换为受信任 CA 证书，并确保客户端连接的主机名或 IP 出现在证书 SAN 中。

查看当前证书 SAN：

```bash
openssl x509 \
  -in /opt/cloud-mail-smtp-gateway/tls/server.crt \
  -noout -subject -issuer -ext subjectAltName
```

如果看到类似 `certificate is valid for 127.0.0.1 ... not 38.246.245.105`，说明旧证书是在未包含公网 IP 时生成的。先从 Git 更新安装脚本，再重新安装；脚本会自动检测并备份后重生成。也可以用上面的 `CLOUD_MAIL_SMTP_TLS_HOSTNAME='smtp-gateway,38.246.245.105'` 显式补充公网 IP。客户端连接公网 IP 时使用 STARTTLS，并将该证书加入信任库；若使用受信任 CA 证书则不需要手动信任。

### Docker 网络不存在

重新运行安装脚本；脚本会自动创建 external network：

```bash
sudo ./install.sh --reconfigure --yes
```

## 感谢

感谢 CLOUD-MAIL 原项目作者、社区贡献者、测试人员和所有提供问题反馈的朋友。
