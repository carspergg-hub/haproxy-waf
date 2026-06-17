# HAProxy + Coraza WAF Deployment

This repository provides a **production-style one-click installer** for building a lightweight Web Application Firewall (WAF) gateway based on:

- HAProxy 2.8
- Coraza WAF (SPOA mode)
- OWASP Core Rule Set (CRS) v4.0.0

---

## 🚀 Architecture Overview

```
Client
  |
  v
HAProxy (L7 Gateway)
  |
  |---- SPOE ---->
  |               Coraza SPOA (WAF Engine)
  |<--- decision--
  |
  v
Backend Service (127.0.0.1:8080)
```

---

## 🔐 Key Features

### 1. High-performance L7 gateway
- HTTP reverse proxy via HAProxy 2.8
- Connection pooling and keepalive optimization
- High concurrency (20k+ connections baseline)

### 2. WAF engine (Coraza + CRS)
- OWASP CRS v4 rule set
- Paranoia Level 1 default (reduced false positives)
- Request inspection via SPOE protocol

### 3. Intelligent traffic bypass
- `/health`, `/metrics` bypass WAF
- Upload endpoints optimized separately
- Large body protection (default 512KB threshold)

### 4. Decision model
- `intervention > 0` → block
- `score > 5` → block
- otherwise allow

---

## ⚙️ Installation

### 1. Clone repository
```bash
git clone https://github.com/carspergg-hub/haproxy-waf.git
cd haproxy-waf
```

### 2. Run installer
```bash
chmod +x install.sh
sudo ./install.sh
```

---

## 📦 What gets installed

- HAProxy compiled from source
- Coraza SPOA binary
- OWASP CRS rule engine
- systemd services:
  - `haproxy.service`
  - `coraza.service`

---

## 🔧 Configuration Highlights

### HAProxy routing
- Backend: `127.0.0.1:8080`
- SPOA WAF: `127.0.0.1:9000`

### WAF rule tuning
File:
```
/etc/coraza/rules/crs-tuning.conf
```

Default setting:
```apache
SecAction "id:900000,phase:1,pass,nolog,setvar:tx.paranoia_level=1"
```

---

## 🧠 Design Notes

This implementation prioritizes:

- Low latency request inspection
- Minimal SPOE overhead
- Deterministic deny logic
- Production-friendly false positive reduction

---

## 📊 Traffic Flow

```
Request → HAProxy → SPOE → Coraza WAF → Decision
        → allow → backend
        → deny  → 403/413
```

---

## ⚠️ Notes

- SPOA is single-instance in default config
- No distributed WAF cluster included
- Recommended for edge gateway or sidecar scenarios

---

## 📈 Future Enhancements

- Multi-SPOA HA mode
- Redis-based dynamic rules
- Prometheus metrics exporter
- GeoIP-based filtering
- Adaptive scoring model

---

## 🧩 License

MIT (recommended — can be adjusted)
