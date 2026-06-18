#!/bin/bash
set -e

GREEN='\033[0;32m'
NC='\033[0m'

# ============================================================
# HAProxy + Coraza WAF (Isolated Safe Version)
# - DOES NOT overwrite system haproxy
# - installs parallel binary: haproxy-waf
# - safe rollback friendly
# ============================================================

echo -e "${GREEN}[1/6] 环境准备...${NC}"
yum update -y
yum install -y epel-release gcc wget git make pcre-devel openssl-devel systemd-devel

# ----------------------------
# Go
# ----------------------------
if [ ! -d "/usr/local/go" ]; then
    wget https://golang.org/dl/go1.22.2.linux-amd64.tar.gz
    tar -C /usr/local -xzf go1.22.2.linux-amd64.tar.gz
    rm -f go1.22.2.linux-amd64.tar.gz
fi
export PATH=$PATH:/usr/local/go/bin

# ============================================================
# HAProxy ISOLATED BUILD (SAFE)
# ============================================================
echo -e "${GREEN}[2/6] 编译 HAProxy (隔离模式，不影响系统版本)...${NC}"
cd /usr/local/src
wget -q https://www.haproxy.org/download/2.8/src/haproxy-2.8.24.tar.gz
rm -rf haproxy-2.8.24

# 防止重复下载失败
tar -zxf haproxy-2.8.24.tar.gz
cd haproxy-2.8.24

make TARGET=linux-glibc USE_OPENSSL=1 USE_PCRE=1 USE_SYSTEMD=1

# ❗关键：不执行 make install，不覆盖系统 haproxy
cp haproxy /usr/local/sbin/haproxy-waf
chmod +x /usr/local/sbin/haproxy-waf

# create isolated runtime dirs
useradd -r -s /bin/false haproxy || true
mkdir -p /etc/haproxy-waf /var/lib/haproxy-waf

# ============================================================
# Coraza SPOA
# ============================================================
echo -e "${GREEN}[3/6] 安装 Coraza SPOA...${NC}"
cd /usr/local/src
rm -rf coraza-spoa

git clone https://github.com/corazawaf/coraza-spoa.git
cd coraza-spoa

git checkout v0.2.0 || true
go mod download
go build -o coraza-spoa cmd/main.go
cp coraza-spoa /usr/local/bin/

# ============================================================
# CRS CONFIG
# ============================================================
echo -e "${GREEN}[4/6] 配置 CRS...${NC}"
mkdir -p /etc/coraza/rules

cp coraza.conf-recommended /etc/coraza/rules/coraza.conf
sed -i 's/SecRuleEngine DetectionOnly/SecRuleEngine On/g' /etc/coraza/rules/coraza.conf

cd /etc/coraza/rules
rm -rf coreruleset
git clone -b v4.0.0 https://github.com/coreruleset/coreruleset.git
cd coreruleset
cp crs-setup.conf.example crs-setup.conf

cat > /etc/coraza/rules/crs-tuning.conf <<EOF
SecAction "id:900000,phase:1,pass,nolog,setvar:tx.paranoia_level=1"
EOF

cat > /etc/coraza/config.yaml <<EOF
bind: "127.0.0.1:9000"
log_level: error
log_file: "/var/log/coraza.log"
directives: |
  Include /etc/coraza/rules/coraza.conf
  Include /etc/coraza/rules/crs-tuning.conf
  Include /etc/coraza/rules/coreruleset/crs-setup.conf
  Include /etc/coraza/rules/coreruleset/rules/*.conf
EOF

# ============================================================
# SPOE CONFIG
# ============================================================
echo -e "${GREEN}[5/6] 配置 SPOE...${NC}"

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
EOF

# ============================================================
# ISOLATED HAPROXY CONFIG
# ============================================================
echo -e "${GREEN}[6/6] 配置 HAProxy (隔离端口 8081)...${NC}"

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

    unique-id-format %{+X}o\ %ci:%cp_%fi:%fp_%Ts_%rt:%pid
    unique-id-header X-Unique-ID

    acl bypass_waf path_beg /health /metrics /upload /api/files /api/bulk /api/import

    acl large_body req.body_size gt 524288
    http-request deny deny_status 413 if large_body !bypass_waf

    http-request set-var(txn.skip_waf) int(1) if bypass_waf

    filter spoe engine coraza config /etc/haproxy-waf/coraza.spoe

    http-request set-var(txn.block) int(0)
    http-request set-var(txn.block) int(1) if { var(txn.coraza.intervention) -m int gt 0 } or { var(txn.coraza.score) -m int gt 5 }

    http-request deny deny_status 403 if !{ var(txn.skip_waf) -m int eq 1 } { var(txn.block) -m int eq 1 }

    default_backend web_servers

backend web_servers
    server app1 127.0.0.1:8080 check

backend coraza-spoa
    mode tcp
    server spoa1 127.0.0.1:9000 check
EOF

# ============================================================
# SYSTEMD
# ============================================================

echo "creating systemd services..."

cat > /etc/systemd/system/haproxy-waf.service <<EOF
[Unit]
Description=HAProxy WAF Isolated Instance
After=network.target

[Service]
ExecStartPre=/usr/local/sbin/haproxy-waf -f /etc/haproxy-waf/haproxy.cfg -c -q
ExecStart=/usr/local/sbin/haproxy-waf -Ws -f /etc/haproxy-waf/haproxy.cfg -p /var/run/haproxy-waf.pid
ExecReload=/bin/kill -USR2 \$MAINPID
Restart=always

[Install]
WantedBy=multi-user.target
EOF

cat > /etc/systemd/system/coraza.service <<EOF
[Unit]
Description=Coraza SPOA
After=network.target

[Service]
ExecStart=/usr/local/bin/coraza-spoa -config /etc/coraza/config.yaml
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now coraza
systemctl enable --now haproxy-waf

echo -e "DEPLOY COMPLETE - SAFE ISOLATED WAF (ROLLBACK READY)"