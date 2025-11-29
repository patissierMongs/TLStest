# LAB 06: 자체 PKI 구축

## 🎯 학습 목표
- PKI(Public Key Infrastructure)의 구조와 동작 원리 이해
- 루트 CA → 중간 CA → 서버 인증서 체인 직접 생성
- 인증서 폐기(Revocation) 개념 이해
- cert-manager를 통한 자동 인증서 관리

## 📚 예상 소요 시간: 반나절 (3-4시간)

## 📋 사전 요구사항
- LAB-01 ~ LAB-05 완료
- Java 실습 Pod 접속 상태

---

# Part 1: PKI 이론

## 1.1 PKI란?

PKI(Public Key Infrastructure)는 디지털 인증서를 생성, 관리, 배포, 사용, 저장, 폐기하기 위한 
정책, 절차, 하드웨어, 소프트웨어의 집합입니다.

```
┌─────────────────────────────────────────────────────────────────┐
│                        PKI 생태계                               │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌─────────────┐                                               │
│  │  Root CA    │ 최상위 신뢰 기관                               │
│  │  (오프라인)  │ 개인키는 HSM에 보관                            │
│  └──────┬──────┘                                               │
│         │ 서명                                                  │
│         ▼                                                      │
│  ┌─────────────┐  ┌─────────────┐                              │
│  │Intermediate│  │Intermediate│ 실제 인증서 발급 담당           │
│  │   CA #1    │  │   CA #2    │ 온라인 운영                     │
│  └──────┬──────┘  └──────┬──────┘                              │
│         │                │                                      │
│    ┌────┴────┐      ┌────┴────┐                                │
│    │  서명    │      │  서명    │                                │
│    ▼         ▼      ▼         ▼                                │
│  ┌─────┐ ┌─────┐ ┌─────┐ ┌─────┐                              │
│  │서버A│ │서버B│ │서버C│ │서버D│ 최종 사용자 인증서             │
│  └─────┘ └─────┘ └─────┘ └─────┘                              │
│                                                                 │
│  ┌────────────────────────────────────────┐                    │
│  │            지원 서비스                  │                    │
│  │  ┌──────┐  ┌──────┐  ┌──────────────┐ │                    │
│  │  │ OCSP │  │ CRL  │  │Registration  │ │                    │
│  │  │Server│  │Server│  │  Authority   │ │                    │
│  │  └──────┘  └──────┘  └──────────────┘ │                    │
│  └────────────────────────────────────────┘                    │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

## 1.2 PKI 구성 요소

### 인증 기관 (Certificate Authority, CA)
| 구성 요소 | 역할 |
|----------|------|
| Root CA | 최상위 CA, 자체 서명, 오프라인 보관 |
| Intermediate CA | 중간 CA, 실제 인증서 발급 |
| Registration Authority | 인증서 요청 검증 (신원 확인) |

### 인증서 관리
| 구성 요소 | 역할 |
|----------|------|
| CRL | Certificate Revocation List - 폐기 인증서 목록 |
| OCSP | Online Certificate Status Protocol - 실시간 상태 확인 |
| Certificate Repository | 인증서 저장소 (LDAP 등) |

## 1.3 인증서 수명주기

```
┌─────────────────────────────────────────────────────────────────┐
│                    인증서 수명주기                               │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  1. 키 쌍 생성        ──────────────────────────────────────>   │
│     (공개키 + 개인키)                                           │
│           │                                                     │
│           ▼                                                     │
│  2. CSR 생성          ──────────────────────────────────────>   │
│     (Certificate Signing Request)                              │
│           │                                                     │
│           ▼                                                     │
│  3. CA에 CSR 제출     ──────────────────────────────────────>   │
│           │                                                     │
│           ▼                                                     │
│  4. CA 검증           ──────────────────────────────────────>   │
│     (도메인 소유권, 조직 확인 등)                                │
│           │                                                     │
│           ▼                                                     │
│  5. 인증서 발급       ──────────────────────────────────────>   │
│     (CA가 CSR에 서명)                                           │
│           │                                                     │
│           ▼                                                     │
│  6. 인증서 사용       ──────────────────────────────────────>   │
│     (서버에 설치, TLS 통신)                                     │
│           │                                                     │
│      ┌────┴────┐                                               │
│      ▼         ▼                                               │
│  7a. 갱신      7b. 폐기     ──────────────────────────────────> │
│  (만료 전)    (침해 시)                                         │
│                    │                                            │
│                    ▼                                            │
│               CRL/OCSP 등록                                     │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

## 1.4 인증서 폐기 (Revocation)

### 왜 폐기가 필요한가?
- 개인키 유출/도난
- CA 침해
- 소속 변경 (퇴사 등)
- 인증서 정보 변경 필요

### CRL (Certificate Revocation List)
```
┌─────────────────────────────────────────┐
│     Certificate Revocation List        │
├─────────────────────────────────────────┤
│ Issuer: CN=MyCA                        │
│ This Update: 2025-01-15 00:00:00       │
│ Next Update: 2025-01-16 00:00:00       │
├─────────────────────────────────────────┤
│ Revoked Certificates:                  │
│   Serial: 0x1234, Date: 2025-01-10    │
│   Serial: 0x5678, Date: 2025-01-12    │
│   Serial: 0x9ABC, Date: 2025-01-14    │
└─────────────────────────────────────────┘

장점: 오프라인 검증 가능
단점: 목록 크기 증가, 업데이트 지연
```

### OCSP (Online Certificate Status Protocol)
```
┌──────────┐     "인증서 0x1234 유효해?"     ┌──────────┐
│ 클라이언트│ ─────────────────────────────> │  OCSP    │
│          │                                │  Server  │
│          │ <───────────────────────────── │          │
└──────────┘     "Good / Revoked / Unknown" └──────────┘

장점: 실시간, 응답 작음
단점: 온라인 필요, OCSP 서버 부하
```

---

# Part 2: Root CA 구축

## 2.1 디렉토리 구조 생성

```bash
cd /workspace/certs
mkdir -p pki/{root-ca,intermediate-ca,server-certs,crl,ocsp}
mkdir -p pki/root-ca/{private,certs,newcerts,crl}
mkdir -p pki/intermediate-ca/{private,certs,newcerts,crl,csr}

cd pki

# 시리얼 번호 및 인덱스 파일 초기화
echo 1000 > root-ca/serial
echo 1000 > intermediate-ca/serial
touch root-ca/index.txt
touch intermediate-ca/index.txt
echo 1000 > root-ca/crlnumber
echo 1000 > intermediate-ca/crlnumber
```

## 2.2 Root CA 설정 파일

```bash
cat << 'EOF' > root-ca/openssl.cnf
# Root CA OpenSSL Configuration

[ ca ]
default_ca = CA_default

[ CA_default ]
dir               = /workspace/certs/pki/root-ca
certs             = $dir/certs
crl_dir           = $dir/crl
new_certs_dir     = $dir/newcerts
database          = $dir/index.txt
serial            = $dir/serial
RANDFILE          = $dir/private/.rand

private_key       = $dir/private/root-ca.key
certificate       = $dir/certs/root-ca.crt

crlnumber         = $dir/crlnumber
crl               = $dir/crl/root-ca.crl
crl_extensions    = crl_ext
default_crl_days  = 30

default_md        = sha256
name_opt          = ca_default
cert_opt          = ca_default
default_days      = 3650
preserve          = no
policy            = policy_strict

[ policy_strict ]
countryName             = match
stateOrProvinceName     = match
organizationName        = match
organizationalUnitName  = optional
commonName              = supplied
emailAddress            = optional

[ policy_loose ]
countryName             = optional
stateOrProvinceName     = optional
localityName            = optional
organizationName        = optional
organizationalUnitName  = optional
commonName              = supplied
emailAddress            = optional

[ req ]
default_bits        = 4096
distinguished_name  = req_distinguished_name
string_mask         = utf8only
default_md          = sha256
x509_extensions     = v3_ca

[ req_distinguished_name ]
countryName                     = Country Name (2 letter code)
stateOrProvinceName             = State or Province Name
localityName                    = Locality Name
0.organizationName              = Organization Name
organizationalUnitName          = Organizational Unit Name
commonName                      = Common Name
emailAddress                    = Email Address

countryName_default             = KR
stateOrProvinceName_default     = Seoul
localityName_default            = Seoul
0.organizationName_default      = TLS Practice Lab
organizationalUnitName_default  = PKI Department

[ v3_ca ]
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid:always,issuer
basicConstraints = critical, CA:true
keyUsage = critical, digitalSignature, cRLSign, keyCertSign

[ v3_intermediate_ca ]
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid:always,issuer
basicConstraints = critical, CA:true, pathlen:0
keyUsage = critical, digitalSignature, cRLSign, keyCertSign

[ crl_ext ]
authorityKeyIdentifier=keyid:always

[ ocsp ]
basicConstraints = CA:FALSE
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid,issuer
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, OCSPSigning
EOF
```

## 2.3 Root CA 키 및 인증서 생성

```bash
cd /workspace/certs/pki

# Root CA 개인키 생성 (4096 bit, 실무에서는 HSM 사용)
openssl genrsa -aes256 -out root-ca/private/root-ca.key 4096
# 비밀번호 입력: labpassword (실습용)

# 권한 설정
chmod 400 root-ca/private/root-ca.key

# Root CA 인증서 생성 (자체 서명, 10년 유효)
openssl req -config root-ca/openssl.cnf \
  -key root-ca/private/root-ca.key \
  -new -x509 -days 3650 -sha256 \
  -extensions v3_ca \
  -out root-ca/certs/root-ca.crt \
  -subj "/C=KR/ST=Seoul/L=Seoul/O=TLS Practice Lab/OU=PKI Department/CN=Lab Root CA"
# 비밀번호 입력: labpassword

# 인증서 확인
openssl x509 -in root-ca/certs/root-ca.crt -noout -text | head -30
```

### Root CA 인증서 확인
```bash
echo "=== Root CA Certificate ==="
openssl x509 -in root-ca/certs/root-ca.crt -noout \
  -subject -issuer -dates

# 출력:
# subject=C = KR, ST = Seoul, L = Seoul, O = TLS Practice Lab, 
#         OU = PKI Department, CN = Lab Root CA
# issuer=C = KR, ST = Seoul, L = Seoul, O = TLS Practice Lab, 
#        OU = PKI Department, CN = Lab Root CA    ← Self-Signed!
# notBefore=Jan 15 12:00:00 2025 GMT
# notAfter=Jan 12 12:00:00 2035 GMT              ← 10년 유효
```

---

# Part 3: Intermediate CA 구축

## 3.1 Intermediate CA 설정 파일

```bash
cat << 'EOF' > intermediate-ca/openssl.cnf
# Intermediate CA OpenSSL Configuration

[ ca ]
default_ca = CA_default

[ CA_default ]
dir               = /workspace/certs/pki/intermediate-ca
certs             = $dir/certs
crl_dir           = $dir/crl
new_certs_dir     = $dir/newcerts
database          = $dir/index.txt
serial            = $dir/serial
RANDFILE          = $dir/private/.rand

private_key       = $dir/private/intermediate-ca.key
certificate       = $dir/certs/intermediate-ca.crt

crlnumber         = $dir/crlnumber
crl               = $dir/crl/intermediate-ca.crl
crl_extensions    = crl_ext
default_crl_days  = 30

default_md        = sha256
name_opt          = ca_default
cert_opt          = ca_default
default_days      = 375
preserve          = no
policy            = policy_loose

[ policy_loose ]
countryName             = optional
stateOrProvinceName     = optional
localityName            = optional
organizationName        = optional
organizationalUnitName  = optional
commonName              = supplied
emailAddress            = optional

[ req ]
default_bits        = 4096
distinguished_name  = req_distinguished_name
string_mask         = utf8only
default_md          = sha256
x509_extensions     = v3_ca

[ req_distinguished_name ]
countryName                     = Country Name (2 letter code)
stateOrProvinceName             = State or Province Name
localityName                    = Locality Name
0.organizationName              = Organization Name
organizationalUnitName          = Organizational Unit Name
commonName                      = Common Name

[ v3_intermediate_ca ]
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid:always,issuer
basicConstraints = critical, CA:true, pathlen:0
keyUsage = critical, digitalSignature, cRLSign, keyCertSign

[ server_cert ]
basicConstraints = CA:FALSE
nsCertType = server
nsComment = "OpenSSL Generated Server Certificate"
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid,issuer:always
keyUsage = critical, digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth
crlDistributionPoints = URI:http://pki.lab.local/crl/intermediate-ca.crl
authorityInfoAccess = OCSP;URI:http://ocsp.lab.local

[ client_cert ]
basicConstraints = CA:FALSE
nsCertType = client, email
nsComment = "OpenSSL Generated Client Certificate"
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid,issuer
keyUsage = critical, nonRepudiation, digitalSignature, keyEncipherment
extendedKeyUsage = clientAuth, emailProtection

[ crl_ext ]
authorityKeyIdentifier=keyid:always
EOF
```

## 3.2 Intermediate CA 키 및 CSR 생성

```bash
cd /workspace/certs/pki

# Intermediate CA 개인키 생성
openssl genrsa -aes256 -out intermediate-ca/private/intermediate-ca.key 4096
# 비밀번호: intpassword

chmod 400 intermediate-ca/private/intermediate-ca.key

# CSR 생성 (Certificate Signing Request)
openssl req -config intermediate-ca/openssl.cnf \
  -new -sha256 \
  -key intermediate-ca/private/intermediate-ca.key \
  -out intermediate-ca/csr/intermediate-ca.csr \
  -subj "/C=KR/ST=Seoul/L=Seoul/O=TLS Practice Lab/OU=PKI Department/CN=Lab Intermediate CA"
# 비밀번호: intpassword

# CSR 확인
openssl req -in intermediate-ca/csr/intermediate-ca.csr -noout -text | head -20
```

## 3.3 Root CA로 Intermediate CA 서명

```bash
# Root CA가 Intermediate CA의 CSR에 서명
openssl ca -config root-ca/openssl.cnf \
  -extensions v3_intermediate_ca \
  -days 1825 -notext -md sha256 \
  -in intermediate-ca/csr/intermediate-ca.csr \
  -out intermediate-ca/certs/intermediate-ca.crt
# Root CA 비밀번호: labpassword
# Sign the certificate? [y/n]: y
# 1 out of 1 certificate requests certified, commit? [y/n]: y

# 인증서 확인
openssl x509 -in intermediate-ca/certs/intermediate-ca.crt -noout \
  -subject -issuer -dates
```

### 출력
```
subject=C = KR, ST = Seoul, L = Seoul, O = TLS Practice Lab, 
        OU = PKI Department, CN = Lab Intermediate CA
issuer=C = KR, ST = Seoul, L = Seoul, O = TLS Practice Lab, 
       OU = PKI Department, CN = Lab Root CA        ← Root CA가 서명!
notBefore=Jan 15 12:00:00 2025 GMT
notAfter=Jan 14 12:00:00 2030 GMT                   ← 5년 유효
```

## 3.4 인증서 체인 파일 생성

```bash
# 체인 파일 생성 (Intermediate + Root)
cat intermediate-ca/certs/intermediate-ca.crt \
    root-ca/certs/root-ca.crt > intermediate-ca/certs/ca-chain.crt

# 체인 확인
openssl crl2pkcs7 -nocrl \
  -certfile intermediate-ca/certs/ca-chain.crt | \
  openssl pkcs7 -print_certs -noout
```

---

# Part 4: 서버 인증서 발급

## 4.1 서버 키 및 CSR 생성

```bash
cd /workspace/certs/pki

# 서버 개인키 생성 (비밀번호 없음 - 서버 자동 시작용)
openssl genrsa -out server-certs/myserver.key 2048

# SAN을 포함한 CSR 생성을 위한 설정
cat << EOF > server-certs/myserver.cnf
[req]
default_bits = 2048
prompt = no
default_md = sha256
distinguished_name = dn
req_extensions = req_ext

[dn]
C = KR
ST = Seoul
L = Seoul
O = TLS Practice Lab
OU = Web Services
CN = myserver.lab.local

[req_ext]
subjectAltName = @alt_names

[alt_names]
DNS.1 = myserver.lab.local
DNS.2 = myserver
DNS.3 = localhost
DNS.4 = *.myserver.lab.local
IP.1 = 127.0.0.1
IP.2 = 10.0.0.100
EOF

# CSR 생성
openssl req -new \
  -key server-certs/myserver.key \
  -out server-certs/myserver.csr \
  -config server-certs/myserver.cnf

# CSR 확인
openssl req -in server-certs/myserver.csr -noout -text | grep -A10 "Subject:"
```

## 4.2 Intermediate CA로 서버 인증서 발급

```bash
# SAN 확장을 포함하여 서명
openssl ca -config intermediate-ca/openssl.cnf \
  -extensions server_cert \
  -days 365 -notext -md sha256 \
  -in server-certs/myserver.csr \
  -out server-certs/myserver.crt \
  -extfile server-certs/myserver.cnf \
  -extensions req_ext
# Intermediate CA 비밀번호: intpassword

# 인증서 확인
openssl x509 -in server-certs/myserver.crt -noout -text | head -40
```

## 4.3 전체 체인 확인

```bash
# 체인 파일 생성 (서버 + 중간 CA)
cat server-certs/myserver.crt \
    intermediate-ca/certs/intermediate-ca.crt > server-certs/myserver-fullchain.crt

# 체인 검증
openssl verify -CAfile root-ca/certs/root-ca.crt \
  -untrusted intermediate-ca/certs/intermediate-ca.crt \
  server-certs/myserver.crt

# 출력: server-certs/myserver.crt: OK
```

## 4.4 체인 구조 확인

```bash
echo "=== Certificate Chain ==="
echo ""
echo "[0] Server Certificate"
openssl x509 -in server-certs/myserver.crt -noout -subject -issuer | sed 's/^/    /'
echo ""
echo "[1] Intermediate CA"
openssl x509 -in intermediate-ca/certs/intermediate-ca.crt -noout -subject -issuer | sed 's/^/    /'
echo ""
echo "[2] Root CA"
openssl x509 -in root-ca/certs/root-ca.crt -noout -subject -issuer | sed 's/^/    /'
```

### 출력
```
=== Certificate Chain ===

[0] Server Certificate
    subject=C = KR, ..., CN = myserver.lab.local
    issuer=C = KR, ..., CN = Lab Intermediate CA

[1] Intermediate CA
    subject=C = KR, ..., CN = Lab Intermediate CA
    issuer=C = KR, ..., CN = Lab Root CA

[2] Root CA
    subject=C = KR, ..., CN = Lab Root CA
    issuer=C = KR, ..., CN = Lab Root CA           ← Self-Signed
```

---

# Part 5: 인증서 폐기 (CRL)

## 5.1 인증서 폐기

```bash
cd /workspace/certs/pki

# 테스트용 인증서 하나 더 발급
openssl genrsa -out server-certs/revoke-test.key 2048
openssl req -new -key server-certs/revoke-test.key \
  -out server-certs/revoke-test.csr \
  -subj "/CN=revoke-test.lab.local"

openssl ca -config intermediate-ca/openssl.cnf \
  -extensions server_cert \
  -days 365 -notext -md sha256 \
  -in server-certs/revoke-test.csr \
  -out server-certs/revoke-test.crt
# 비밀번호: intpassword

# 인증서 시리얼 번호 확인
openssl x509 -in server-certs/revoke-test.crt -noout -serial

# 인증서 폐기!
openssl ca -config intermediate-ca/openssl.cnf \
  -revoke server-certs/revoke-test.crt
# 비밀번호: intpassword

# index.txt 확인 (R = Revoked)
cat intermediate-ca/index.txt
```

### index.txt 형식
```
V  260115120000Z    1000  unknown  /C=KR/.../CN=myserver.lab.local
R  260115120000Z  250115120000Z  1001  unknown  /C=KR/.../CN=revoke-test.lab.local
│                      │
│                      └─ 폐기 시간
└─ V=Valid, R=Revoked, E=Expired
```

## 5.2 CRL 생성

```bash
# CRL 생성
openssl ca -config intermediate-ca/openssl.cnf \
  -gencrl -out intermediate-ca/crl/intermediate-ca.crl
# 비밀번호: intpassword

# CRL 내용 확인
openssl crl -in intermediate-ca/crl/intermediate-ca.crl -noout -text
```

### CRL 출력
```
Certificate Revocation List (CRL):
        Version 2 (0x1)
        Signature Algorithm: sha256WithRSAEncryption
        Issuer: C = KR, ..., CN = Lab Intermediate CA
        Last Update: Jan 15 12:00:00 2025 GMT
        Next Update: Feb 14 12:00:00 2025 GMT
Revoked Certificates:
    Serial Number: 1001
        Revocation Date: Jan 15 12:00:00 2025 GMT
```

## 5.3 CRL로 인증서 상태 확인

```bash
# 유효한 인증서 확인
openssl verify -crl_check \
  -CAfile <(cat root-ca/certs/root-ca.crt intermediate-ca/crl/intermediate-ca.crl) \
  -untrusted intermediate-ca/certs/intermediate-ca.crt \
  server-certs/myserver.crt
# 출력: server-certs/myserver.crt: OK

# 폐기된 인증서 확인
openssl verify -crl_check \
  -CAfile <(cat root-ca/certs/root-ca.crt intermediate-ca/crl/intermediate-ca.crl) \
  -untrusted intermediate-ca/certs/intermediate-ca.crt \
  server-certs/revoke-test.crt
# 출력: error 23 at 0 depth lookup: certificate revoked
```

---

# Part 6: Java에서 PKI 사용

## 6.1 Root CA를 TrustStore에 추가

```bash
cd /workspace/certs

# 새 TrustStore 생성
keytool -importcert \
  -keystore pki-truststore.p12 \
  -storepass changeit \
  -alias "lab-root-ca" \
  -file pki/root-ca/certs/root-ca.crt \
  -noprompt

# 확인
keytool -list -keystore pki-truststore.p12 -storepass changeit
```

## 6.2 서버 인증서를 KeyStore로 변환

```bash
cd /workspace/certs/pki

# PKCS12 형식으로 변환 (개인키 + 인증서 + 체인)
openssl pkcs12 -export \
  -in server-certs/myserver.crt \
  -inkey server-certs/myserver.key \
  -certfile intermediate-ca/certs/intermediate-ca.crt \
  -out server-certs/myserver.p12 \
  -name "myserver" \
  -password pass:changeit

# keytool로 확인
keytool -list -keystore server-certs/myserver.p12 -storepass changeit
```

## 6.3 Java에서 테스트

```bash
cd /workspace/java-app

# 우리가 만든 PKI로 연결 테스트 (로컬 테스트)
# 실제로는 서버를 띄워야 하지만, 인증서 체인 검증만 테스트

cat << 'EOF' > PKIChainTest.java
import java.io.*;
import java.security.*;
import java.security.cert.*;
import java.util.*;

public class PKIChainTest {
    public static void main(String[] args) throws Exception {
        System.out.println("🔐 PKI Certificate Chain Validation");
        System.out.println("════════════════════════════════════════════════");
        
        // 1. Root CA 로드
        CertificateFactory cf = CertificateFactory.getInstance("X.509");
        
        X509Certificate rootCert;
        try (FileInputStream fis = new FileInputStream(
                "/workspace/certs/pki/root-ca/certs/root-ca.crt")) {
            rootCert = (X509Certificate) cf.generateCertificate(fis);
        }
        System.out.println("✅ Root CA loaded: " + rootCert.getSubjectX500Principal());
        
        // 2. Intermediate CA 로드
        X509Certificate intCert;
        try (FileInputStream fis = new FileInputStream(
                "/workspace/certs/pki/intermediate-ca/certs/intermediate-ca.crt")) {
            intCert = (X509Certificate) cf.generateCertificate(fis);
        }
        System.out.println("✅ Intermediate CA loaded: " + intCert.getSubjectX500Principal());
        
        // 3. Server 인증서 로드
        X509Certificate serverCert;
        try (FileInputStream fis = new FileInputStream(
                "/workspace/certs/pki/server-certs/myserver.crt")) {
            serverCert = (X509Certificate) cf.generateCertificate(fis);
        }
        System.out.println("✅ Server cert loaded: " + serverCert.getSubjectX500Principal());
        
        // 4. 체인 검증
        System.out.println("\n📋 Validating certificate chain...");
        
        // TrustAnchor 설정 (Root CA)
        Set<TrustAnchor> trustAnchors = new HashSet<>();
        trustAnchors.add(new TrustAnchor(rootCert, null));
        
        // 인증서 체인 생성
        List<X509Certificate> certChain = Arrays.asList(serverCert, intCert);
        CertPath certPath = cf.generateCertPath(certChain);
        
        // 검증 파라미터
        PKIXParameters params = new PKIXParameters(trustAnchors);
        params.setRevocationEnabled(false); // CRL 체크 비활성화 (실습용)
        
        // 검증 실행
        CertPathValidator validator = CertPathValidator.getInstance("PKIX");
        try {
            PKIXCertPathValidatorResult result = 
                (PKIXCertPathValidatorResult) validator.validate(certPath, params);
            
            System.out.println("\n✅ Certificate chain is VALID!");
            System.out.println("   Trust Anchor: " + result.getTrustAnchor().getTrustedCert().getSubjectX500Principal());
            System.out.println("   Public Key: " + result.getPublicKey().getAlgorithm());
            
        } catch (CertPathValidatorException e) {
            System.out.println("\n❌ Certificate chain validation FAILED!");
            System.out.println("   Error: " + e.getMessage());
            System.out.println("   Index: " + e.getIndex());
        }
    }
}
EOF

javac PKIChainTest.java
java PKIChainTest
```

### 예상 출력
```
🔐 PKI Certificate Chain Validation
════════════════════════════════════════════════
✅ Root CA loaded: CN=Lab Root CA, OU=PKI Department, O=TLS Practice Lab, ...
✅ Intermediate CA loaded: CN=Lab Intermediate CA, OU=PKI Department, ...
✅ Server cert loaded: CN=myserver.lab.local, OU=Web Services, ...

📋 Validating certificate chain...

✅ Certificate chain is VALID!
   Trust Anchor: CN=Lab Root CA, OU=PKI Department, O=TLS Practice Lab, ...
   Public Key: RSA
```

---

# Part 7: cert-manager 자동화

## 7.1 cert-manager의 역할

```
┌─────────────────────────────────────────────────────────────────┐
│                  cert-manager 자동화                            │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  기존 수동 방식:                                                 │
│  개발자 → openssl로 키 생성 → CSR 생성 → CA에 제출 →            │
│        → 인증서 수령 → 서버 설정 → 갱신 캘린더 등록...           │
│                                                                 │
│  cert-manager 방식:                                             │
│  ┌──────────────┐      ┌──────────────┐      ┌──────────────┐  │
│  │  Certificate │ ──>  │ cert-manager │ ──>  │   Secret     │  │
│  │   (CR 정의)  │      │   (자동화)   │      │ (인증서 저장)│  │
│  └──────────────┘      └──────────────┘      └──────────────┘  │
│                              │                                  │
│                              ▼                                  │
│                    ┌──────────────────┐                        │
│                    │ 자동 갱신 (만료 전)│                        │
│                    │ 자동 재발급       │                        │
│                    └──────────────────┘                        │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

## 7.2 cert-manager 구성 요소

### Issuer / ClusterIssuer
```yaml
# 네임스페이스 범위 Issuer
apiVersion: cert-manager.io/v1
kind: Issuer
metadata:
  name: my-ca-issuer
  namespace: default
spec:
  ca:
    secretName: my-ca-secret  # CA 인증서/키가 담긴 Secret

# 클러스터 범위 ClusterIssuer
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: admin@example.com
    privateKeySecretRef:
      name: letsencrypt-account-key
    solvers:
    - http01:
        ingress:
          class: nginx
```

### Certificate
```yaml
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: myapp-cert
  namespace: default
spec:
  secretName: myapp-tls-secret  # 생성될 Secret 이름
  duration: 2160h              # 90일
  renewBefore: 360h            # 15일 전 갱신
  commonName: myapp.example.com
  dnsNames:
  - myapp.example.com
  - www.myapp.example.com
  issuerRef:
    name: my-ca-issuer
    kind: Issuer
```

## 7.3 우리 환경의 cert-manager 확인

```bash
# cert-manager가 생성한 인증서 확인
kubectl get certificates -n tls-lab

# 인증서 상세 정보
kubectl describe certificate tls-server-cert -n tls-lab

# Secret 확인
kubectl get secret tls-server-secret -n tls-lab -o yaml
```

---

# Part 8: 핵심 개념 정리

## 8.1 PKI 계층 구조

```
Root CA (10년)
├── Intermediate CA #1 (5년)
│   ├── Server Cert A (1년)
│   ├── Server Cert B (1년)
│   └── Client Cert X (1년)
└── Intermediate CA #2 (5년)
    ├── Server Cert C (1년)
    └── Server Cert D (1년)
```

## 8.2 인증서 유형별 유효기간 권장

| 유형 | 권장 유효기간 | 이유 |
|------|-------------|------|
| Root CA | 10-25년 | 오프라인 보관, 변경 어려움 |
| Intermediate CA | 3-10년 | Root보다 짧게 |
| Server Cert | 90일-2년 | 자동 갱신 권장 |
| Client Cert | 1-2년 | 사용자/기기 수명 |

## 8.3 실무 베스트 프랙티스

### DO ✅
- Root CA 개인키는 오프라인/HSM 보관
- Intermediate CA로 실제 인증서 발급
- 인증서 자동 갱신 설정 (cert-manager)
- CRL/OCSP 체계 구축
- 인증서 인벤토리 관리

### DON'T ❌
- Root CA 개인키 온라인 노출
- Root CA로 직접 서버 인증서 발급
- 수동 인증서 갱신에 의존
- 폐기 체계 없이 운영
- 만료된 인증서 방치

---

# 📝 실습 체크리스트

- [ ] PKI 구조와 역할 이해
- [ ] Root CA 생성 (4096bit, 자체서명)
- [ ] Intermediate CA 생성 (Root가 서명)
- [ ] 서버 인증서 발급 (SAN 포함)
- [ ] 인증서 체인 검증
- [ ] 인증서 폐기 및 CRL 생성
- [ ] Java에서 체인 검증
- [ ] cert-manager 자동화 이해

---

# 🎉 축하합니다!

모든 LAB을 완료했습니다! 이제 다음을 할 수 있습니다:

1. ✅ TLS/SSL의 동작 원리 설명
2. ✅ 인증서 체인 구조 이해 및 분석
3. ✅ Java에서 TLS 연결 구현 및 디버깅
4. ✅ mTLS 환경 구축
5. ✅ 인증서 문제 트러블슈팅
6. ✅ 자체 PKI 구축 및 관리

## 다음 단계 추천
- Istio/Linkerd의 mTLS 자동화 학습
- Let's Encrypt ACME 프로토콜 심화
- HashiCorp Vault PKI 엔진 활용
- 쿠버네티스 Certificate API 활용
