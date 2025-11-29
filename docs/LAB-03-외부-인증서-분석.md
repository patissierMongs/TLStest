# LAB 03: 외부 사이트 인증서 분석

## 🎯 학습 목표
- 실제 운영 중인 사이트의 인증서 구조 분석
- CN과 SAN의 차이점 이해
- 와일드카드 인증서의 동작 방식 파악
- 인증서 체인 깊이와 발급 기관 이해

## 📚 예상 소요 시간: 1시간

## 📋 사전 요구사항
- LAB-01, LAB-02 완료
- Java 실습 Pod 접속 상태

---

# Part 1: 인증서 필드 심화 이해

## 1.1 X.509 인증서 구조

X.509는 인증서의 국제 표준 형식입니다. ITU-T에서 정의했습니다.

```
┌─────────────────────────────────────────────────────────────────┐
│                    X.509 v3 Certificate                         │
├─────────────────────────────────────────────────────────────────┤
│  Version              : 3 (현재 표준)                           │
│  Serial Number        : 고유 일련번호                           │
│  Signature Algorithm  : 서명에 사용된 알고리즘                   │
│  Issuer              : 발급자 (CA) 정보                         │
│  Validity            :                                          │
│    ├─ Not Before     : 유효 시작일                              │
│    └─ Not After      : 만료일                                   │
│  Subject             : 인증서 소유자 정보                        │
│  Subject Public Key  : 공개키                                   │
│  Extensions (v3)     :                                          │
│    ├─ Key Usage              : 키 사용 목적                     │
│    ├─ Extended Key Usage     : 확장 키 사용 목적                │
│    ├─ Subject Alt Name (SAN) : 대체 이름 목록  ★               │
│    ├─ Basic Constraints      : CA 여부                         │
│    ├─ CRL Distribution Points: CRL 위치                        │
│    └─ Authority Info Access  : OCSP 위치                       │
├─────────────────────────────────────────────────────────────────┤
│  Signature           : CA의 디지털 서명                         │
└─────────────────────────────────────────────────────────────────┘
```

## 1.2 Subject와 Issuer의 DN 형식

DN (Distinguished Name)은 X.500 표준의 이름 형식입니다:

```
CN=www.google.com, O=Google LLC, L=Mountain View, ST=California, C=US
```

### 주요 필드
| 약어 | 전체 이름 | 설명 | 예시 |
|------|----------|------|------|
| CN | Common Name | 일반 이름 (도메인) | www.google.com |
| O | Organization | 조직명 | Google LLC |
| OU | Organizational Unit | 부서명 | IT Department |
| L | Locality | 도시 | Mountain View |
| ST | State | 주/도 | California |
| C | Country | 국가 코드 (2자리) | US |

## 1.3 CN vs SAN

### CN (Common Name)
- **역사**: SSL 초기부터 사용된 레거시 방식
- **위치**: Subject 필드 내
- **제한**: 하나의 도메인만 지정 가능
- **현재**: 더 이상 권장되지 않음

### SAN (Subject Alternative Name)
- **역사**: X.509 v3 확장으로 추가
- **위치**: Extensions 섹션
- **장점**: 여러 도메인, IP 주소 지정 가능
- **현재**: 모든 최신 브라우저가 SAN 우선 사용

```
┌────────────────────────────────────────────────────────────────┐
│                    CN vs SAN 비교                              │
├────────────────────────────────────────────────────────────────┤
│                                                                │
│  [과거 방식 - CN만 사용]                                        │
│  Subject: CN=www.example.com                                   │
│  → www.example.com만 유효                                      │
│  → example.com 접속 시 경고!                                   │
│                                                                │
│  [현대 방식 - SAN 사용]                                        │
│  Subject: CN=example.com                                       │
│  SAN: DNS:example.com, DNS:www.example.com,                   │
│       DNS:api.example.com, DNS:*.example.com                   │
│  → 모든 나열된 도메인에서 유효                                  │
│                                                                │
└────────────────────────────────────────────────────────────────┘
```

### 브라우저의 검증 순서
1. SAN이 있으면 SAN만 확인 (CN 무시)
2. SAN이 없으면 CN 확인 (레거시 호환)

## 1.4 와일드카드 인증서

### 형식
```
*.example.com
```

### 매칭 규칙
```
*.example.com 인증서가 커버하는 도메인:
  ✓ www.example.com
  ✓ api.example.com
  ✓ mail.example.com
  ✓ any-subdomain.example.com

커버하지 않는 도메인:
  ✗ example.com          (루트 도메인)
  ✗ sub.www.example.com  (2단계 서브도메인)
  ✗ other.com            (다른 도메인)
```

### 실무에서의 활용
```
보통 인증서에는 둘 다 포함:
  SAN: DNS:example.com, DNS:*.example.com

이렇게 하면:
  - example.com (루트) ✓
  - www.example.com ✓
  - api.example.com ✓
```

---

# Part 2: 실제 사이트 인증서 분석

## 2.1 Google 인증서 분석

```bash
cd /workspace/certs

# 인증서 체인 추출
/opt/scripts/extract-certs.sh www.google.com
```

### 출력 예시
```
🔐 Extracting certificate chain from www.google.com:443...

📜 Extracted certificates:

📄 www.google.com-0.crt
   Subject: CN = www.google.com
   Issuer:  CN = GTS CA 1C3, O = Google Trust Services LLC, C = US

📄 www.google.com-1.crt
   Subject: CN = GTS CA 1C3, O = Google Trust Services LLC, C = US
   Issuer:  CN = GTS Root R1, O = Google Trust Services LLC, C = US

📄 www.google.com-2.crt
   Subject: CN = GTS Root R1, O = Google Trust Services LLC, C = US
   Issuer:  CN = GTS Root R1, O = Google Trust Services LLC, C = US

✅ Certificates saved to: /workspace/certs/www.google.com/
```

### 체인 구조 분석
```
[Root CA] GTS Root R1
    │
    │ 서명
    ▼
[Intermediate] GTS CA 1C3
    │
    │ 서명
    ▼
[Server] www.google.com
```

## 2.2 서버 인증서 상세 분석

```bash
# 서버 인증서 상세 정보
openssl x509 -in /workspace/certs/www.google.com/www.google.com-0.crt \
  -noout -text
```

### 주요 필드 확인

```bash
# Subject 확인
openssl x509 -in /workspace/certs/www.google.com/www.google.com-0.crt \
  -noout -subject
# 출력: subject=CN = www.google.com

# Issuer 확인
openssl x509 -in /workspace/certs/www.google.com/www.google.com-0.crt \
  -noout -issuer
# 출력: issuer=C = US, O = Google Trust Services LLC, CN = GTS CA 1C3

# 유효기간 확인
openssl x509 -in /workspace/certs/www.google.com/www.google.com-0.crt \
  -noout -dates
# 출력:
# notBefore=Jan  8 08:20:35 2025 GMT
# notAfter=Apr  2 08:20:34 2025 GMT

# SAN 확인 (핵심!)
openssl x509 -in /workspace/certs/www.google.com/www.google.com-0.crt \
  -noout -text | grep -A1 "Subject Alternative Name"
```

### SAN 출력 예시
```
X509v3 Subject Alternative Name: 
    DNS:www.google.com
```

Google의 www 인증서는 단일 도메인용입니다.

## 2.3 Naver 인증서 분석 (멀티 도메인)

```bash
/opt/scripts/extract-certs.sh www.naver.com
```

```bash
# SAN 확인
openssl x509 -in /workspace/certs/www.naver.com/www.naver.com-0.crt \
  -noout -text | grep -A5 "Subject Alternative Name"
```

### 출력 예시
```
X509v3 Subject Alternative Name: 
    DNS:www.naver.com, DNS:www.naver.net, DNS:naver.com, 
    DNS:naver.net, DNS:*.naver.com, DNS:*.naver.net
```

Naver는 여러 도메인과 와일드카드를 하나의 인증서로 커버합니다!

## 2.4 GitHub 인증서 분석

```bash
/opt/scripts/extract-certs.sh github.com

# SAN 확인
openssl x509 -in /workspace/certs/github.com/github.com-0.crt \
  -noout -text | grep -A3 "Subject Alternative Name"
```

### 출력 예시
```
X509v3 Subject Alternative Name: 
    DNS:github.com, DNS:www.github.com
```

## 2.5 인증서 비교 표

```bash
# 각 사이트 인증서 정보 비교
echo "=== Google ==="
openssl x509 -in /workspace/certs/www.google.com/www.google.com-0.crt \
  -noout -subject -issuer -dates

echo ""
echo "=== Naver ==="
openssl x509 -in /workspace/certs/www.naver.com/www.naver.com-0.crt \
  -noout -subject -issuer -dates

echo ""
echo "=== GitHub ==="
openssl x509 -in /workspace/certs/github.com/github.com-0.crt \
  -noout -subject -issuer -dates
```

---

# Part 3: 인증서 체인 깊이 분석

## 3.1 체인 길이 비교

```bash
# 각 사이트의 체인 길이 확인
echo "Google chain: $(ls /workspace/certs/www.google.com/*.crt | wc -l) certs"
echo "Naver chain: $(ls /workspace/certs/www.naver.com/*.crt | wc -l) certs"
echo "GitHub chain: $(ls /workspace/certs/github.com/*.crt | wc -l) certs"
```

### 일반적인 체인 구조

```
[2단계 체인]                    [3단계 체인]
Root CA                        Root CA
   │                              │
   └─> Server Cert                └─> Intermediate CA
                                         │
                                         └─> Server Cert
```

## 3.2 왜 중간 CA를 사용하는가?

### 보안상의 이유

```
┌─────────────────────────────────────────────────────────────────┐
│                    Root CA 보호                                 │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  Root CA의 개인키는 극도로 중요!                                 │
│  - 유출 시 모든 인증서가 위험                                    │
│  - 오프라인 보관 (HSM, 금고 등)                                  │
│  - 직접 인증서 발급에 사용하지 않음                              │
│                                                                 │
│  대신 Intermediate CA를 사용:                                   │
│  - Root가 Intermediate에 서명                                   │
│  - Intermediate가 실제 서버 인증서 발급                         │
│  - Intermediate 키 유출 시 해당 CA만 폐기                       │
│                                                                 │
│  Root CA ──서명──> Intermediate CA ──서명──> Server Cert        │
│  (오프라인)          (온라인)                 (서버)             │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

## 3.3 Cross-Signing 이해

Let's Encrypt 같은 신규 CA는 Cross-Signing을 사용합니다:

```bash
# Let's Encrypt 사이트 인증서 분석
/opt/scripts/extract-certs.sh letsencrypt.org

# 체인 확인
for cert in /workspace/certs/letsencrypt.org/*.crt; do
    echo "=== $(basename $cert) ==="
    openssl x509 -in "$cert" -noout -subject -issuer
    echo ""
done
```

### Cross-Signing이란?

```
┌─────────────────────────────────────────────────────────────────┐
│                    Cross-Signing                                │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  [기존 신뢰받는 Root]        [신규 Root - 아직 배포 안됨]        │
│  DST Root CA X3              ISRG Root X1                       │
│       │                           │                             │
│       │ Cross-Sign                │                             │
│       ▼                           ▼                             │
│  ┌─────────────────────────────────────┐                       │
│  │     Let's Encrypt CA (R3)           │                       │
│  │  (두 Root에서 모두 신뢰됨)           │                       │
│  └─────────────────────────────────────┘                       │
│       │                                                         │
│       ▼                                                         │
│  [Server Certificate]                                           │
│                                                                 │
│  오래된 시스템: DST Root 체인으로 검증                          │
│  최신 시스템: ISRG Root 체인으로 검증                           │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

# Part 4: 인증서 유효성 검증 실습

## 4.1 체인 검증

```bash
cd /workspace/certs/www.google.com

# 체인 검증 (Root로 Server 검증)
# 중간 CA를 untrusted로 지정하고 Root를 신뢰 기반으로 사용
openssl verify \
  -CAfile www.google.com-2.crt \
  -untrusted www.google.com-1.crt \
  www.google.com-0.crt
```

### 출력
```
www.google.com-0.crt: OK
```

### 옵션 설명
| 옵션 | 설명 |
|------|------|
| `-CAfile` | 신뢰할 Root CA 인증서 |
| `-untrusted` | 체인에 포함되지만 직접 신뢰하지 않는 중간 인증서 |

## 4.2 잘못된 체인으로 검증 (실패 예상)

```bash
# Root 없이 검증 시도
openssl verify www.google.com-0.crt

# 출력:
# C = US, O = Google Trust Services LLC, CN = GTS CA 1C3
# error 20 at 0 depth lookup: unable to get local issuer certificate
# error www.google.com-0.crt: verification failed
```

## 4.3 만료 확인

```bash
# 현재 날짜와 비교하여 만료 여부 확인
openssl x509 -in www.google.com-0.crt -noout -checkend 0
# 출력: Certificate will not expire (아직 유효)

# 30일 후 만료 여부 확인
openssl x509 -in www.google.com-0.crt -noout -checkend 2592000
# 2592000 = 30일 * 24시간 * 60분 * 60초
```

## 4.4 인증서 해시값 확인

```bash
# SHA256 fingerprint
openssl x509 -in www.google.com-0.crt -noout -fingerprint -sha256

# SHA1 fingerprint (레거시)
openssl x509 -in www.google.com-0.crt -noout -fingerprint -sha1
```

---

# Part 5: Java에서 검증

## 5.1 외부 사이트 연결 및 체인 출력

```bash
cd /workspace/java-app

# Google
java TLSConnectionTest https://www.google.com

# Naver
java TLSConnectionTest https://www.naver.com

# GitHub
java TLSConnectionTest https://github.com
```

## 5.2 상세 검증기로 분석

```bash
# 상세 검증 (CN/SAN 확인 포함)
java CertificateChainValidator https://www.google.com
```

### 출력 예시
```
🔍 Validating certificate chain for: https://www.google.com
════════════════════════════════════════════════════════════
📁 Using default truststore

🌐 Hostname Verification:
   Expected: www.google.com
   CN: www.google.com
   SANs:
      - DNS: www.google.com
   ✅ Hostname matches SAN

✅ Certificate chain validated successfully!

📊 Connection Details:
   Response: 200 OK
   Protocol: TLSv1.3
   Cipher: TLS_AES_256_GCM_SHA384
```

## 5.3 호스트명 불일치 테스트

```bash
# IP로 접속 시도 (SAN에 IP가 없으면 실패)
java CertificateChainValidator https://142.250.196.100
# Google의 IP - SAN에 이 IP가 없으므로 hostname 검증 실패
```

---

# Part 6: 주요 CA 비교

## 6.1 유명 CA들의 인증서 비교

```bash
# 다양한 사이트의 CA 확인
sites=("google.com" "facebook.com" "amazon.com" "microsoft.com" "apple.com")

for site in "${sites[@]}"; do
    echo "=== $site ==="
    echo | openssl s_client -connect ${site}:443 2>/dev/null | \
      openssl x509 -noout -issuer
    echo ""
done
```

### 주요 CA 목록

| CA | 특징 |
|----|------|
| DigiCert | 대기업, 금융권 선호 |
| Let's Encrypt | 무료, 자동화 |
| Sectigo (Comodo) | 가격 경쟁력 |
| GlobalSign | 유럽 강세 |
| Google Trust Services | Google 자체 CA |
| Amazon Trust Services | AWS 서비스용 |

## 6.2 EV vs DV vs OV 인증서

```
┌─────────────────────────────────────────────────────────────────┐
│                    인증서 검증 수준                              │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  DV (Domain Validation)                                        │
│  - 도메인 소유권만 확인                                         │
│  - 자동 발급 가능                                               │
│  - Let's Encrypt가 대표적                                       │
│  - 가격: 무료 ~ 저렴                                            │
│                                                                 │
│  OV (Organization Validation)                                  │
│  - 조직 실체 확인                                               │
│  - 사업자 등록증 등 서류 필요                                    │
│  - 발급까지 며칠 소요                                           │
│  - 가격: 중간                                                   │
│                                                                 │
│  EV (Extended Validation)                                      │
│  - 가장 엄격한 검증                                             │
│  - 법적 실체, 물리적 주소 확인                                   │
│  - 예전에는 주소창이 녹색으로 표시됨                             │
│  - 가격: 비쌈                                                   │
│                                                                 │
│  ※ 암호화 강도는 동일! 차이는 "신원 확인 수준"                   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

# Part 7: 실무 활용 팁

## 7.1 인증서 만료 모니터링 스크립트

```bash
# 여러 사이트의 만료일 확인
cat << 'EOF' > /workspace/scripts/check-expiry.sh
#!/bin/bash
sites=("google.com" "naver.com" "github.com" "your-internal-server:443")

for site in "${sites[@]}"; do
    expiry=$(echo | openssl s_client -connect ${site}:443 2>/dev/null | \
      openssl x509 -noout -enddate 2>/dev/null | cut -d= -f2)
    
    if [ -n "$expiry" ]; then
        echo "$site: $expiry"
    else
        echo "$site: Unable to connect"
    fi
done
EOF

chmod +x /workspace/scripts/check-expiry.sh
```

## 7.2 인증서 정보 JSON 출력

```bash
# 인증서 정보를 JSON으로 추출
openssl x509 -in /workspace/certs/www.google.com/www.google.com-0.crt \
  -noout -subject -issuer -dates -serial | \
  awk -F'=' '{
    gsub(/^ +| +$/, "", $2)
    if ($1 ~ /subject/) print "\"subject\": \""$2"\","
    if ($1 ~ /issuer/) print "\"issuer\": \""$2"\","
    if ($1 ~ /notBefore/) print "\"validFrom\": \""$2"\","
    if ($1 ~ /notAfter/) print "\"validTo\": \""$2"\","
    if ($1 ~ /serial/) print "\"serial\": \""$2"\""
  }' | sed '1s/^/{/; $s/$/}/'
```

---

# 📝 실습 체크리스트

- [ ] X.509 인증서 구조 이해
- [ ] CN과 SAN의 차이점 파악
- [ ] 와일드카드 인증서 매칭 규칙 이해
- [ ] Google, Naver, GitHub 인증서 체인 추출
- [ ] 인증서 체인 깊이 비교
- [ ] openssl verify로 체인 검증
- [ ] Java에서 호스트명 검증 확인
- [ ] 주요 CA 비교

---

## 🔗 다음 실습
[LAB-04-mTLS-실습.md](./LAB-04-mTLS-실습.md)
