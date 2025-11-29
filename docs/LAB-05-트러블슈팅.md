# LAB 05: 인증서 문제 트러블슈팅

## 🎯 학습 목표
- 의도적으로 인증서 문제를 발생시키고 해결
- 실제 에러 메시지 분석 능력 향상
- SSL 디버그 로그 해석
- 체계적인 트러블슈팅 방법론 습득

## 📚 예상 소요 시간: 2시간

## 📋 사전 요구사항
- LAB-01 ~ LAB-04 완료
- Java 실습 Pod 접속 상태

---

# Part 1: 트러블슈팅 방법론

## 1.1 TLS 문제 진단 프레임워크

```
┌─────────────────────────────────────────────────────────────────┐
│                TLS 트러블슈팅 체크리스트                         │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  1️⃣ 네트워크 연결 확인                                          │
│     └─ 서버 IP/포트 접근 가능?                                  │
│                                                                 │
│  2️⃣ TLS 핸드셰이크 확인                                        │
│     └─ openssl s_client 연결 성공?                             │
│                                                                 │
│  3️⃣ 인증서 체인 확인                                           │
│     ├─ 서버 인증서 유효?                                       │
│     ├─ 중간 CA 포함?                                           │
│     └─ Root CA 신뢰?                                           │
│                                                                 │
│  4️⃣ 호스트명 확인                                              │
│     └─ CN/SAN이 호스트명과 일치?                                │
│                                                                 │
│  5️⃣ 시간 동기화 확인                                           │
│     └─ 서버/클라이언트 시간 정확?                               │
│                                                                 │
│  6️⃣ 프로토콜/암호화 호환성                                     │
│     └─ TLS 버전, Cipher Suite 호환?                            │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

## 1.2 주요 에러 메시지 분류

| 에러 | 의미 | 원인 |
|------|------|------|
| `PKIX path building failed` | 인증서 체인 검증 실패 | Root CA 없음 |
| `unable to find valid certification path` | 신뢰 경로 없음 | CA 미등록 |
| `certificate has expired` | 인증서 만료 | 유효기간 초과 |
| `hostname verification failed` | 호스트명 불일치 | CN/SAN 불일치 |
| `handshake_failure` | 핸드셰이크 실패 | 프로토콜/암호화 불일치 |
| `bad_certificate` | 잘못된 인증서 | mTLS 인증서 문제 |
| `certificate_unknown` | 알 수 없는 인증서 | CA 미신뢰 |

## 1.3 디버깅 도구

### Java 디버그 옵션
```bash
# 전체 SSL 디버그
-Djavax.net.debug=all

# 핸드셰이크만
-Djavax.net.debug=ssl:handshake

# 인증서만
-Djavax.net.debug=ssl:handshake:cert

# 세션 정보
-Djavax.net.debug=ssl:session
```

### OpenSSL 디버그
```bash
# 상세 연결 정보
openssl s_client -connect host:port -state -debug

# 인증서 체인 표시
openssl s_client -connect host:port -showcerts

# 특정 TLS 버전 강제
openssl s_client -connect host:port -tls1_2
```

---

# Part 2: 시나리오 1 - Root CA 누락

## 2.1 문제 재현

의도적으로 Root CA가 없는 TrustStore로 연결합니다.

```bash
cd /workspace/certs

# 빈 TrustStore 생성 (또는 기존 것 사용)
keytool -genkeypair -alias dummy -keystore empty.p12 -storepass changeit \
  -dname "CN=dummy" -keyalg RSA -validity 1 2>/dev/null
keytool -delete -alias dummy -keystore empty.p12 -storepass changeit 2>/dev/null

# 빈 TrustStore로 연결 시도
cd /workspace/java-app
java -Djavax.net.ssl.trustStore=/workspace/certs/empty.p12 \
     -Djavax.net.ssl.trustStorePassword=changeit \
     TLSConnectionTest https://www.google.com
```

## 2.2 에러 분석

### 에러 메시지
```
❌ SSL Handshake Failed!
──────────────────────────────────────────────────
Error: PKIX path building failed: 
  sun.security.provider.certpath.SunCertPathBuilderException: 
  unable to find valid certification path to requested target
```

### 원인 분석
```
┌─────────────────────────────────────────────────────────────────┐
│                    인증서 체인 검증 실패                         │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  Google 서버가 보낸 체인:                                       │
│  [Server] www.google.com                                       │
│      ↑ 서명                                                    │
│  [Intermediate] GTS CA 1C3                                     │
│      ↑ 서명                                                    │
│  [Root] GTS Root R1                                            │
│                                                                 │
│  클라이언트 TrustStore:                                         │
│  (비어있음)                                                     │
│                                                                 │
│  검증 과정:                                                     │
│  1. Root CA를 TrustStore에서 찾음 → 없음!                       │
│  2. 체인을 신뢰할 수 없음                                       │
│  3. PKIX path building failed                                  │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

## 2.3 디버그 로그 확인

```bash
java -Djavax.net.debug=ssl:handshake:trustmanager \
     -Djavax.net.ssl.trustStore=/workspace/certs/empty.p12 \
     -Djavax.net.ssl.trustStorePassword=changeit \
     TLSConnectionTest https://www.google.com 2>&1 | grep -A5 "PKIX"
```

### 핵심 로그
```
javax.net.ssl|DEBUG|...|
PKIX path building failed: 
sun.security.provider.certpath.SunCertPathBuilderException: 
unable to find valid certification path to requested target
```

## 2.4 해결 방법

### 방법 1: 기본 cacerts 사용
```bash
# TrustStore 옵션 제거
java TLSConnectionTest https://www.google.com
# 성공!
```

### 방법 2: Root CA 추가
```bash
cd /workspace/certs

# Google Root CA 추출
/opt/scripts/extract-certs.sh www.google.com

# Root CA를 TrustStore에 추가
keytool -importcert \
  -keystore empty.p12 \
  -storepass changeit \
  -alias "google-root" \
  -file www.google.com/www.google.com-2.crt \
  -noprompt

# 다시 테스트
java -Djavax.net.ssl.trustStore=/workspace/certs/empty.p12 \
     -Djavax.net.ssl.trustStorePassword=changeit \
     TLSConnectionTest https://www.google.com
# 성공!
```

---

# Part 3: 시나리오 2 - 인증서 만료

## 3.1 만료된 인증서 생성

```bash
cd /workspace/certs
mkdir -p expired-test
cd expired-test

# 이미 만료된 인증서 생성 (유효기간: -1일)
# OpenSSL로 과거 날짜의 인증서 생성

# CA 키 생성
openssl genrsa -out ca.key 2048

# 과거 날짜로 CA 인증서 생성 (이미 만료됨)
# faketime 없이는 직접 만료된 인증서 생성이 어려우므로
# 대신 유효기간이 1초인 인증서를 생성 후 대기

# 1초 유효 인증서 생성
openssl req -x509 -new -nodes \
  -key ca.key \
  -sha256 \
  -days 0 \
  -out expired-ca.crt \
  -subj "/CN=Expired-CA"

# 잠시 대기 후 만료 확인
sleep 2
openssl x509 -in expired-ca.crt -noout -checkend 0
# Certificate has expired
```

### 대안: 만료 확인 시뮬레이션

```bash
# 실제 만료된 인증서 대신, 유효기간 검사 시뮬레이션
cd /workspace/certs

# 현재 유효한 인증서의 만료 예정 확인
openssl x509 -in www.google.com/www.google.com-0.crt -noout -dates

# 90일 후 만료 여부 확인
openssl x509 -in www.google.com/www.google.com-0.crt -noout -checkend 7776000
# 7776000 = 90일
```

## 3.2 에러 메시지 예시

만료된 인증서로 연결 시:
```
❌ SSL Handshake Failed!
Error: ValidatorException: PKIX path validation failed: 
  java.security.cert.CertPathValidatorException: 
  timestamp check failed
```

또는:
```
Error: NotAfter: [날짜]; Current time: [현재시간]
```

## 3.3 해결 방법

### 확인 스크립트
```bash
cat << 'EOF' > /workspace/scripts/check-cert-expiry.sh
#!/bin/bash

if [ -z "$1" ]; then
    echo "Usage: $0 <cert_file_or_host:port>"
    exit 1
fi

INPUT=$1

# 파일인지 호스트인지 확인
if [ -f "$INPUT" ]; then
    CERT_DATA=$(cat "$INPUT")
else
    # 호스트:포트 형식
    HOST=$(echo $INPUT | cut -d: -f1)
    PORT=$(echo $INPUT | cut -d: -f2)
    PORT=${PORT:-443}
    CERT_DATA=$(echo | openssl s_client -connect ${HOST}:${PORT} 2>/dev/null | \
                openssl x509 2>/dev/null)
fi

if [ -z "$CERT_DATA" ]; then
    echo "❌ Could not get certificate"
    exit 1
fi

# 만료일 추출
EXPIRY=$(echo "$CERT_DATA" | openssl x509 -noout -enddate | cut -d= -f2)
EXPIRY_EPOCH=$(date -d "$EXPIRY" +%s 2>/dev/null || date -j -f "%b %d %T %Y %Z" "$EXPIRY" +%s 2>/dev/null)
NOW_EPOCH=$(date +%s)
DAYS_LEFT=$(( ($EXPIRY_EPOCH - $NOW_EPOCH) / 86400 ))

echo "📜 Certificate Expiry Check"
echo "═══════════════════════════════════════"
echo "Expires: $EXPIRY"
echo "Days left: $DAYS_LEFT"
echo ""

if [ $DAYS_LEFT -lt 0 ]; then
    echo "❌ EXPIRED!"
elif [ $DAYS_LEFT -lt 30 ]; then
    echo "⚠️ WARNING: Expires soon!"
elif [ $DAYS_LEFT -lt 90 ]; then
    echo "📌 Note: Consider renewal"
else
    echo "✅ OK"
fi
EOF

chmod +x /workspace/scripts/check-cert-expiry.sh
```

### 사용
```bash
# 파일로 확인
/workspace/scripts/check-cert-expiry.sh /workspace/certs/www.google.com/www.google.com-0.crt

# 호스트로 확인
/workspace/scripts/check-cert-expiry.sh www.google.com:443
```

---

# Part 4: 시나리오 3 - 호스트명 불일치

## 4.1 문제 재현

```bash
cd /workspace/certs
mkdir -p hostname-test
cd hostname-test

# CA 생성
openssl genrsa -out ca.key 2048
openssl req -x509 -new -nodes -key ca.key -sha256 -days 365 \
  -out ca.crt -subj "/CN=Test-CA"

# 서버 키 생성
openssl genrsa -out server.key 2048

# 잘못된 호스트명으로 인증서 생성
# (tls-server가 아닌 wrong-hostname으로)
openssl req -new -key server.key -out server.csr \
  -subj "/CN=wrong-hostname.example.com"

# 인증서 발급
openssl x509 -req -in server.csr -CA ca.crt -CAkey ca.key \
  -CAcreateserial -out server.crt -days 90 -sha256

# 인증서 확인
openssl x509 -in server.crt -noout -subject
# subject=CN = wrong-hostname.example.com
```

## 4.2 에러 분석

Java에서 호스트명이 일치하지 않으면:
```
❌ SSL Handshake Failed!
Error: java.security.cert.CertificateException: 
  No subject alternative names matching IP address X.X.X.X found
```

또는:
```
Error: Hostname tls-server.tls-lab.svc.cluster.local not verified:
  certificate: CN=wrong-hostname.example.com
```

## 4.3 진단 방법

```bash
# 인증서의 CN과 SAN 확인
openssl x509 -in server.crt -noout -text | grep -E "(Subject:|Subject Alternative)"

# 기대하는 호스트명
echo "Expected: tls-server.tls-lab.svc.cluster.local"

# 실제 인증서
echo "Certificate CN: wrong-hostname.example.com"
# → 불일치!
```

## 4.4 해결 방법

### 올바른 SAN으로 인증서 재발급

```bash
cd /workspace/certs/hostname-test

# SAN 설정 파일 생성
cat << EOF > san.cnf
[req]
distinguished_name = req_distinguished_name
req_extensions = v3_req
prompt = no

[req_distinguished_name]
CN = tls-server.tls-lab.svc.cluster.local

[v3_req]
keyUsage = keyEncipherment, dataEncipherment
extendedKeyUsage = serverAuth
subjectAltName = @alt_names

[alt_names]
DNS.1 = tls-server
DNS.2 = tls-server.tls-lab
DNS.3 = tls-server.tls-lab.svc
DNS.4 = tls-server.tls-lab.svc.cluster.local
DNS.5 = localhost
IP.1 = 127.0.0.1
EOF

# 새 CSR 생성
openssl req -new -key server.key -out server-fixed.csr -config san.cnf

# 인증서 발급 (SAN 포함)
openssl x509 -req -in server-fixed.csr -CA ca.crt -CAkey ca.key \
  -CAcreateserial -out server-fixed.crt -days 90 -sha256 \
  -extfile san.cnf -extensions v3_req

# SAN 확인
openssl x509 -in server-fixed.crt -noout -text | grep -A1 "Subject Alternative Name"
```

### 출력
```
X509v3 Subject Alternative Name: 
    DNS:tls-server, DNS:tls-server.tls-lab, DNS:tls-server.tls-lab.svc, 
    DNS:tls-server.tls-lab.svc.cluster.local, DNS:localhost, IP Address:127.0.0.1
```

---

# Part 5: 시나리오 4 - 중간 CA 누락

## 5.1 문제 이해

```
┌─────────────────────────────────────────────────────────────────┐
│              중간 CA 누락 문제                                   │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  정상적인 체인:                                                  │
│  [서버] ──서명──> [중간 CA] ──서명──> [Root CA]                  │
│                                         ↑                       │
│                                    TrustStore에 있음            │
│                                                                 │
│  중간 CA 누락:                                                   │
│  [서버] ──서명──> [???] ──???──> [Root CA]                      │
│                    ↑                                            │
│               서버가 안 보냄!                                    │
│                                                                 │
│  결과: 체인 검증 불가능                                          │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

## 5.2 진단 방법

```bash
# 서버가 보내는 인증서 체인 확인
openssl s_client -connect www.google.com:443 -showcerts </dev/null 2>/dev/null | \
  grep -E "^ [0-9]+ s:|^ +i:"
```

### 정상 출력 (체인 완전)
```
 0 s:CN = www.google.com
   i:CN = GTS CA 1C3, O = Google Trust Services LLC, C = US
 1 s:CN = GTS CA 1C3, O = Google Trust Services LLC, C = US
   i:CN = GTS Root R1, O = Google Trust Services LLC, C = US
 2 s:CN = GTS Root R1, O = Google Trust Services LLC, C = US
   i:CN = GTS Root R1, O = Google Trust Services LLC, C = US
```

### 비정상 출력 (중간 CA 누락)
```
 0 s:CN = www.example.com
   i:CN = Some Intermediate CA
(여기서 끝 - 중간 CA 인증서 없음)
```

## 5.3 해결 방법

### 서버 설정 수정 (NGINX 예시)
```nginx
# 전체 체인 포함
ssl_certificate /path/to/fullchain.pem;  # 서버 + 중간 CA
ssl_certificate_key /path/to/server.key;
```

### 체인 파일 생성
```bash
# 서버 인증서 + 중간 CA 결합
cat server.crt intermediate.crt > fullchain.pem
```

---

# Part 6: 시나리오 5 - TLS 버전 불일치

## 6.1 문제 재현

```bash
# TLS 1.0만 지원하도록 강제 (대부분의 현대 서버는 거부)
openssl s_client -connect www.google.com:443 -tls1

# 에러 예시:
# error:1409442E:SSL routines:ssl3_read_bytes:tlsv1 alert protocol version
```

## 6.2 서버 지원 TLS 버전 확인

```bash
# 지원되는 TLS 버전 확인 스크립트
cat << 'EOF' > /workspace/scripts/check-tls-versions.sh
#!/bin/bash

HOST=${1:-"www.google.com"}
PORT=${2:-443}

echo "🔐 TLS Version Check for ${HOST}:${PORT}"
echo "═══════════════════════════════════════════"

for VERSION in tls1 tls1_1 tls1_2 tls1_3; do
    echo -n "Testing $VERSION: "
    if echo | openssl s_client -connect ${HOST}:${PORT} -${VERSION} 2>/dev/null | \
       grep -q "Protocol.*:"; then
        PROTO=$(echo | openssl s_client -connect ${HOST}:${PORT} -${VERSION} 2>/dev/null | \
                grep "Protocol" | head -1)
        echo "✅ Supported - $PROTO"
    else
        echo "❌ Not supported or deprecated"
    fi
done
EOF

chmod +x /workspace/scripts/check-tls-versions.sh
```

### 사용
```bash
/workspace/scripts/check-tls-versions.sh www.google.com 443
```

### 출력 예시
```
🔐 TLS Version Check for www.google.com:443
═══════════════════════════════════════════
Testing tls1: ❌ Not supported or deprecated
Testing tls1_1: ❌ Not supported or deprecated
Testing tls1_2: ✅ Supported - Protocol  : TLSv1.2
Testing tls1_3: ✅ Supported - Protocol  : TLSv1.3
```

## 6.3 Java TLS 버전 설정

```bash
# TLS 1.2만 사용하도록 강제
java -Dhttps.protocols=TLSv1.2 TLSConnectionTest https://www.google.com

# TLS 1.3만 사용
java -Dhttps.protocols=TLSv1.3 TLSConnectionTest https://www.google.com
```

---

# Part 7: 시나리오 6 - Cipher Suite 불일치

## 7.1 Cipher Suite란?

```
TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384
 │    │     │       │   │    │
 │    │     │       │   │    └─ 무결성 해시
 │    │     │       │   └────── 암호화 모드
 │    │     │       └────────── 암호화 알고리즘
 │    │     └────────────────── 인증 알고리즘
 │    └──────────────────────── 키 교환 알고리즘
 └───────────────────────────── 프로토콜
```

## 7.2 서버 지원 Cipher 확인

```bash
# 서버가 지원하는 Cipher Suite 목록
openssl s_client -connect www.google.com:443 </dev/null 2>/dev/null | \
  grep "Cipher.*:"
```

### nmap으로 상세 확인 (설치된 경우)
```bash
nmap --script ssl-enum-ciphers -p 443 www.google.com
```

## 7.3 Java Cipher 설정

```bash
# 특정 Cipher만 활성화
java -Dhttps.cipherSuites=TLS_AES_256_GCM_SHA384 \
     TLSConnectionTest https://www.google.com
```

---

# Part 8: 종합 트러블슈팅 스크립트

## 8.1 진단 스크립트 작성

```bash
cat << 'EOF' > /workspace/scripts/tls-diagnose.sh
#!/bin/bash

# TLS 종합 진단 스크립트
# Usage: ./tls-diagnose.sh <host:port>

if [ -z "$1" ]; then
    echo "Usage: $0 <host:port>"
    echo "Example: $0 www.google.com:443"
    exit 1
fi

INPUT=$1
HOST=$(echo $INPUT | cut -d: -f1)
PORT=$(echo $INPUT | cut -d: -f2)
PORT=${PORT:-443}

echo ""
echo "╔═══════════════════════════════════════════════════════════════╗"
echo "║           TLS/SSL Diagnostic Report                          ║"
echo "╠═══════════════════════════════════════════════════════════════╣"
echo "║  Target: ${HOST}:${PORT}"
echo "╚═══════════════════════════════════════════════════════════════╝"
echo ""

# 1. 네트워크 연결 확인
echo "═══════════════════════════════════════════════════════════════"
echo "1️⃣  Network Connectivity"
echo "───────────────────────────────────────────────────────────────"
if timeout 5 bash -c "echo >/dev/tcp/${HOST}/${PORT}" 2>/dev/null; then
    echo "✅ Port ${PORT} is reachable"
else
    echo "❌ Cannot connect to ${HOST}:${PORT}"
    echo "   Check: firewall, DNS, network connectivity"
    exit 1
fi
echo ""

# 2. TLS 연결 테스트
echo "═══════════════════════════════════════════════════════════════"
echo "2️⃣  TLS Connection"
echo "───────────────────────────────────────────────────────────────"
TLS_INFO=$(echo | openssl s_client -connect ${HOST}:${PORT} 2>/dev/null)
if echo "$TLS_INFO" | grep -q "CONNECTED"; then
    PROTOCOL=$(echo "$TLS_INFO" | grep "Protocol" | head -1 | awk '{print $NF}')
    CIPHER=$(echo "$TLS_INFO" | grep "Cipher.*:" | head -1 | awk '{print $NF}')
    echo "✅ TLS handshake successful"
    echo "   Protocol: ${PROTOCOL:-unknown}"
    echo "   Cipher: ${CIPHER:-unknown}"
else
    echo "❌ TLS handshake failed"
fi
echo ""

# 3. 인증서 정보
echo "═══════════════════════════════════════════════════════════════"
echo "3️⃣  Certificate Information"
echo "───────────────────────────────────────────────────────────────"
CERT_INFO=$(echo | openssl s_client -connect ${HOST}:${PORT} 2>/dev/null | \
            openssl x509 -noout -subject -issuer -dates 2>/dev/null)
if [ -n "$CERT_INFO" ]; then
    echo "$CERT_INFO" | while read line; do
        echo "   $line"
    done
else
    echo "❌ Could not retrieve certificate"
fi
echo ""

# 4. 인증서 체인
echo "═══════════════════════════════════════════════════════════════"
echo "4️⃣  Certificate Chain"
echo "───────────────────────────────────────────────────────────────"
echo | openssl s_client -connect ${HOST}:${PORT} -showcerts 2>/dev/null | \
  grep -E "^ [0-9]+ s:|^ +i:" | head -10
echo ""

# 5. 만료 확인
echo "═══════════════════════════════════════════════════════════════"
echo "5️⃣  Certificate Expiry"
echo "───────────────────────────────────────────────────────────────"
EXPIRY=$(echo | openssl s_client -connect ${HOST}:${PORT} 2>/dev/null | \
         openssl x509 -noout -enddate 2>/dev/null | cut -d= -f2)
if [ -n "$EXPIRY" ]; then
    echo "   Expires: $EXPIRY"
    
    # 만료일까지 남은 일수
    EXPIRY_EPOCH=$(date -d "$EXPIRY" +%s 2>/dev/null)
    NOW_EPOCH=$(date +%s)
    if [ -n "$EXPIRY_EPOCH" ]; then
        DAYS_LEFT=$(( ($EXPIRY_EPOCH - $NOW_EPOCH) / 86400 ))
        if [ $DAYS_LEFT -lt 0 ]; then
            echo "   ❌ EXPIRED!"
        elif [ $DAYS_LEFT -lt 30 ]; then
            echo "   ⚠️ Warning: Only $DAYS_LEFT days left!"
        else
            echo "   ✅ Valid for $DAYS_LEFT more days"
        fi
    fi
else
    echo "❌ Could not check expiry"
fi
echo ""

# 6. SAN 확인
echo "═══════════════════════════════════════════════════════════════"
echo "6️⃣  Subject Alternative Names (SAN)"
echo "───────────────────────────────────────────────────────────────"
echo | openssl s_client -connect ${HOST}:${PORT} 2>/dev/null | \
  openssl x509 -noout -text 2>/dev/null | \
  grep -A2 "Subject Alternative Name" | tail -1 | \
  tr ',' '\n' | sed 's/^[[:space:]]*/   /'
echo ""

# 7. TLS 버전 지원
echo "═══════════════════════════════════════════════════════════════"
echo "7️⃣  TLS Version Support"
echo "───────────────────────────────────────────────────────────────"
for VER in tls1 tls1_1 tls1_2 tls1_3; do
    if echo | timeout 3 openssl s_client -connect ${HOST}:${PORT} -${VER} 2>/dev/null | \
       grep -q "Protocol"; then
        echo "   ✅ ${VER}"
    else
        echo "   ❌ ${VER}"
    fi
done
echo ""

echo "═══════════════════════════════════════════════════════════════"
echo "📋 Diagnosis Complete"
echo "═══════════════════════════════════════════════════════════════"
EOF

chmod +x /workspace/scripts/tls-diagnose.sh
```

## 8.2 사용 예시

```bash
# Google 진단
/workspace/scripts/tls-diagnose.sh www.google.com:443

# 내부 서버 진단
/workspace/scripts/tls-diagnose.sh tls-server.tls-lab.svc.cluster.local:443
```

---

# Part 9: Java 트러블슈팅 클래스

## 9.1 상세 진단 도구

```bash
cat << 'EOF' > /workspace/java-app/TLSDiagnostics.java
import javax.net.ssl.*;
import java.net.*;
import java.io.*;
import java.security.*;
import java.security.cert.*;
import java.util.*;

public class TLSDiagnostics {
    public static void main(String[] args) {
        if (args.length < 1) {
            System.out.println("Usage: java TLSDiagnostics <url>");
            System.exit(1);
        }
        
        String urlStr = args[0];
        
        System.out.println("\n╔═══════════════════════════════════════════════════════════════╗");
        System.out.println("║           Java TLS Diagnostics                                ║");
        System.out.println("╚═══════════════════════════════════════════════════════════════╝");
        System.out.println("Target: " + urlStr);
        System.out.println();
        
        try {
            URL url = new URL(urlStr);
            String host = url.getHost();
            int port = url.getPort() == -1 ? 443 : url.getPort();
            
            // 1. TrustStore 정보
            System.out.println("═══════════════════════════════════════════════════════════════");
            System.out.println("1️⃣  TrustStore Configuration");
            System.out.println("───────────────────────────────────────────────────────────────");
            
            String trustStorePath = System.getProperty("javax.net.ssl.trustStore");
            if (trustStorePath != null) {
                System.out.println("   Custom TrustStore: " + trustStorePath);
            } else {
                System.out.println("   Using default cacerts: " + 
                    System.getProperty("java.home") + "/lib/security/cacerts");
            }
            System.out.println();
            
            // 2. 연결 테스트
            System.out.println("═══════════════════════════════════════════════════════════════");
            System.out.println("2️⃣  Connection Test");
            System.out.println("───────────────────────────────────────────────────────────────");
            
            SSLSocketFactory factory = (SSLSocketFactory) SSLSocketFactory.getDefault();
            
            try (SSLSocket socket = (SSLSocket) factory.createSocket(host, port)) {
                socket.setSoTimeout(10000);
                socket.startHandshake();
                
                SSLSession session = socket.getSession();
                System.out.println("   ✅ Handshake successful!");
                System.out.println("   Protocol: " + session.getProtocol());
                System.out.println("   Cipher: " + session.getCipherSuite());
                System.out.println();
                
                // 3. 인증서 체인
                System.out.println("═══════════════════════════════════════════════════════════════");
                System.out.println("3️⃣  Certificate Chain");
                System.out.println("───────────────────────────────────────────────────────────────");
                
                Certificate[] certs = session.getPeerCertificates();
                for (int i = 0; i < certs.length; i++) {
                    if (certs[i] instanceof X509Certificate) {
                        X509Certificate x509 = (X509Certificate) certs[i];
                        String type = (i == 0) ? "Server" : 
                                      (i == certs.length - 1) ? "Root CA" : "Intermediate";
                        
                        System.out.println("\n   [" + i + "] " + type);
                        System.out.println("       Subject: " + x509.getSubjectX500Principal());
                        System.out.println("       Issuer: " + x509.getIssuerX500Principal());
                        System.out.println("       Valid: " + x509.getNotBefore() + 
                                          " ~ " + x509.getNotAfter());
                        
                        // 만료 확인
                        long daysLeft = (x509.getNotAfter().getTime() - 
                                        System.currentTimeMillis()) / (1000 * 60 * 60 * 24);
                        if (daysLeft < 0) {
                            System.out.println("       ❌ EXPIRED!");
                        } else if (daysLeft < 30) {
                            System.out.println("       ⚠️ Expires in " + daysLeft + " days");
                        } else {
                            System.out.println("       ✅ Valid for " + daysLeft + " days");
                        }
                    }
                }
                System.out.println();
                
                // 4. 호스트명 검증
                System.out.println("═══════════════════════════════════════════════════════════════");
                System.out.println("4️⃣  Hostname Verification");
                System.out.println("───────────────────────────────────────────────────────────────");
                
                if (certs[0] instanceof X509Certificate) {
                    X509Certificate serverCert = (X509Certificate) certs[0];
                    
                    // CN 확인
                    String dn = serverCert.getSubjectX500Principal().getName();
                    String cn = "";
                    for (String part : dn.split(",")) {
                        if (part.trim().startsWith("CN=")) {
                            cn = part.trim().substring(3);
                            break;
                        }
                    }
                    System.out.println("   CN: " + cn);
                    System.out.println("   Expected: " + host);
                    
                    // SAN 확인
                    Collection<List<?>> sans = serverCert.getSubjectAlternativeNames();
                    if (sans != null) {
                        System.out.println("   SANs:");
                        boolean matched = false;
                        for (List<?> san : sans) {
                            Integer type = (Integer) san.get(0);
                            String value = san.get(1).toString();
                            String typeStr = (type == 2) ? "DNS" : (type == 7) ? "IP" : "Other";
                            System.out.println("       - " + typeStr + ": " + value);
                            
                            if (type == 2 && matchHostname(host, value)) {
                                matched = true;
                            }
                        }
                        
                        if (matched) {
                            System.out.println("   ✅ Hostname matches SAN");
                        } else if (cn.equals(host)) {
                            System.out.println("   ✅ Hostname matches CN");
                        } else {
                            System.out.println("   ❌ Hostname does not match!");
                        }
                    }
                }
                System.out.println();
                
            }
            
            System.out.println("═══════════════════════════════════════════════════════════════");
            System.out.println("📋 Diagnostics Complete - No issues found");
            System.out.println("═══════════════════════════════════════════════════════════════");
            
        } catch (SSLHandshakeException e) {
            System.out.println("\n❌ SSL Handshake Failed!");
            System.out.println("───────────────────────────────────────────────────────────────");
            System.out.println("Error: " + e.getMessage());
            
            Throwable cause = e.getCause();
            while (cause != null) {
                System.out.println("Caused by: " + cause.getClass().getSimpleName() + 
                                  ": " + cause.getMessage());
                cause = cause.getCause();
            }
            
            // 에러 유형별 조언
            String msg = e.getMessage().toLowerCase();
            System.out.println("\n💡 Suggested fixes:");
            
            if (msg.contains("pkix") || msg.contains("certification path")) {
                System.out.println("   - Root CA is not in TrustStore");
                System.out.println("   - Add CA: keytool -importcert -keystore <ks> -alias <alias> -file <ca.crt>");
            }
            if (msg.contains("expired")) {
                System.out.println("   - Certificate has expired");
                System.out.println("   - Check with: openssl x509 -in cert.crt -noout -dates");
            }
            if (msg.contains("hostname") || msg.contains("name")) {
                System.out.println("   - Hostname doesn't match certificate CN/SAN");
                System.out.println("   - Check with: openssl x509 -in cert.crt -noout -text | grep -A1 'Subject Alternative'");
            }
            
        } catch (Exception e) {
            System.out.println("\n❌ Error: " + e.getMessage());
            e.printStackTrace();
        }
    }
    
    private static boolean matchHostname(String hostname, String pattern) {
        if (pattern.startsWith("*.")) {
            String suffix = pattern.substring(1);
            int dotIndex = hostname.indexOf('.');
            if (dotIndex > 0) {
                return hostname.substring(dotIndex).equalsIgnoreCase(suffix);
            }
        }
        return hostname.equalsIgnoreCase(pattern);
    }
}
EOF

# 컴파일
cd /workspace/java-app
javac TLSDiagnostics.java
```

## 9.2 사용 예시

```bash
# 외부 사이트 진단
java TLSDiagnostics https://www.google.com

# 커스텀 TrustStore로 진단
java -Djavax.net.ssl.trustStore=/workspace/certs/test-cacerts \
     -Djavax.net.ssl.trustStorePassword=changeit \
     TLSDiagnostics https://tls-server.tls-lab.svc.cluster.local
```

---

# 📝 실습 체크리스트

- [ ] Root CA 누락 에러 재현 및 해결
- [ ] 인증서 만료 확인 방법 숙달
- [ ] 호스트명 불일치 에러 이해
- [ ] 중간 CA 누락 문제 진단
- [ ] TLS 버전 호환성 확인
- [ ] Cipher Suite 확인
- [ ] 종합 진단 스크립트 활용
- [ ] Java 진단 클래스 활용

---

## 🔗 다음 실습
[LAB-06-PKI-구축.md](./LAB-06-PKI-구축.md)
