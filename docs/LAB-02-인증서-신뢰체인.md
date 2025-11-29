# LAB 02: 인증서 신뢰 체인 실습

## 🎯 학습 목표
- 테스트용 KeyStore를 생성하여 원본 cacerts 보호
- 루트 CA 추가를 통한 신뢰 체인 구축
- 인증서 추가 전/후 연결 차이 체험
- KeyStore 관리 명령어 숙달

## 📚 예상 소요 시간: 1시간

## 📋 사전 요구사항
- LAB-01 완료
- Java 실습 Pod 접속 상태

---

# Part 1: KeyStore 이론

## 1.1 KeyStore vs TrustStore

Java에서는 두 종류의 저장소를 구분합니다:

### KeyStore
- **목적**: 나의 개인키와 인증서 저장
- **용도**: 클라이언트 인증(mTLS), 서버 인증서 저장
- **비유**: 나의 신분증 + 도장

### TrustStore  
- **목적**: 신뢰할 수 있는 CA 인증서 저장
- **용도**: 상대방 인증서 검증
- **비유**: 신뢰할 수 있는 기관 목록

```
┌──────────────────────────────────────────────────────────────┐
│                    Java SSL/TLS                              │
├──────────────────────────────────────────────────────────────┤
│                                                              │
│  ┌─────────────┐              ┌─────────────┐               │
│  │  KeyStore   │              │ TrustStore  │               │
│  │             │              │  (cacerts)  │               │
│  │ - 내 개인키  │              │             │               │
│  │ - 내 인증서  │              │ - 신뢰할 CA │               │
│  │             │              │   인증서들   │               │
│  └──────┬──────┘              └──────┬──────┘               │
│         │                            │                       │
│         ▼                            ▼                       │
│  "나는 누구인가"               "상대방을 믿을 수 있나"         │
│  (클라이언트 인증 시)          (서버 인증서 검증 시)          │
│                                                              │
└──────────────────────────────────────────────────────────────┘
```

### 실무에서의 혼용
실제로 Java에서는 KeyStore와 TrustStore가 같은 파일 형식(JKS, PKCS12)을 사용합니다.
`cacerts`도 기술적으로는 KeyStore 파일이지만, CA 인증서만 담고 있어서 TrustStore로 사용됩니다.

## 1.2 KeyStore 파일 형식

### JKS (Java KeyStore)
- Java 전용 형식
- 확장자: `.jks`
- 레거시, 점점 사용 감소

### PKCS12
- 업계 표준 형식
- 확장자: `.p12`, `.pfx`
- Java 9부터 기본 형식
- OpenSSL 등 다른 도구와 호환

```bash
# 현재 cacerts 형식 확인
keytool -list -keystore $JAVA_HOME/lib/security/cacerts -storepass changeit | head -5

# 출력:
# Keystore type: PKCS12    ← Java 17+는 PKCS12가 기본
# Keystore provider: SUN
```

## 1.3 왜 테스트용 KeyStore를 만드는가?

### 원본 cacerts를 직접 수정하면 안 되는 이유

1. **시스템 전체 영향**
   - 같은 JVM을 사용하는 모든 애플리케이션에 영향
   
2. **복원 어려움**
   - 실수로 중요한 CA 삭제 시 복구 힘듦
   
3. **업그레이드 문제**
   - Java 업데이트 시 cacerts가 덮어씌워질 수 있음

4. **보안 감사**
   - 운영 환경에서 시스템 파일 변경은 감사 대상

### 올바른 방법: 복사본 사용

```
원본 cacerts (절대 수정 안 함)
       │
       │ 복사
       ▼
테스트용 cacerts (마음대로 수정)
       │
       │ -Djavax.net.ssl.trustStore=...
       ▼
특정 애플리케이션만 영향
```

---

# Part 2: 테스트용 TrustStore 생성

## 2.1 작업 디렉토리 준비

```bash
# Pod에 접속된 상태에서
cd /workspace/certs

# 현재 내용 확인
ls -la
# test-cacerts가 이미 있을 수 있음 (setup 스크립트가 생성)
```

## 2.2 원본 cacerts 복사

```bash
# 원본 cacerts를 테스트용으로 복사
cp $JAVA_HOME/lib/security/cacerts ./test-cacerts

# 권한 설정 (쓰기 가능하게)
chmod 644 ./test-cacerts

# 파일 확인
ls -la test-cacerts
# -rw-r--r-- 1 root root 123456 Jan 15 12:00 test-cacerts
```

## 2.3 복사본 내용 확인

```bash
# KeyStore 정보 확인
keytool -list -keystore ./test-cacerts -storepass changeit | head -10
```

### 출력 예시
```
Keystore type: PKCS12
Keystore provider: SUN

Your keystore contains 91 entries

affaboraborertrust, Jan 1, 2020, trustedCertEntry,
...
```

## 2.4 특정 CA 검색

```bash
# DigiCert 관련 CA 검색
keytool -list -keystore ./test-cacerts -storepass changeit | grep -i digicert

# Let's Encrypt 관련 CA 검색
keytool -list -keystore ./test-cacerts -storepass changeit | grep -i "let's\|isrg"

# Google Trust Services 검색
keytool -list -keystore ./test-cacerts -storepass changeit | grep -i "google\|gts"
```

---

# Part 3: 빈 TrustStore로 연결 실패 체험

## 3.1 빈 TrustStore 생성

모든 CA가 없는 완전히 빈 TrustStore를 만들어서, 
인증서 검증이 왜 실패하는지 명확하게 이해해봅시다.

```bash
cd /workspace/certs

# 빈 KeyStore 생성 (임시 키 생성 후 삭제하는 방식)
keytool -genkeypair \
  -alias temp \
  -keystore ./empty-cacerts \
  -storepass changeit \
  -keypass changeit \
  -dname "CN=temp" \
  -keyalg RSA \
  -validity 1

# 임시 키 삭제하여 완전히 비우기
keytool -delete \
  -alias temp \
  -keystore ./empty-cacerts \
  -storepass changeit

# 확인 (0개 항목)
keytool -list -keystore ./empty-cacerts -storepass changeit
```

### 출력
```
Keystore type: PKCS12
Keystore provider: SUN

Your keystore contains 0 entries
```

## 3.2 빈 TrustStore로 외부 사이트 연결

```bash
cd /workspace/java-app

# 빈 TrustStore 사용
java -Djavax.net.ssl.trustStore=/workspace/certs/empty-cacerts \
     -Djavax.net.ssl.trustStorePassword=changeit \
     TLSConnectionTest https://www.google.com
```

### 예상 출력
```
🔐 Testing TLS connection to: https://www.google.com
══════════════════════════════════════════════════

❌ SSL Handshake Failed!
──────────────────────────────────────────────────
Error: PKIX path building failed: 
  sun.security.provider.certpath.SunCertPathBuilderException: 
  unable to find valid certification path to requested target

💡 Possible causes:
   - Server certificate not trusted
   - Root CA not in truststore        ← 이것!
   - Certificate expired
   - Hostname mismatch
```

### 왜 실패했나?
- 빈 TrustStore에는 아무 CA도 없음
- Google의 Root CA도 없음
- → 인증서 체인 검증 불가능

## 3.3 빈 TrustStore로 내부 서버 연결

```bash
java -Djavax.net.ssl.trustStore=/workspace/certs/empty-cacerts \
     -Djavax.net.ssl.trustStorePassword=changeit \
     TLSConnectionTest https://tls-server.tls-lab.svc.cluster.local
```

당연히 실패합니다. 이제 CA를 하나씩 추가해보겠습니다.

---

# Part 4: 내부 CA 추가하기

## 4.1 내부 CA 인증서 가져오기

cert-manager가 생성한 내부 CA 인증서를 가져옵니다.

```bash
cd /workspace/certs

# Kubernetes Secret에서 CA 인증서 추출
# (Pod 내부에서는 kubectl이 없으므로, 미리 마운트된 경로나 openssl 사용)

# 방법 1: openssl로 서버에서 직접 추출
openssl s_client -connect tls-server.tls-lab.svc.cluster.local:443 \
  -showcerts </dev/null 2>/dev/null | \
  awk '/-----BEGIN CERTIFICATE-----/,/-----END CERTIFICATE-----/' | \
  tail -n +$(openssl s_client -connect tls-server.tls-lab.svc.cluster.local:443 \
    -showcerts </dev/null 2>/dev/null | \
    awk '/-----BEGIN CERTIFICATE-----/{start=NR} /-----END CERTIFICATE-----/{print start}' | tail -1)p \
  > internal-ca.crt 2>/dev/null

# 더 간단한 방법: 전체 체인에서 마지막(Root CA) 추출
openssl s_client -connect tls-server.tls-lab.svc.cluster.local:443 \
  -showcerts </dev/null 2>/dev/null | \
  awk '/-----BEGIN CERTIFICATE-----/{cert=""} {cert=cert$0"\n"} /-----END CERTIFICATE-----/{last=cert} END{print last}' \
  > internal-ca.crt
```

### 더 확실한 방법 (스크립트 사용)

```bash
# 인증서 체인 추출 스크립트 실행
/opt/scripts/extract-certs.sh tls-server.tls-lab.svc.cluster.local

# 결과 확인
ls -la /workspace/certs/tls-server.tls-lab.svc.cluster.local/
```

### 출력
```
📜 Extracted certificates:

📄 tls-server.tls-lab.svc.cluster.local-0.crt
   Subject: CN = tls-server.tls-lab.svc.cluster.local
   Issuer:  CN = tls-lab-ca

📄 tls-server.tls-lab.svc.cluster.local-1.crt
   Subject: CN = tls-lab-ca
   Issuer:  CN = tls-lab-ca      ← Self-Signed Root CA!
```

## 4.2 CA 인증서 정보 확인

```bash
# Root CA 인증서 상세 정보
openssl x509 -in /workspace/certs/tls-server.tls-lab.svc.cluster.local/tls-server.tls-lab.svc.cluster.local-1.crt \
  -noout -text | head -30
```

### 주요 확인 사항
```
Certificate:
    Data:
        Version: 3 (0x2)
        Issuer: CN = tls-lab-ca
        Validity
            Not Before: ...
            Not After : ...              ← 10년 유효
        Subject: CN = tls-lab-ca         ← Issuer와 동일 = Self-Signed
        X509v3 extensions:
            X509v3 Basic Constraints: critical
                CA:TRUE                  ← CA 인증서임을 표시
            X509v3 Key Usage: critical
                Certificate Sign, CRL Sign   ← 인증서 서명 권한
```

## 4.3 테스트용 TrustStore에 CA 추가

```bash
cd /workspace/certs

# 내부 CA를 테스트용 cacerts에 추가
keytool -importcert \
  -keystore ./test-cacerts \
  -storepass changeit \
  -alias "tls-lab-internal-ca" \
  -file ./tls-server.tls-lab.svc.cluster.local/tls-server.tls-lab.svc.cluster.local-1.crt \
  -noprompt

# 출력: Certificate was added to keystore
```

### 옵션 설명
| 옵션 | 설명 |
|------|------|
| `-keystore` | 대상 KeyStore 파일 |
| `-storepass` | KeyStore 비밀번호 |
| `-alias` | 인증서 식별자 (고유해야 함) |
| `-file` | 추가할 인증서 파일 |
| `-noprompt` | 신뢰 확인 질문 건너뛰기 |

## 4.4 추가 확인

```bash
# 추가된 CA 확인
keytool -list -keystore ./test-cacerts -storepass changeit | grep -i "tls-lab"

# 상세 정보 확인
keytool -list -v -keystore ./test-cacerts -storepass changeit \
  -alias "tls-lab-internal-ca"
```

### 출력 예시
```
Alias name: tls-lab-internal-ca
Creation date: Jan 15, 2025
Entry type: trustedCertEntry

Owner: CN=tls-lab-ca
Issuer: CN=tls-lab-ca
Serial number: ...
Valid from: ... until: ...
Certificate fingerprints:
         SHA1: AA:BB:CC:DD:...
         SHA256: 11:22:33:44:...
```

---

# Part 5: CA 추가 후 연결 테스트

## 5.1 내부 서버 연결 (성공 예상!)

```bash
cd /workspace/java-app

# 테스트용 TrustStore 사용
java -Djavax.net.ssl.trustStore=/workspace/certs/test-cacerts \
     -Djavax.net.ssl.trustStorePassword=changeit \
     TLSConnectionTest https://tls-server.tls-lab.svc.cluster.local
```

### 예상 출력
```
🔐 Testing TLS connection to: https://tls-server.tls-lab.svc.cluster.local
══════════════════════════════════════════════════

✅ TLS Connection Successful!
──────────────────────────────────────────────────
Protocol:     TLSv1.3
Cipher Suite: TLS_AES_256_GCM_SHA384
Peer Host:    tls-server.tls-lab.svc.cluster.local

📜 Certificate Chain (2 certs):
──────────────────────────────────────────────────

[0] Server Certificate:
    Subject: CN=tls-server.tls-lab.svc.cluster.local
    Issuer:  CN=tls-lab-ca
    Valid:   ...

[1] Root CA Certificate:
    Subject: CN=tls-lab-ca
    Issuer:  CN=tls-lab-ca

📡 HTTP Response: 200
Response: {"status":"ok","message":"TLS connection successful",...}
✅ Test completed successfully!
```

### 🎉 성공! 왜 성공했나?

1. 서버가 인증서 체인을 보냄: `서버 인증서` + `tls-lab-ca`
2. Java가 서버 인증서 검증: `tls-lab-ca`가 서명함 ✓
3. `tls-lab-ca`가 test-cacerts에 있음 ✓
4. 체인 검증 성공 → 연결 성공!

## 5.2 외부 서버 연결 확인

테스트용 cacerts는 원본 cacerts를 복사했으므로, 외부 사이트도 여전히 연결됩니다.

```bash
java -Djavax.net.ssl.trustStore=/workspace/certs/test-cacerts \
     -Djavax.net.ssl.trustStorePassword=changeit \
     TLSConnectionTest https://www.google.com
```

외부 사이트도 정상 연결됩니다! 

## 5.3 비교 실험: 기본 cacerts vs 테스트 cacerts

```bash
# 기본 cacerts로 내부 서버 (실패)
java TLSConnectionTest https://tls-server.tls-lab.svc.cluster.local
# → PKIX path building failed

# 테스트 cacerts로 내부 서버 (성공)
java -Djavax.net.ssl.trustStore=/workspace/certs/test-cacerts \
     -Djavax.net.ssl.trustStorePassword=changeit \
     TLSConnectionTest https://tls-server.tls-lab.svc.cluster.local
# → TLS Connection Successful!
```

이 차이가 바로 TrustStore에 CA가 있고 없고의 차이입니다.

---

# Part 6: 심화 실험

## 6.1 서버 인증서만 추가하면? (실패)

Root CA 대신 서버 인증서만 추가하면 어떻게 될까요?

```bash
cd /workspace/certs

# 새로운 테스트용 KeyStore (빈 상태에서 시작)
cp ./empty-cacerts ./test-server-only

# 서버 인증서만 추가 (CA가 아님!)
keytool -importcert \
  -keystore ./test-server-only \
  -storepass changeit \
  -alias "tls-server-cert" \
  -file ./tls-server.tls-lab.svc.cluster.local/tls-server.tls-lab.svc.cluster.local-0.crt \
  -noprompt

# 테스트
java -Djavax.net.ssl.trustStore=/workspace/certs/test-server-only \
     -Djavax.net.ssl.trustStorePassword=changeit \
     TLSConnectionTest https://tls-server.tls-lab.svc.cluster.local
```

### 결과: 성공하기도 함!

Java는 TrustStore에 있는 인증서를 직접 신뢰하기도 합니다.
하지만 이 방식은 권장되지 않습니다:

- 서버 인증서가 갱신되면 매번 추가해야 함
- CA를 추가하면 그 CA가 발급한 모든 인증서를 자동 신뢰

## 6.2 인증서 수 비교

```bash
# 원본 cacerts의 CA 수
keytool -list -keystore $JAVA_HOME/lib/security/cacerts -storepass changeit 2>/dev/null | grep -c "trustedCertEntry"
# 약 90개

# 테스트 cacerts의 CA 수 (내부 CA 추가 후)
keytool -list -keystore ./test-cacerts -storepass changeit 2>/dev/null | grep -c "trustedCertEntry"
# 약 91개 (1개 추가됨)
```

## 6.3 CA 제거 실험

```bash
# 내부 CA 제거
keytool -delete \
  -keystore ./test-cacerts \
  -storepass changeit \
  -alias "tls-lab-internal-ca"

# 다시 연결 테스트 (실패 예상)
java -Djavax.net.ssl.trustStore=/workspace/certs/test-cacerts \
     -Djavax.net.ssl.trustStorePassword=changeit \
     TLSConnectionTest https://tls-server.tls-lab.svc.cluster.local
```

CA를 제거하면 다시 연결이 실패합니다!

```bash
# 다시 CA 추가 (복원)
keytool -importcert \
  -keystore ./test-cacerts \
  -storepass changeit \
  -alias "tls-lab-internal-ca" \
  -file ./tls-server.tls-lab.svc.cluster.local/tls-server.tls-lab.svc.cluster.local-1.crt \
  -noprompt
```

---

# Part 7: 핵심 개념 정리

## 7.1 KeyStore 관리 명령어 요약

| 작업 | 명령어 |
|------|--------|
| 목록 조회 | `keytool -list -keystore <ks> -storepass <pw>` |
| 상세 조회 | `keytool -list -v -keystore <ks> -alias <alias>` |
| 인증서 추가 | `keytool -importcert -keystore <ks> -alias <alias> -file <cert>` |
| 인증서 삭제 | `keytool -delete -keystore <ks> -alias <alias>` |
| 인증서 내보내기 | `keytool -exportcert -keystore <ks> -alias <alias> -file <out>` |
| 비밀번호 변경 | `keytool -storepasswd -keystore <ks>` |

## 7.2 TrustStore 설정 방법

### 방법 1: JVM 옵션 (권장)
```bash
java -Djavax.net.ssl.trustStore=/path/to/truststore \
     -Djavax.net.ssl.trustStorePassword=password \
     MyApp
```

### 방법 2: 코드에서 설정
```java
System.setProperty("javax.net.ssl.trustStore", "/path/to/truststore");
System.setProperty("javax.net.ssl.trustStorePassword", "password");
```

### 방법 3: 환경변수
```bash
export JAVA_OPTS="-Djavax.net.ssl.trustStore=/path/to/truststore"
```

## 7.3 실무 베스트 프랙티스

### DO ✅
- 테스트 환경에서는 복사본 사용
- alias는 의미있는 이름으로 지정
- 인증서 추가 시 내용 확인
- 변경 사항 문서화

### DON'T ❌
- 운영 환경 cacerts 직접 수정
- `-noprompt`를 검증 없이 사용
- 만료된 CA 인증서 추가
- 신뢰하지 않는 CA 무분별 추가

---

# 📝 실습 체크리스트

- [ ] KeyStore vs TrustStore 개념 이해
- [ ] 테스트용 cacerts 복사본 생성
- [ ] 빈 TrustStore로 연결 실패 확인
- [ ] 내부 CA 인증서 추출
- [ ] CA를 TrustStore에 추가
- [ ] 연결 성공 확인
- [ ] CA 제거 후 실패 확인
- [ ] keytool 명령어 숙달

---

## 🔗 다음 실습
[LAB-03-외부-인증서-분석.md](./LAB-03-외부-인증서-분석.md)
