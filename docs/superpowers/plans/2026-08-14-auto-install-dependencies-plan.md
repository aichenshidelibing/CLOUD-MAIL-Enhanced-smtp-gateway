# 自动安装运行依赖 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 让 Linux 安装脚本自动检测并安装 Debian/Ubuntu 上推荐的 Docker、Compose、基础命令和可选 Certbot 依赖，并在安装失败时安全停止。

**Architecture:** 在现有 `install.sh` 的系统检查阶段之前加入幂等的依赖管理层。依赖管理层识别 Debian/Ubuntu、使用 Docker 官方 APT 源安装 Docker Engine + Compose v2，按需安装基础工具和 certbot；成功后才进入现有配置、证书、Cloud Mail 预检查和 Compose 流程。发布仓库与源码镜像目录保持同一份安装脚本、测试和 README。

**Tech Stack:** Bash 5-compatible shell, Debian/Ubuntu APT, Docker Engine, Docker Compose v2, existing shell regression tests.

---

### Task 1: Add failing dependency-management regression checks

**Files:**
- Modify: `publish-upload/CLOUD-MAIL-Enhanced-smtp-gateway/test/install-script.test.sh`
- Mirror: `smtp-gateway/test/install-script.test.sh`

- [ ] **Step 1: Add assertions for the public dependency-install behavior**

Add checks for all of the following strings/branches in `install.sh`: `--no-auto-install`, `ensure_runtime_dependencies`, `docker-compose-plugin`, `docker.asc`, `non_debian`, `systemctl enable --now docker`, and `CLOUD_MAIL_SMTP_AUTO_INSTALL`.

- [ ] **Step 2: Run the test before implementation**

Run:

```bash
bash -n publish-upload/CLOUD-MAIL-Enhanced-smtp-gateway/install.sh
bash publish-upload/CLOUD-MAIL-Enhanced-smtp-gateway/test/install-script.test.sh
```

Expected: FAIL because the dependency-management functions and option do not exist yet.

---

### Task 2: Implement OS detection and safe APT helpers

**Files:**
- Modify: `publish-upload/CLOUD-MAIL-Enhanced-smtp-gateway/install.sh`

- [ ] **Step 1: Add installer state and bilingual messages**

Add `AUTO_INSTALL_DEPENDENCIES` defaulting to `CLOUD_MAIL_SMTP_AUTO_INSTALL` or `1`, plus localized messages for OS detection, package installation, Docker setup, service startup, unsupported distributions, and manual repair.

- [ ] **Step 2: Add `detect_linux_distribution`**

Read `/etc/os-release` without executing it as code beyond the standard `.` parsing pattern, set `DISTRO_ID`, `DISTRO_VERSION_ID`, `DISTRO_CODENAME`, and accept only `debian` and `ubuntu`. On any other Linux distribution, print the detected values and exit with a manual-installation message.

- [ ] **Step 3: Add `apt_install_packages`**

Implement an idempotent helper:

```bash
apt_install_packages() {
  local packages=("$@")
  [ "${#packages[@]}" -gt 0 ] || return 0
  apt-get update || die "$(text apt_update_failed)"
  DEBIAN_FRONTEND=noninteractive apt-get install --no-install-recommends -y "${packages[@]}" \
    || die "$(text apt_install_failed): ${packages[*]}"
}
```

Do not use `--allow-unauthenticated`, do not disable signature verification, and do not edit unrelated existing APT entries. If an existing invalid source breaks `apt-get update`, show `grep -Rni` repair commands and stop.

- [ ] **Step 4: Add `ensure_base_commands`**

Map missing commands to Debian/Ubuntu packages (`curl`, `openssl`, `getent`/`hostname` via `libc-bin`, `ss` via `iproute2`, and `awk`/`sort`/`tr`/`cut`/`install`/`mktemp` via `gawk`, `coreutils`, and `util-linux` as needed), detect each command with `command -v`, and install only missing packages.

---

### Task 3: Implement Docker official repository installation and runtime validation

**Files:**
- Modify: `publish-upload/CLOUD-MAIL-Enhanced-smtp-gateway/install.sh`

- [ ] **Step 1: Add `ensure_docker_repository`**

Create `/etc/apt/keyrings`, download Docker’s signed key to `/etc/apt/keyrings/docker.asc`, set mode `0644`, and create an idempotent `/etc/apt/sources.list.d/docker.list` entry using the detected architecture, codename, and `https://download.docker.com/linux/<distro>` URL with `signed-by=/etc/apt/keyrings/docker.asc`. Fail if the codename cannot be determined; do not use `curl | sh`.

- [ ] **Step 2: Add `ensure_docker_runtime`**

Detect `docker` and `docker compose version`. If both are already usable, do not reinstall. Otherwise call `ensure_docker_repository`, then install:

```text
docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
```

Start Docker with `systemctl enable --now docker` when systemd is available; otherwise use `service docker start` and report that boot-time enablement could not be configured.

- [ ] **Step 3: Add `validate_docker_runtime`**

Require `docker version` and `docker compose version`, verify the daemon responds, and fail with a clear message if the current root/user context cannot access the daemon. This validation must run before any `docker network create`, `docker compose config`, or image build command.

---

### Task 4: Integrate dependency checks into the installer flow

**Files:**
- Modify: `publish-upload/CLOUD-MAIL-Enhanced-smtp-gateway/install.sh`

- [ ] **Step 1: Add CLI/environment controls**

Add `--no-auto-install` to usage and argument parsing. Accept `CLOUD_MAIL_SMTP_AUTO_INSTALL=0` to disable installation. When disabled, preserve fail-fast behavior with explicit missing-command messages.

- [ ] **Step 2: Replace the early Docker-only checks**

After Linux/root validation and before checking the installation package, call:

```bash
if [ "$AUTO_INSTALL_DEPENDENCIES" -eq 1 ]; then
  ensure_runtime_dependencies
else
  validate_required_commands
fi
```

Remove the old direct `command -v docker` and `docker compose version` checks or make them part of the new validation helper, avoiding duplicate output.

- [ ] **Step 3: Install Certbot only when needed**

Keep `ensure_certbot` as a conditional dependency. It must reuse the APT helper and preserve the existing behavior of reporting broken APT sources rather than disabling security checks.

- [ ] **Step 4: Ensure failures happen before container creation**

Retain the existing ordering: all dependency installation/validation, configuration checks, Cloud Mail preflight, certificate preparation, and Compose validation happen before `docker compose build`, `docker network create`, or `docker compose up`.

---

### Task 5: Add mocked dependency tests and mirror files

**Files:**
- Modify: `publish-upload/CLOUD-MAIL-Enhanced-smtp-gateway/test/install-script.test.sh`
- Mirror: `smtp-gateway/test/install-script.test.sh`

- [ ] **Step 1: Add a static test for safe Docker source configuration**

Assert that the installer uses `/etc/apt/keyrings/docker.asc`, `signed-by=`, the Docker official repository URL, and the v2 package name `docker-compose-plugin`.

- [ ] **Step 2: Add a static test for unsupported distributions and opt-out mode**

Assert that non-Debian/Ubuntu systems use the bilingual unsupported-distribution failure path and that `--no-auto-install` disables package installation.

- [ ] **Step 3: Run both test copies**

Run:

```bash
bash -n smtp-gateway/install.sh
bash smtp-gateway/test/install-script.test.sh
bash -n publish-upload/CLOUD-MAIL-Enhanced-smtp-gateway/install.sh
bash publish-upload/CLOUD-MAIL-Enhanced-smtp-gateway/test/install-script.test.sh
```

Expected: all checks pass.

---

### Task 6: Document automatic dependency installation

**Files:**
- Modify: `publish-upload/CLOUD-MAIL-Enhanced-smtp-gateway/README.md`

- [ ] **Step 1: Add the default installation section**

Document that the installer must run as root/sudo, automatically installs Docker official packages and basic tools on Debian/Ubuntu, starts/enables Docker, and only installs certbot when Let’s Encrypt is selected.

- [ ] **Step 2: Document opt-out and unsupported systems**

Document `--no-auto-install`, `CLOUD_MAIL_SMTP_AUTO_INSTALL=0`, non-Debian/Ubuntu behavior, and the manual dependency package list.

- [ ] **Step 3: Document broken APT repositories**

Add the exact `grep -Rni` command for locating invalid entries such as `bullseye-backports`, explain that the installer will not disable APT signature checking or delete sources, and show the manual `apt-get update`/`apt-get install` retry.

---

### Task 7: Verify, commit, and publish

**Files:**
- Commit the modified files in `publish-upload/CLOUD-MAIL-Enhanced-smtp-gateway`.

- [ ] **Step 1: Run final verification**

Run shell syntax checks, both installer tests, and `git diff --check`; inspect `git status --short --branch` and confirm only dependency-installation files are changed.

- [ ] **Step 2: Commit**

```bash
git add install.sh README.md test/install-script.test.sh docs/superpowers/specs/2026-08-14-auto-install-dependencies-design.md docs/superpowers/plans/2026-08-14-auto-install-dependencies-plan.md
git commit -m "feat: auto install gateway dependencies"
```

- [ ] **Step 3: Push**

```bash
git push origin main
```

Expected: remote `main` advances and contains the automatic dependency installation feature.