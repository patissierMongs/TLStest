#!/bin/bash
# ============================================
# Java TLS/SSL Lab - 전체 배포 스크립트
# Docker Desktop Kubernetes 환경용 (WSL/Git Bash)
# ============================================

set -e

echo ""
echo "╔════════════════════════════════════════════════════════════╗"
echo "║        Java TLS/SSL Lab - Kubernetes Deployment            ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""

# 스크립트 디렉토리로 이동
cd "$(dirname "$0")"

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 사전 요구사항 확인
echo "[1/7] 사전 요구사항 확인..."

if ! command -v kubectl &> /dev/null; then
    echo -e "${RED}❌ kubectl이 설치되지 않았습니다.${NC}"
    exit 1
fi

if ! command -v helm &> /dev/null; then
    echo -e "${RED}❌ Helm이 설치되지 않았습니다.${NC}"
    echo "   설치: https://helm.sh/docs/intro/install/"
    exit 1
fi

if ! kubectl cluster-info &> /dev/null; then
    echo -e "${RED}❌ Kubernetes 클러스터에 연결할 수 없습니다.${NC}"
    echo "   Docker Desktop에서 Kubernetes를 활성화하세요."
    exit 1
fi

echo -e "${GREEN}✅ 모든 사전 요구사항 충족${NC}"

# 네임스페이스 생성
echo ""
echo "[2/7] 네임스페이스 생성..."
kubectl apply -f k8s/namespace.yaml
echo -e "${GREEN}✅ 네임스페이스 생성 완료${NC}"

# cert-manager 설치
echo ""
echo "[3/7] cert-manager 설치..."
if ! kubectl get namespace cert-manager &> /dev/null; then
    helm repo add jetstack https://charts.jetstack.io
    helm repo update
    helm install cert-manager jetstack/cert-manager \
      --namespace cert-manager \
      --create-namespace \
      --set installCRDs=true \
      --wait
else
    echo "   cert-manager가 이미 설치되어 있습니다."
fi
echo -e "${GREEN}✅ cert-manager 준비 완료${NC}"

# cert-manager 준비 대기
echo ""
echo "[4/7] cert-manager 준비 대기 (최대 60초)..."
kubectl wait --for=condition=available --timeout=60s deployment/cert-manager -n cert-manager
kubectl wait --for=condition=available --timeout=60s deployment/cert-manager-webhook -n cert-manager

# 인증서 설정
echo ""
echo "[5/7] 인증서 및 TLS 서버 배포..."
kubectl apply -f k8s/cert-manager/certificates.yaml
echo "   인증서 발급 대기 중..."
sleep 10
kubectl apply -f k8s/tls-server/deployment.yaml
echo -e "${GREEN}✅ TLS 서버 배포 완료${NC}"

# 모니터링 스택 배포
echo ""
echo "[6/7] 모니터링 스택 배포..."
kubectl apply -f k8s/monitoring/prometheus.yaml
kubectl apply -f k8s/monitoring/grafana.yaml
kubectl apply -f k8s/monitoring/loki.yaml
kubectl apply -f k8s/monitoring/jaeger.yaml
kubectl apply -f k8s/monitoring/kube-state-metrics.yaml
echo -e "${GREEN}✅ 모니터링 스택 배포 완료${NC}"

# Java 실습 환경 배포
echo ""
echo "[7/7] Java TLS 실습 환경 배포..."
kubectl apply -f k8s/java-lab/deployment.yaml
echo -e "${GREEN}✅ Java 실습 환경 배포 완료${NC}"

# 배포 상태 확인
echo ""
echo "════════════════════════════════════════════════════════════"
echo "배포 상태 확인 중..."
echo "════════════════════════════════════════════════════════════"
echo ""

echo -e "${YELLOW}[tls-lab 네임스페이스]${NC}"
kubectl get pods -n tls-lab

echo ""
echo -e "${YELLOW}[monitoring 네임스페이스]${NC}"
kubectl get pods -n monitoring

echo ""
echo "════════════════════════════════════════════════════════════"
echo -e "${GREEN}🎉 배포 완료!${NC}"
echo "════════════════════════════════════════════════════════════"
echo ""
echo "📌 접속 방법:"
echo ""
echo "   Java 실습 Pod 접속:"
echo "   kubectl exec -it -n tls-lab deploy/java-tls-lab -- /bin/bash"
echo ""
echo "   Grafana 대시보드 (localhost:3000, admin/admin):"
echo "   kubectl port-forward -n monitoring svc/grafana 3000:3000"
echo ""
echo "   Prometheus UI (localhost:9090):"
echo "   kubectl port-forward -n monitoring svc/prometheus 9090:9090"
echo ""
echo "   Jaeger UI (localhost:16686):"
echo "   kubectl port-forward -n monitoring svc/jaeger 16686:16686"
echo ""
echo "📖 상세 가이드: README.md 참조"
echo ""
