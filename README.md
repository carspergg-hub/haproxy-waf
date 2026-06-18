# HAProxy + Coraza WAF 部署项目（隔离安全版）

本项目提供一个**生产级一键部署脚本**，用于构建轻量级 Web 应用防火墙（WAF）网关，采用“非侵入式隔离部署”，避免影响原有 HAProxy 生产环境。

---

## 🚀 架构说明

本版本采用**双栈隔离架构**：

```
                ┌────────────────────┐
                │ 生产 HAProxy（不变） │
                └─────────┬──────────┘
                          │
                          │（可选流量切换）
                          v
                ┌────────────────────┐
                │ haproxy-waf 网关    │  ← 独立进程 / 独立端口
                │ /usr/local/sbin/... │
                └─────────┬──────────┘
                          │
                          v
                ┌────────────────────┐
                │ Coraza SPOA WAF     │
                └────────────────────┘
                          │
                          v
                ┌────────────────────┐
                │ 后端服务 8080       │
                └────────────────────┘
```

---

## 🔐 核心能力

### 1. 非破坏式部署（关键升级）
- ❌ 不再覆盖系统 `/usr/sbin/haproxy`
- ✅ 独立二进制：`haproxy-waf`
- ✅ 可随时回滚到原 HAProxy

### 2. 高性能网关能力
- 基于 HAProxy 2.8.24 编译
- 支持 20K+ 并发连接
- 独立运行 chroot 环境

### 3. WAF 防护能力
- Coraza WAF + OWASP CRS v4
- Paranoia Level 1（降低误杀）
- SPOE 异步检测机制

### 4. 流量治理能力
- `/health` `/metrics` 自动旁路
- 上传接口优化处理
- 512KB 大包拦截策略

### 5. 决策模型
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

脚本将自动部署以下组件：

- HAProxy 2.8.24（隔离编译版本）
- haproxy-waf（独立二进制）
- Coraza SPOA 引擎
- OWASP CRS 规则库
- systemd 服务：
  - haproxy-waf.service
  - coraza.service

---

## 🔧 配置说明

### WAF 网关端口
```
8081（与生产环境隔离）
```

### 后端服务
```
127.0.0.1:8080
```

### SPOA WAF
```
127.0.0.1:9000
```

---

## 🧠 设计说明

本架构强调：

- 非侵入式安全增强
- 与生产系统完全解耦
- 可回滚、安全可控
- SPOE 异步检测降低延迟

---

## 📊 请求流转流程

```
请求 → haproxy-waf（8081） → SPOE → Coraza WAF → 决策
        → 放行 → 后端服务
        → 拦截 → 403/413
```

---

## ⚠️ 注意事项

- 默认不影响生产 HAProxy
- WAF 网关独立运行（8081）
- 可作为旁路安全层或灰度入口

---

## 📈 后续增强方向

- 多实例 SPOA 高可用
- Redis 动态规则中心
- Prometheus + Grafana 监控
- 流量灰度与AB测试
- AI 攻击评分模型

---

## 📄 License

MIT License
