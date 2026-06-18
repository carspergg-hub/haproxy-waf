#!/bin/bash
set -e

GREEN='\033[0;32m'
NC='\033[0m'

echo -e "${GREEN}[1/6] 环境准备...${NC}"
yum update -y
yum install -y epel-release gcc wget git make pcre-devel openssl-devel systemd-devel

# ----------------------------
# Go 1.22
# ----------------------------
if [ ! -d "/usr/local/go" ]; then
    wget https://golang.org/dl/go1.22.2.linux-amd64.tar.gz
    tar -C /usr/local -xzf go1.22.2.linux-amd64.tar.gz
    rm -f go1.22.2.linux-amd64.tar.gz
fi
export PATH=$PATH:/usr/local/go/bin

# ----------------------------
# HAProxy 2.8.24 (进程与目录完全隔离版)
# ----------------------------
echo -e "${GREEN}[2/6] 安装 HAProxy 2.8.24 (旁路隔离模式)...${NC}"
cd /usr/local/src
if [ ! -d "haproxy-2.8.24" ]; then
    wget -q https://www.haproxy.org/download/2.8/src/haproxy-2.8.24.tar.gz
    tar -zxf haproxy-2.8.24.tar.gz
fi
cd haproxy-2.8.24

make TARGET=linux-glibc USE_OPENSSL=1 USE_PCRE=1 USE_SYSTEMD=1

# 隔离部署：不执行 make install，避免覆盖原机老版本
cp haproxy /usr/local/sbin/haproxy-waf
chmod +x /usr/local/sbin/haproxy-waf

useradd -r -s /bin/false haproxy || true
mkdir -p /etc/haproxy-waf /var/lib/haproxy-waf

# ----------------------------
# Coraza SPOA 0.7.2 (现代稳定版)
# ----------------------------
echo -e "${GREEN}[3/6] 安装 Coraza SPOA (v0.7.2)...${NC}"
cd /usr/local/src
rm -rf coraza-spoa
git clone https://github.com/corazawaf/coraza-spoa.git
cd coraza-spoa

# 检出 0.7.2 现代稳定版
git checkout v0.7.2 || true
go mod download
# 0.7.2 版本 main.go 在根目录，使用 . 编译
go build -o coraza-spoa .
cp coraza-spoa /usr/local/bin/

# ----------------------------
# 核心规则集 CRS v4.3.0 & Config
# ----------------------------
echo -e "${GREEN}[4/6] 配置 CRS v4.3.0 与 Coraza...${NC}"
mkdir -p /etc/coraza/rules/coreruleset
touch /var/log/coraza.log
chmod 666 /var/log/coraza.log

# 1. 下载官方底层推荐配置
wget -q https://raw.githubusercontent.com/corazawaf/coraza/main/coraza.conf-recommended -O /etc/coraza/rules/coraza.conf
sed -i 's/SecRuleEngine DetectionOnly/SecRuleEngine On/g' /etc/coraza/rules/coraza.conf

# 2. 克隆并提取 CRS v4.3.0
rm -rf /tmp/coreruleset
git clone -b v4.3.0 https://github.com/coreruleset/coreruleset.git /tmp/coreruleset
cp -r /tmp/coreruleset/rules /etc/coraza/rules/coreruleset/
cp /tmp/coreruleset/crs-setup.conf.example /etc/coraza/rules/coreruleset/crs-setup.conf
rm -rf /tmp/coreruleset

# 3. 注入降级基线 (PL1)
cat > /etc/coraza/rules/crs-tuning.conf <<EOF
SecAction "id:900000,phase:1,pass,nolog,setvar:tx.paranoia_level=1"
EOF

# 4. 写入支持 0.7.2 新语法的 YAML
cat > /etc/coraza/config.yaml <<EOF
bind: "127.0.0.1:9000"
default_application: "default"

# --- 全局日志配置 ---
log_level: error
log_file: "/var/log/coraza.log"
log_format: "json"

applications:
  - name: "default"
    # --- 应用日志配置（双重配置，防止报错） ---
    log_level: error
    log_file: "/var/log/coraza.log"
    log_format: "json"
    directives: |
      Include /etc/coraza/rules/coraza.conf
      Include /etc/coraza/rules/crs-tuning.conf
      Include /etc/coraza/rules/coreruleset/crs-setup.conf
      Include /etc/coraza/rules/coreruleset/rules/*.conf
EOF

# ----------------------------
# SPOE (纯净标准 Schema)
# ----------------------------
echo -e "${GREEN}[5/6] 配置 HAProxy SPOE...${NC}"

cat > /etc/haproxy-waf/coraza.spoe <<EOF
[coraza]
spoe-agent coraza-agent
    messages check-request
    option var-prefix coraza
    timeout hello 100ms
    timeout idle 30s
    timeout processing 500ms
    use-backend coraza-spoa

spoe-message check-request
    args unique-id method path query req.ver req.hdrs_bin req.body_size req.body
    event on-frontend-http-request
EOF

# ----------------------------
# HAProxy (最终稳定状态机 & 0.7.2 变量联动)
# ----------------------------
cat > /etc/haproxy-waf/haproxy.cfg <<EOF
global
    log 127.0.0.1 local0
    maxconn 20000
    user haproxy
    group haproxy
    daemon
    chroot /var/lib/haproxy-waf

defaults
    mode http
    timeout connect 5s
    timeout client 50s
    timeout server 50s

frontend http_in
    bind *:8081

    # -------------------------
    # Trace ID 贯通
    # -------------------------
    unique-id-format %{+X}o\ %ci:%cp_%fi:%fp_%Ts_%rt:%pid
    unique-id-header X-Unique-ID

    # -------------------------
    # 业务旁路池与 DoS 防御
    # -------------------------
    acl bypass_waf path_beg /health /metrics /upload /api/files /api/bulk /api/import
    acl large_body req.body_size gt 524288
    
    http-request deny deny_status 413 if large_body !bypass_waf
    http-request set-var(txn.skip_waf) int(1) if bypass_waf

    # -------------------------
    # WAF 引擎挂载
    # -------------------------
    filter spoe engine coraza config /etc/haproxy-waf/coraza.spoe

    # -------------------------
    # 状态机初始化 (按需分配)
    # -------------------------
    http-request set-var(txn.block) int(0) if !{ var(txn.skip_waf) -m int eq 1 }

    # -------------------------
    # 决策收敛 (精准对齐 anomaly_score)
    # -------------------------
    http-request set-var(txn.block) int(1) if { var(txn.coraza.intervention) -m int gt 0 } or { var(txn.coraza.anomaly_score) -m int gt 5 }

    # -------------------------
    # 最终决断
    # -------------------------
    http-request deny deny_status 403 if !{ var(txn.skip_waf) -m int eq 1 } { var(txn.block) -m int eq 1 }

    default_backend web_servers

backend web_servers
    server app1 127.0.0.1:8080 check

backend coraza-spoa
    mode tcp
    server spoa1 127.0.0.1:9000 check
EOF

# ----------------------------
# Systemd 服务 (独立防爆 & 无损热重载)
# ----------------------------
echo -e "${GREEN}[6/6] 注册独立服务并启动...${NC}"

cat > /etc/systemd/system/coraza.service <<EOF
[Unit]
Description=Coraza SPOA v0.7.2
After=network.target

[Service]
ExecStart=/usr/local/bin/coraza-spoa -config /etc/coraza/config.yaml
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

cat > /etc/systemd/system/haproxy-waf.service <<EOF
[Unit]
Description=HAProxy 2.8.24 WAF Gateway
After=network.target

[Service]
ExecStartPre=/usr/local/sbin/haproxy-waf -f /etc/haproxy-waf/haproxy.cfg -c -q
ExecStart=/usr/local/sbin/haproxy-waf -Ws -f /etc/haproxy-waf/haproxy.cfg -p /var/run/haproxy-waf.pid
ExecReload=/bin/kill -USR2 \$MAINPID
Restart=always

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now coraza
systemctl enable --now haproxy-waf

echo -e "${GREEN}====================================================${NC}"
echo -e " 部署完成！"
echo -e " HAProxy-WAF 监听端口: 8081"
echo -e " Coraza WAF 日志文件: /var/log/coraza.log (JSON 格式)"
echo -e "${GREEN}====================================================${NC}"
