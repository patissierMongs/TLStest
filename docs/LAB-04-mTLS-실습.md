# LAB 04: mTLS (상호 인증) 구현

## 🎯 학습 목표
- mTLS의 개념과 일반 TLS와의 차이 이해
- 클라이언트 인증서 생성 및 관리
- KeyStore와 TrustStore 동시 사용
- Java에서 mTLS 클라이언트 구현

## 📚 예상 소요 시간: 2시간

## 📋 사전 요구사항
- LAB-01 ~ LAB-03 완료
- Java 실습 Pod 접속 상태

---

# Part 1: mTLS 이론

## 1.1 TLS vs mTLS

### 일반 TLS (단방향 인증)

```
┌──────────────────────────────────────────────────────────────────┐
│                      일반 TLS                                    │
├──────────────────────────────────────────────────────────────────┤
│                                                                  │
│  클라이언트                              서버                     │
│  (브라우저)                             (웹서버)                  │
│      │                                     │                     │
│      │  1. "안녕, 나는 클라이언트야"         │                     │
│      │─────────────────────────────────────>│                     │
│      │                                     │                     │
│      │  2. "안녕, 내 인증서야. 난 진짜 서버야" │                     │
│      │<─────────────────────────────────────│                     │
│      │     [서버 인증서]                     │                     │
│      │                                     │                     │
│      │  3. 클라이언트가 서버 인증서 검증      │                     │
│      │     "Root CA가 서명했네? OK!"        │                     │
│      │                                     │                     │
│      │  4. 암호화 통신 시작                  │                     │
│      │<════════════════════════════════════>│                     │
│                                                                  │
│  ✓ 서버가 누구인지 확인됨                                         │
│  ✗ 클라이언트가 누구인지 서버는 모름                               │
│    (ID/PW, 토큰 등으로 별도 인증 필요)                            │
│                                                                  │
└──────────────────────────────────────────────────────────────────┘
```

### mTLS (양방향/상호 인증)

```
┌──────────────────────────────────────────────────────────────────┐
│                      mTLS (Mutual TLS)                           │
├──────────────────────────────────────────────────────────────────┤
│                                                                  │
│  클라이언트                              서버                     │
│  (서비스 A)                            (서비스 B)                 │
│      │                                     │                     │
│      │  1. "안녕, 나는 클라이언트야"         │                     │
│      │─────────────────────────────────────>│                     │
│      │                                     │                     │
│      │  2. "안녕, 내 인증서야"               │                     │
│      │<─────────────────────────────────────│                     │
│      │     [서버 인증서]                     │                     │
│      │                                     │                     │
│      │  3. "클라이언트 인증서도 보내줘" ★    │                     │
│      │<─────────────────────────────────────│                     │
│      │                                     │                     │
│      │  4. "여기 내 인증서야" ★              │                     │
│      │─────────────────────────────────────>│                     │
│      │     [클라이언트 인증서]               │                     │
│      │                                     │                     │
│      │  5. 양쪽 모두 상대방 인증서 검증       │                     │
│      │                                     │                     │
│      │  6. 암호화 통신 시작                  │                     │
│      │<════════════════════════════════════>│                     │
│                                                                  │
│  ✓ 서버가 누구인지 확인됨                                         │
│  ✓ 클라이언트가 누구인지도 확인됨 (인증서로!)                      │
│                                                                  │
└──────────────────────────────────────────────────────────────────┘
```

## 1.2 mTLS 사용 사례

### 마이크로서비스 통신 (Service Mesh)

```
┌─────────────────────────────────────────────────────────────────┐
│                    Kubernetes Cluster                           │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌─────────────┐    mTLS    ┌─────────────┐    mTLS    ┌─────┐│
│  │ Order       │<─────────>│ Payment     │<─────────>│ Bank ││
│  │ Service     │           │ Service     │           │ API  ││
│  └─────────────┘           └─────────────┘           └─────┘│
│         │                                                     │
│         │ mTLS                                                │
│         ▼                                                     │
│  ┌─────────────┐                                              │
│  │ Inventory   │   Istio/Linkerd가 자동으로 mTLS 처리         │
│  │ Service     │                                              │
│  └─────────────┘                                              │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### API 게이트웨이 인증

```
┌─────────────────────────────────────────────────────────────────┐
│                    Partner API 접근                             │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  우리 회사                              파트너 회사             │
│  ┌──────────┐                         ┌──────────┐            │
│  │ 우리     │      mTLS + API Key     │ 파트너   │            │
│  │ 서버     │ ───────────────────────>│ API      │            │
│  │          │  [클라이언트 인증서]      │          │            │
│  └──────────┘                         └──────────┘            │
│                                                                 │
│  파트너가 우리에게 클라이언트 인증서 발급                        │
│  → 우리만 API 호출 가능                                        │
│  → IP 화이트리스트보다 안전                                     │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### IoT 디바이스 인증

```
┌─────────────────────────────────────────────────────────────────┐
│                    IoT 환경                                     │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌────────┐ ┌────────┐ ┌────────┐                              │
│  │센서 A  │ │센서 B  │ │센서 C  │  각 디바이스에 고유 인증서     │
│  │[인증서]│ │[인증서]│ │[인증서]│                               │
│  └───┬────┘ └───┬────┘ └───┬────┘                              │
│      │          │          │                                   │
│      └──────────┼──────────┘                                   │
│                 │ mTLS                                         │
│                 ▼                                              │
│          ┌──────────────┐                                      │
│          │  IoT 서버    │  서버가 각 디바이스 식별 가능         │
│          │ [CA 인증서]  │  위조된 디바이스 접근 차단            │
│          └──────────────┘                                      │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

## 1.3 mTLS의 장단점

### 장점 ✅
| 장점 | 설명 |
|------|------|
| 강력한 인증 | 인증서 기반 - 탈취 어려움 |
| 상호 신뢰 | 양측 모두 검증됨 |
| 비밀번호 불필요 | 인증서가 대신 |
| 자동 갱신 가능 | cert-manager 등 활용 |
| 감사 추적 | 인증서로 클라이언트 식별 |

### 단점 ❌
| 단점 | 설명 |
|------|------|
| 복잡성 | 인증서 관리 필요 |
| 인증서 배포 | 클라이언트에 인증서 전달 필요 |
| 갱신 관리 | 만료 전 갱신 필수 |
| 디버깅 어려움 | 문제 발생 시 원인 파악 복잡 |

---

# Part 2: 실습 환경 준비

## 2.1 mTLS 서버 확인

우리가 배포한 NGINX에는 이미 mTLS 포트(8443)가 구성되어 있습니다.

```bash
# mTLS 서버 설정 확인 (kubectl이 있다면)
# NGINX 설정에서 ssl_verify_client on; 확인

# mTLS 포트 테스트 (클라이언트 인증서 없이)
curl -k https://tls-server.tls-lab.svc.cluster.local:8443

# 출력:
# <html>
# <head><title>400 No required SSL certificate was sent</title></head>
# 클라이언트 인증서 필요!
```

## 2.2 현재 상태 확인

```bash
# 일반 TLS 포트(443)는 클라이언트 인증서 없이 접속 가능
curl -k https://tls-server.tls-lab.svc.cluster.local:443
# {"status":"ok","message":"TLS connection successful",...}

# mTLS 포트(8443)는 클라이언트 인증서 필수
curl -k https://tls-server.tls-lab.svc.cluster.local:8443
# 400 에러 - 클라이언트 인증서 필요
```

---

# Part 3: 클라이언트 인증서 생성

## 3.1 인증서 파일 가져오기

cert-manager가 생성한 클라이언트 인증서를 사용합니다.

```bash
cd /workspace/certs

# 클라이언트 인증서와 키 확인
# (cert-manager가 tls-client-secret에 생성)

# 클라이언트 인증서 추출 (Pod 내부에서)
# Kubernetes API를 직접 호출하거나, 마운트된 경로 사용

# 테스트를 위해 직접 생성해봅시다
mkdir -p /workspace/certs/client
cd /workspace/certs/client
```

## 3.2 클라이언트 인증서 직접 생성

실습을 위해 OpenSSL로 직접 클라이언트 인증서를 생성합니다.

### Step 1: 클라이언트 개인키 생성

```bash
# RSA 2048비트 개인키 생성
openssl genrsa -out client.key 2048

# 키 확인
openssl rsa -in client.key -check
# RSA key ok
```

### Step 2: CSR(Certificate Signing Request) 생성

```bash
# 클라이언트 인증서 요청서 생성
openssl req -new \
  -key client.key \
  -out client.csr \
  -subj "/CN=java-tls-lab-client/O=TLS Lab/OU=Development"

# CSR 내용 확인
openssl req -in client.csr -noout -text | head -20
```

### Step 3: 내부 CA로 클라이언트 인증서 서명

```bash
# 먼저 CA 인증서와 키 가져오기
# (서버에서 추출한 CA 사용)
cp /workspace/certs/tls-server.tls-lab.svc.cluster.local/tls-server.tls-lab.svc.cluster.local-1.crt ./ca.crt

# CA 개인키는 Kubernetes Secret에 있으므로, 
# 실습을 위해 새로운 CA를 생성합니다

# 실습용 CA 키 생성
openssl genrsa -out ca.key 4096

# 실습용 CA 인증서 생성 (Self-Signed)
openssl req -x509 -new -nodes \
  -key ca.key \
  -sha256 \
  -days 365 \
  -out ca.crt \
  -subj "/CN=Lab-CA/O=TLS Practice Lab"

# CA로 클라이언트 인증서 서명
openssl x509 -req \
  -in client.csr \
  -CA ca.crt \
  -CAkey ca.key \
  -CAcreateserial \
  -out client.crt \
  -days 90 \
  -sha256

# 생성된 파일 확인
ls -la
# ca.crt      - CA 인증서
# ca.key      - CA 개인키
# client.crt  - 클라이언트 인증서
# client.key  - 클라이언트 개인키
# client.csr  - CSR (더 이상 필요 없음)
```

### Step 4: 클라이언트 인증서 확인

```bash
# 클라이언트 인증서 정보 확인
openssl x509 -in client.crt -noout -text | head -25

# 발급자와 주체 확인
openssl x509 -in client.crt -noout -subject -issuer
# subject=CN = java-tls-lab-client, O = TLS Lab, OU = Development
# issuer=CN = Lab-CA, O = TLS Practice Lab
```

## 3.3 PKCS12 (PFX) 형식 변환

Java는 KeyStore 형식이 필요하므로 PKCS12로 변환합니다.

```bash
# 개인키와 인증서를 PKCS12로 묶기
openssl pkcs12 -export \
  -in client.crt \
  -inkey client.key \
  -certfile ca.crt \
  -out client.p12 \
  -name "client-cert" \
  -password pass:changeit

# PKCS12 파일 확인
openssl pkcs12 -in client.p12 -info -password pass:changeit -noout
```

### 출력 예시
```
MAC: sha256, Iteration 2048
MAC length: 32, salt length: 8
PKCS7 Encrypted data: PBES2, PBKDF2, AES-256-CBC, Iteration 2048, PRF hmacWithSHA256
Certificate bag
PKCS7 Data
Shrouded Keybag: PBES2, PBKDF2, AES-256-CBC, Iteration 2048, PRF hmacWithSHA256
```

## 3.4 Java KeyStore 확인

keytool로도 PKCS12 파일을 확인할 수 있습니다.

```bash
keytool -list -keystore client.p12 -storepass changeit

# 출력:
# Keystore type: PKCS12
# ...
# client-cert, Jan 15, 2025, PrivateKeyEntry,
```

---

# Part 4: mTLS 서버 설정 (NGINX)

## 4.1 현재 서버 설정 이해

우리가 배포한 NGINX의 mTLS 설정을 확인합니다:

```nginx
# 8443 포트 - mTLS 활성화
server {
    listen 8443 ssl;
    
    ssl_certificate /etc/nginx/ssl/tls.crt;
    ssl_certificate_key /etc/nginx/ssl/tls.key;
    
    # 클라이언트 인증서 검증 설정
    ssl_client_certificate /etc/nginx/ssl/ca.crt;  # 클라이언트 CA
    ssl_verify_client on;                          # 클라이언트 인증 필수
    
    location / {
        return 200 '{"client_dn":"$ssl_client_s_dn"}';
    }
}
```

### 주요 설정 설명
| 설정 | 설명 |
|------|------|
| `ssl_client_certificate` | 클라이언트 인증서를 검증할 CA |
| `ssl_verify_client on` | 클라이언트 인증서 필수 |
| `ssl_verify_client optional` | 선택적 (있으면 검증) |
| `$ssl_client_s_dn` | 검증된 클라이언트 DN |

## 4.2 테스트용 mTLS 서버 구성

Pod 내부에서 간단한 mTLS 테스트를 위해 Python으로 테스트 서버를 만듭니다.

```bash
# Python SSL 테스트 서버 (옵션)
cat << 'EOF' > /workspace/scripts/mtls-server.py
import ssl
import http.server
import socketserver

PORT = 9443

class MyHandler(http.server.SimpleHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.send_header('Content-type', 'application/json')
        self.end_headers()
        
        # 클라이언트 인증서 정보
        cert = self.connection.getpeercert()
        if cert:
            subject = dict(x[0] for x in cert['subject'])
            response = f'{{"status":"ok","client_cn":"{subject.get("commonName", "unknown")}"}}'
        else:
            response = '{"status":"ok","client":"anonymous"}'
        
        self.wfile.write(response.encode())

context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
context.load_cert_chain('/workspace/certs/client/ca.crt', '/workspace/certs/client/ca.key')
context.load_verify_locations('/workspace/certs/client/ca.crt')
context.verify_mode = ssl.CERT_REQUIRED  # mTLS 활성화

with socketserver.TCPServer(("", PORT), MyHandler) as httpd:
    httpd.socket = context.wrap_socket(httpd.socket, server_side=True)
    print(f"mTLS Server running on port {PORT}")
    httpd.serve_forever()
EOF
```

---

# Part 5: curl로 mTLS 테스트

## 5.1 클라이언트 인증서 없이 (실패)

```bash
curl -k https://tls-server.tls-lab.svc.cluster.local:8443

# 출력:
# <html>
# <head><title>400 No required SSL certificate was sent</title></head>
# <body>
# <center><h1>400 Bad Request</h1></center>
# <center>No required SSL certificate was sent</center>
# </body>
# </html>
```

## 5.2 클라이언트 인증서로 접속 (성공)

```bash
cd /workspace/certs/client

# 클라이언트 인증서와 키로 접속
curl -k \
  --cert client.crt \
  --key client.key \
  https://tls-server.tls-lab.svc.cluster.local:8443
```

### 예상 출력
```json
{"status":"ok","message":"mTLS connection successful","client_dn":"CN=java-tls-lab-client,O=TLS Lab,OU=Development","client_verify":"SUCCESS"}
```

🎉 mTLS 성공! 서버가 클라이언트를 인증했습니다.

## 5.3 상세 디버그

```bash
curl -v -k \
  --cert client.crt \
  --key client.key \
  https://tls-server.tls-lab.svc.cluster.local:8443 2>&1 | grep -E "(SSL|subject|issuer)"
```

### 출력 분석
```
* SSL connection using TLSv1.3 / TLS_AES_256_GCM_SHA384
* Server certificate:
*  subject: CN=tls-server.tls-lab.svc.cluster.local
*  issuer: CN=tls-lab-ca
* Client certificate:
*  subject: CN=java-tls-lab-client; O=TLS Lab; OU=Development
*  issuer: CN=Lab-CA; O=TLS Practice Lab
```

---

# Part 6: Java에서 mTLS 구현

## 6.1 Java mTLS 클라이언트 작성

```bash
cat << 'EOF' > /workspace/java-app/MTLSClient.java
import javax.net.ssl.*;
import java.io.*;
import java.net.*;
import java.security.*;
import java.security.cert.*;

public class MTLSClient {
    public static void main(String[] args) throws Exception {
        if (args.length < 1) {
            System.out.println("Usage: java MTLSClient <url>");
            System.out.println("Required properties:");
            System.out.println("  -Djavax.net.ssl.keyStore=<client.p12>");
            System.out.println("  -Djavax.net.ssl.keyStorePassword=<password>");
            System.out.println("  -Djavax.net.ssl.trustStore=<truststore>");
            System.out.println("  -Djavax.net.ssl.trustStorePassword=<password>");
            System.exit(1);
        }
        
        String urlStr = args[0];
        System.out.println("🔐 mTLS Connection Test");
        System.out.println("═".repeat(60));
        System.out.println("URL: " + urlStr);
        
        // KeyStore (클라이언트 인증서) 로드
        String keyStorePath = System.getProperty("javax.net.ssl.keyStore");
        String keyStorePassword = System.getProperty("javax.net.ssl.keyStorePassword", "changeit");
        
        if (keyStorePath != null) {
            System.out.println("KeyStore: " + keyStorePath);
        } else {
            System.out.println("⚠️ Warning: No KeyStore specified (client cert)");
        }
        
        // TrustStore 확인
        String trustStorePath = System.getProperty("javax.net.ssl.trustStore");
        if (trustStorePath != null) {
            System.out.println("TrustStore: " + trustStorePath);
        } else {
            System.out.println("TrustStore: (default cacerts)");
        }
        
        System.out.println("─".repeat(60));
        
        try {
            // SSL Context 설정
            SSLContext sslContext = SSLContext.getInstance("TLS");
            
            // KeyManager (클라이언트 인증서용)
            KeyManager[] keyManagers = null;
            if (keyStorePath != null) {
                KeyStore keyStore = KeyStore.getInstance("PKCS12");
                try (FileInputStream fis = new FileInputStream(keyStorePath)) {
                    keyStore.load(fis, keyStorePassword.toCharArray());
                }
                
                KeyManagerFactory kmf = KeyManagerFactory.getInstance(
                    KeyManagerFactory.getDefaultAlgorithm());
                kmf.init(keyStore, keyStorePassword.toCharArray());
                keyManagers = kmf.getKeyManagers();
                
                // 클라이언트 인증서 정보 출력
                System.out.println("\n📜 Client Certificate:");
                java.util.Enumeration<String> aliases = keyStore.aliases();
                while (aliases.hasMoreElements()) {
                    String alias = aliases.nextElement();
                    if (keyStore.isKeyEntry(alias)) {
                        X509Certificate cert = (X509Certificate) keyStore.getCertificate(alias);
                        System.out.println("   Alias: " + alias);
                        System.out.println("   Subject: " + cert.getSubjectX500Principal());
                        System.out.println("   Issuer: " + cert.getIssuerX500Principal());
                        System.out.println("   Valid: " + cert.getNotBefore() + " ~ " + cert.getNotAfter());
                    }
                }
            }
            
            // TrustManager
            TrustManager[] trustManagers = null;
            if (trustStorePath != null) {
                KeyStore trustStore = KeyStore.getInstance(KeyStore.getDefaultType());
                try (FileInputStream fis = new FileInputStream(trustStorePath)) {
                    String trustStorePassword = System.getProperty(
                        "javax.net.ssl.trustStorePassword", "changeit");
                    trustStore.load(fis, trustStorePassword.toCharArray());
                }
                
                TrustManagerFactory tmf = TrustManagerFactory.getInstance(
                    TrustManagerFactory.getDefaultAlgorithm());
                tmf.init(trustStore);
                trustManagers = tmf.getTrustManagers();
            }
            
            sslContext.init(keyManagers, trustManagers, new java.security.SecureRandom());
            
            // HTTPS 연결
            URL url = new URL(urlStr);
            HttpsURLConnection conn = (HttpsURLConnection) url.openConnection();
            conn.setSSLSocketFactory(sslContext.getSocketFactory());
            conn.setConnectTimeout(10000);
            conn.setReadTimeout(10000);
            
            // 연결
            conn.connect();
            
            // 서버 인증서 정보
            SSLSession session = conn.getSSLSession().orElse(null);
            if (session != null) {
                System.out.println("\n✅ mTLS Connection Successful!");
                System.out.println("─".repeat(60));
                System.out.println("Protocol: " + session.getProtocol());
                System.out.println("Cipher: " + session.getCipherSuite());
                
                Certificate[] serverCerts = session.getPeerCertificates();
                System.out.println("\n📜 Server Certificate:");
                if (serverCerts.length > 0 && serverCerts[0] instanceof X509Certificate) {
                    X509Certificate serverCert = (X509Certificate) serverCerts[0];
                    System.out.println("   Subject: " + serverCert.getSubjectX500Principal());
                    System.out.println("   Issuer: " + serverCert.getIssuerX500Principal());
                }
            }
            
            // 응답 읽기
            int responseCode = conn.getResponseCode();
            System.out.println("\n📡 HTTP Response: " + responseCode);
            
            if (responseCode == 200) {
                BufferedReader reader = new BufferedReader(
                    new InputStreamReader(conn.getInputStream()));
                String line;
                StringBuilder response = new StringBuilder();
                while ((line = reader.readLine()) != null) {
                    response.append(line);
                }
                reader.close();
                System.out.println("Response: " + response.toString());
            }
            
            conn.disconnect();
            System.out.println("\n✅ mTLS test completed successfully!");
            
        } catch (SSLHandshakeException e) {
            System.err.println("\n❌ SSL Handshake Failed!");
            System.err.println("─".repeat(60));
            System.err.println("Error: " + e.getMessage());
            
            Throwable cause = e.getCause();
            while (cause != null) {
                System.err.println("Caused by: " + cause.getMessage());
                cause = cause.getCause();
            }
            
            System.err.println("\n💡 Possible causes:");
            System.err.println("   - Client certificate not provided");
            System.err.println("   - Client certificate not trusted by server");
            System.err.println("   - Server certificate not trusted by client");
            System.err.println("   - Certificate expired");
            
            System.exit(1);
        } catch (Exception e) {
            System.err.println("\n❌ Connection Failed: " + e.getMessage());
            e.printStackTrace();
            System.exit(1);
        }
    }
}
EOF
```

## 6.2 컴파일 및 실행

```bash
cd /workspace/java-app

# 컴파일
javac MTLSClient.java

# 실행 (mTLS)
java \
  -Djavax.net.ssl.keyStore=/workspace/certs/client/client.p12 \
  -Djavax.net.ssl.keyStorePassword=changeit \
  -Djavax.net.ssl.trustStore=/workspace/certs/test-cacerts \
  -Djavax.net.ssl.trustStorePassword=changeit \
  MTLSClient https://tls-server.tls-lab.svc.cluster.local:8443
```

### 예상 출력
```
🔐 mTLS Connection Test
════════════════════════════════════════════════════════════
URL: https://tls-server.tls-lab.svc.cluster.local:8443
KeyStore: /workspace/certs/client/client.p12
TrustStore: /workspace/certs/test-cacerts
────────────────────────────────────────────────────────────

📜 Client Certificate:
   Alias: client-cert
   Subject: CN=java-tls-lab-client, O=TLS Lab, OU=Development
   Issuer: CN=Lab-CA, O=TLS Practice Lab
   Valid: Wed Jan 15 ... ~ Tue Apr 15 ...

✅ mTLS Connection Successful!
────────────────────────────────────────────────────────────
Protocol: TLSv1.3
Cipher: TLS_AES_256_GCM_SHA384

📜 Server Certificate:
   Subject: CN=tls-server.tls-lab.svc.cluster.local
   Issuer: CN=tls-lab-ca

📡 HTTP Response: 200
Response: {"status":"ok","message":"mTLS connection successful","client_dn":"CN=java-tls-lab-client,O=TLS Lab,OU=Development"}

✅ mTLS test completed successfully!
```

## 6.3 KeyStore 없이 실행 (실패 예상)

```bash
# 클라이언트 인증서 없이 mTLS 서버 접속
java \
  -Djavax.net.ssl.trustStore=/workspace/certs/test-cacerts \
  -Djavax.net.ssl.trustStorePassword=changeit \
  MTLSClient https://tls-server.tls-lab.svc.cluster.local:8443
```

### 예상 출력
```
⚠️ Warning: No KeyStore specified (client cert)

❌ SSL Handshake Failed!
Error: Received fatal alert: bad_certificate
```

서버가 클라이언트 인증서를 요구했지만 제공하지 않아서 실패합니다.

---

# Part 7: mTLS 디버깅

## 7.1 상세 로그 활성화

```bash
# SSL 핸드셰이크 전체 로그
java \
  -Djavax.net.debug=ssl:handshake \
  -Djavax.net.ssl.keyStore=/workspace/certs/client/client.p12 \
  -Djavax.net.ssl.keyStorePassword=changeit \
  -Djavax.net.ssl.trustStore=/workspace/certs/test-cacerts \
  -Djavax.net.ssl.trustStorePassword=changeit \
  MTLSClient https://tls-server.tls-lab.svc.cluster.local:8443 2>&1 | head -100
```

### 핵심 로그 포인트

```
# 1. 클라이언트가 지원하는 인증서 타입
"CertificateRequest": {
  "certificate types": [rsa_sign, ecdsa_sign, ...]
  "supported signature algorithms": [...]
  "certificate authorities": [...]    ← 서버가 원하는 CA
}

# 2. 클라이언트가 인증서 전송
"Certificate": {
  "certificates": [{
    "certificate": {
      "subject": "CN=java-tls-lab-client, O=TLS Lab, OU=Development"
    }
  }]
}

# 3. 클라이언트가 개인키로 서명 증명
"CertificateVerify": {
  "signature algorithm": rsa_pss_rsae_sha256
}
```

## 7.2 일반적인 mTLS 에러와 해결

### 에러 1: "bad_certificate"
```
원인: 클라이언트 인증서가 없거나 형식이 잘못됨
해결: 
  - KeyStore 경로 확인
  - 인증서에 개인키가 포함되어 있는지 확인
  - PKCS12 형식 확인
```

### 에러 2: "certificate_unknown"
```
원인: 서버가 클라이언트 CA를 신뢰하지 않음
해결:
  - 서버의 ssl_client_certificate에 클라이언트 CA 추가
  - 클라이언트 인증서가 올바른 CA로 서명되었는지 확인
```

### 에러 3: "certificate_expired"
```
원인: 클라이언트 또는 서버 인증서 만료
해결:
  - openssl x509 -noout -dates로 유효기간 확인
  - 새 인증서 발급
```

---

# Part 8: 핵심 개념 정리

## 8.1 mTLS에 필요한 파일

### 클라이언트 측
| 파일 | 용도 | Java 설정 |
|------|------|-----------|
| client.p12 (KeyStore) | 클라이언트 인증서 + 개인키 | `javax.net.ssl.keyStore` |
| truststore | 서버 CA 인증서 | `javax.net.ssl.trustStore` |

### 서버 측
| 파일 | 용도 | NGINX 설정 |
|------|------|------------|
| server.crt | 서버 인증서 | `ssl_certificate` |
| server.key | 서버 개인키 | `ssl_certificate_key` |
| client-ca.crt | 클라이언트 CA | `ssl_client_certificate` |

## 8.2 설정 요약

```bash
# Java mTLS 클라이언트 실행
java \
  -Djavax.net.ssl.keyStore=<클라이언트.p12> \
  -Djavax.net.ssl.keyStorePassword=<비밀번호> \
  -Djavax.net.ssl.trustStore=<신뢰저장소> \
  -Djavax.net.ssl.trustStorePassword=<비밀번호> \
  MyApplication
```

## 8.3 실무 베스트 프랙티스

### DO ✅
- 인증서 자동 갱신 설정 (cert-manager)
- 인증서 만료 알림 설정
- 클라이언트 인증서는 서비스별로 개별 발급
- 인증서 폐기(Revocation) 체계 구축

### DON'T ❌
- 하나의 클라이언트 인증서를 여러 서비스에서 공유
- 개인키 하드코딩
- 인증서 만료 무시
- `-k` 옵션으로 운영 환경 접속

---

# 📝 실습 체크리스트

- [ ] mTLS와 일반 TLS의 차이 이해
- [ ] 클라이언트 개인키 생성
- [ ] CSR 생성 및 CA 서명
- [ ] PKCS12 형식 변환
- [ ] curl로 mTLS 테스트 성공
- [ ] Java mTLS 클라이언트 구현
- [ ] 인증서 없이 접속 시 에러 확인
- [ ] SSL 디버그 로그 분석

---

## 🔗 다음 실습
[LAB-05-트러블슈팅.md](./LAB-05-트러블슈팅.md)
