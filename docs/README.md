# 🔐 Java TLS/SSL 완벽 실습 가이드

## 📚 실습 개요

이 실습 시리즈는 운영 시스템을 건드리지 않고 안전하게 Java TLS/SSL을 학습할 수 있도록 설계되었습니다.
Docker Desktop Kubernetes 환경에서 격리된 실습 환경을 제공합니다.

## 🎯 학습 목표

실습을 완료하면 다음을 할 수 있습니다:
- TLS/SSL의 동작 원리와 인증서 체인 구조 이해
- Java에서 HTTPS 연결 구현 및 TrustStore/KeyStore 관리
- mTLS(상호 인증) 환경 구축
- 인증서 관련 문제 진단 및 해결
- 자체 PKI(인증 기관) 구축

## 📋 사전 요구사항

- Docker Desktop (Kubernetes 활성화)
- kubectl, Helm 설치
- 기본적인 Linux 명령어 이해

## 🗂️ 실습 목차

| LAB | 제목 | 난이도 | 소요시간 | 파일 |
|-----|------|--------|---------|------|
| 01 | 기본 TLS 연결 이해하기 | 🟢 입문 | 30분 | [LAB-01-TLS-기초.md](./LAB-01-TLS-기초.md) |
| 02 | 인증서 신뢰 체인 실습 | 🟡 중급 | 1시간 | [LAB-02-인증서-신뢰체인.md](./LAB-02-인증서-신뢰체인.md) |
| 03 | 외부 사이트 인증서 분석 | 🟡 중급 | 1시간 | [LAB-03-외부-인증서-분석.md](./LAB-03-외부-인증서-분석.md) |
| 04 | mTLS (상호 인증) 구현 | 🟠 고급 | 2시간 | [LAB-04-mTLS-실습.md](./LAB-04-mTLS-실습.md) |
| 05 | 인증서 문제 트러블슈팅 | 🟠 고급 | 2시간 | [LAB-05-트러블슈팅.md](./LAB-05-트러블슈팅.md) |
| 06 | 자체 PKI 구축 | 🔴 심화 | 3-4시간 | [LAB-06-PKI-구축.md](./LAB-06-PKI-구축.md) |

**총 예상 소요시간: 약 10시간**

---

## 🚀 빠른 시작

### 1. 환경 배포
```powershell
cd C:\Users\upica\claude\developServer
.\deploy.bat
```

### 2. 실습 환경 접속
```powershell
kubectl exec -it -n tls-lab deploy/java-tls-lab -- /bin/bash
```

### 3. 첫 번째 실습 시작
```bash
# Pod 내부에서
cat /opt/scripts/setup-workspace.sh
# 또는 docs/LAB-01-TLS-기초.md 참조
```

---

## 📖 LAB 상세 설명

### LAB 01: 기본 TLS 연결 이해하기 🟢

**학습 내용:**
- TLS/SSL의 기본 개념 (기밀성, 무결성, 인증)
- TLS 핸드셰이크 과정
- 인증서 체인 구조 (Root CA → Intermediate → Server)
- Java TrustStore (cacerts) 역할

**주요 실습:**
- openssl s_client로 핸드셰이크 관찰
- Java에서 HTTPS 연결 성공/실패 체험
- 인증서 체인 분석

---

### LAB 02: 인증서 신뢰 체인 실습 🟡

**학습 내용:**
- KeyStore vs TrustStore 차이
- 테스트용 TrustStore 생성 방법
- 인증서 추가/삭제 관리

**주요 실습:**
- 빈 TrustStore로 연결 실패 확인
- CA 인증서 추가 후 성공 확인
- keytool 명령어 숙달

---

### LAB 03: 외부 사이트 인증서 분석 🟡

**학습 내용:**
- X.509 인증서 구조 상세
- CN vs SAN 차이
- 와일드카드 인증서 동작
- DV/OV/EV 인증서 차이

**주요 실습:**
- Google, Naver, GitHub 인증서 분석
- 인증서 체인 깊이 비교
- openssl verify로 체인 검증

---

### LAB 04: mTLS (상호 인증) 구현 🟠

**학습 내용:**
- mTLS vs 일반 TLS 차이
- 클라이언트 인증서 역할
- KeyStore + TrustStore 동시 사용

**주요 실습:**
- 클라이언트 인증서 생성 (CSR → 서명)
- PKCS12 형식 변환
- Java mTLS 클라이언트 구현

---

### LAB 05: 인증서 문제 트러블슈팅 🟠

**학습 내용:**
- 주요 TLS 에러 메시지 이해
- 체계적인 진단 방법론
- SSL 디버그 로그 해석

**주요 실습:**
- Root CA 누락 에러 재현 및 해결
- 호스트명 불일치 에러 재현
- TLS 버전/Cipher 호환성 확인
- 종합 진단 스크립트 활용

---

### LAB 06: 자체 PKI 구축 🔴

**학습 내용:**
- PKI 구성 요소 (CA, RA, CRL, OCSP)
- 인증서 수명주기
- 인증서 폐기(Revocation) 메커니즘

**주요 실습:**
- Root CA 생성 (4096bit, 10년)
- Intermediate CA 생성 및 서명
- 서버 인증서 발급 (SAN 포함)
- CRL 생성 및 인증서 폐기
- Java에서 체인 검증

---

## 🛠️ 주요 도구 및 명령어

### keytool (Java)
```bash
keytool -list -keystore <ks>          # 목록 조회
keytool -importcert -keystore <ks>    # 인증서 추가
keytool -delete -keystore <ks>        # 인증서 삭제
```

### openssl
```bash
openssl s_client -connect host:443    # TLS 연결 테스트
openssl x509 -in cert.crt -noout -text # 인증서 상세 정보
openssl verify -CAfile ca.crt cert.crt # 체인 검증
```

### Java 시스템 속성
```bash
-Djavax.net.ssl.trustStore=<path>     # TrustStore 지정
-Djavax.net.ssl.keyStore=<path>       # KeyStore 지정 (mTLS)
-Djavax.net.debug=ssl:handshake       # SSL 디버그 활성화
```

---

## 📊 모니터링 대시보드

```powershell
# 대시보드 접속
.\start-dashboards.bat
```

| 서비스 | URL | 계정 |
|--------|-----|------|
| Grafana | http://localhost:3000 | admin/admin |
| Prometheus | http://localhost:9090 | - |
| Jaeger | http://localhost:16686 | - |

---

## 🧹 환경 정리

```powershell
# 전체 정리
.\cleanup.bat

# 또는 개별 정리
kubectl delete namespace tls-lab
kubectl delete namespace monitoring
```

---

## 📚 추가 학습 자료

### 공식 문서
- [Oracle Java Security Guide](https://docs.oracle.com/en/java/javase/21/security/)
- [OpenSSL Cookbook](https://www.feistyduck.com/library/openssl-cookbook/)
- [cert-manager Documentation](https://cert-manager.io/docs/)

### 관련 기술
- Istio/Linkerd mTLS
- HashiCorp Vault PKI
- Let's Encrypt ACME

---

## 🤝 문제 해결

### 자주 묻는 질문

**Q: Pod가 시작되지 않아요**
```bash
kubectl describe pod -n tls-lab <pod-name>
kubectl logs -n tls-lab <pod-name>
```

**Q: 인증서 연결이 안 돼요**
```bash
# 진단 스크립트 실행
/workspace/scripts/tls-diagnose.sh <host:port>
```

**Q: keytool 비밀번호가 뭐예요?**
- 기본 cacerts 비밀번호: `changeit`
- 실습용 비밀번호: 각 LAB에서 안내

---

## 📝 체크리스트

전체 실습 완료 체크리스트:

- [ ] LAB 01: TLS 기본 개념 이해
- [ ] LAB 02: TrustStore 관리 숙달
- [ ] LAB 03: 인증서 분석 능력
- [ ] LAB 04: mTLS 구현 완료
- [ ] LAB 05: 트러블슈팅 능력
- [ ] LAB 06: PKI 구축 경험

**모든 체크박스를 완료하면 Java TLS/SSL 전문가! 🎉**
