# HAProxy + Coraza WAF 部署项目

本项目提供一个**生产级一键部署脚本**，用于构建轻量级 Web 应用防火墙（WAF）网关，基于以下组件：

- HAProxy 2.8（高性能四/七层代理）
- Coraza WAF（SPOA 模式）
- OWASP Core Rule Set (CRS) v4.0.0

---

## 🚀 架构说明

```
客户端
  |
  v
HAProxy（七层网关）
  |
  |---- SPOE ---->
  |               Coraza SPOA（WAF引擎）
  |<--- 决策返回 ---
  |
  v
后端服务（127.0.0.1:8080）
```

---

## 🔐 核心能力

### 1. 高性能网关
- 基于 HAProxy 2.8 构建 HTTP 反向代理
- 支持高并发（20K+ 连接级别）
- Keepalive + 连接复用优化

### 2. WAF 防护能力
- 基于 OWASP CRS v4 规则集
- 默认 Paranoia Level = 1（降低误杀）
- SPOE 协议异步检测请求

### 3. 流量治理能力
- `/health`、`/metrics` 自动旁路 WAF
- 上传接口优化处理
- 支持 512KB 大包拦截策略

### 4. 决策模型
- `intervention > 0` → 拦截
- `score > 5` → 拦截
- 否则放行

---

## ⚙️ 安装方式

### 1. 克隆仓库
```bash
git clone https://github.com/carspergg-hub/haproxy-waf.git
cd haproxy-waf
```

### 2. 执行安装脚本
```bash
chmod +x install.sh
sudo ./install.sh
```

---

## 📦 安装内容

安装脚本将自动部署：

- HAProxy（源码编译）
- Coraza SPOA 引擎
- OWASP CRS 规则库
- systemd 服务
  - haproxy.service
  - coraza.service

---

## 🔧 配置说明

### HAProxy 配置
- 后端服务：127.0.0.1:8080
- WAF 服务：127.0.0.1:9000

### CRS 调优文件
路径：
```
/etc/coraza/rules/crs-tuning.conf
```

默认配置：
```apache
SecAction "id:900000,phase:1,pass,nolog,setvar:tx.paranoia_level=1"
```

---

## 🧠 设计说明

本系统设计目标：

- 低延迟请求检测
- SPOE 异步检测降低主链路开销
- 可控误杀率（PL1 基线）
- 明确的安全决策模型

---

## 📊 请求流转流程

```
请求 → HAProxy → SPOE → Coraza WAF → 决策
       → 放行 → 后端服务
       → 拦截 → 403/413
```

---

## ⚠️ 注意事项

- 默认 SPOA 为单实例部署（可扩展多实例）
- 未启用分布式 WAF 集群能力
- 更适合边缘网关 / Sidecar 场景

---

## 📈 后续增强方向

- SPOA 高可用集群化
- Redis 动态规则中心
- Prometheus + Grafana 监控
- IP 信誉系统
- AI 异常流量识别模型

---

## 📄 License

MIT License（建议，可按需修改）
