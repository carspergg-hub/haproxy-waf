# HAProxy + Coraza WAF（旁路隔离版）

基于 HAProxy 2.8.24 + Coraza SPOA v0.7.2 + OWASP CRS v4.0.0 构建的轻量级 WAF 网关。

特点：

- 不覆盖系统原有 HAProxy
- 独立二进制 `haproxy-waf`
- 独立配置目录 `/etc/haproxy-waf`
- 独立监听端口 `8081`
- 支持快速回退
- 适合生产环境灰度验证

---

## 架构

```text
Client
   |
   v
haproxy-waf:8081
   |
   +---- SPOE ----> Coraza SPOA v0.7.2
   |                     |
   |<---- Decision ------+
   |
   v
Backend Service
```

---

## 软件版本

| 组件 | 版本 |
|--------|--------|
| HAProxy | 2.8.24 |
| Coraza SPOA | 0.7.2 |
| OWASP CRS | 4.0.0 |
| Go | 1.22.2 |

---

## 核心能力

### 安全部署

- 非侵入式安装
- 原有 HAProxy 完全保留
- 回退仅需停止 haproxy-waf 服务

### WAF能力

- Coraza WAF 引擎
- OWASP CRS v4
- Paranoia Level 1
- anomaly score 检测
- intervention 拦截

### 流量治理

自动旁路：

- /health
- /metrics
- /upload
- /api/files
- /api/bulk
- /api/import

### DoS基础防护

默认限制：

```text
非白名单接口
Body > 512KB
直接返回 413
```

---

## 安装

```bash
git clone https://github.com/carspergg-hub/haproxy-waf.git
cd haproxy-waf
chmod +x install.sh
./install.sh
```

---

## 安装结果

### 二进制

```text
/usr/local/sbin/haproxy-waf
/usr/local/bin/coraza-spoa
```

### 配置目录

```text
/etc/haproxy-waf/
/etc/coraza/
```

### 服务

```bash
systemctl status haproxy-waf
systemctl status coraza
```

---

## 端口规划

| 端口 | 用途 |
|--------|--------|
| 8081 | WAF网关 |
| 9000 | Coraza SPOA |
| 8080 | 后端应用 |

---

## 请求处理流程

```text
Request
   |
   +--> Body > 512KB ?
           |
           +--> 413

   +--> bypass ?
           |
           +--> Backend

   +--> Coraza
           |
           +--> intervention > 0
           |
           +--> anomaly_score > 5
           |
           +--> 403

   +--> Backend
```

---

## 回退方案

停止旁路网关即可：

```bash
systemctl stop haproxy-waf
```

系统原有 HAProxy 不受任何影响。

---

## 后续规划

- 多 SPOA 实例高可用
- Redis 动态黑名单
- Prometheus Metrics
- Grafana Dashboard
- GeoIP/IP信誉库
- AI异常流量识别

---

License: MIT