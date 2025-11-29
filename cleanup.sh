#!/bin/bash
# ============================================
# Java TLS/SSL Lab - 환경 정리 스크립트
# ============================================

set -e

cd "$(dirname "$0")"

echo ""
echo "╔════════════════════════════════════════════════════════════╗"
echo "║        Java TLS/SSL Lab - Cleanup                          ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""

read -p "정말로 모든 리소스를 삭제하시겠습니까? (y/N): " confirm
if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
    echo "취소되었습니다."
    exit 0
fi

echo ""
echo "[1/4] Java 실습 환경 삭제..."
kubectl delete -f k8s/java-lab/deployment.yaml --ignore-not-found || true

echo ""
echo "[2/4] TLS 서버 및 인증서 삭제..."
kubectl delete -f k8s/tls-server/deployment.yaml --ignore-not-found || true
kubectl delete -f k8s/cert-manager/certificates.yaml --ignore-not-found || true

echo ""
echo "[3/4] 모니터링 스택 삭제..."
kubectl delete -f k8s/monitoring/ --ignore-not-found || true

echo ""
echo "[4/4] 네임스페이스 삭제..."
kubectl delete -f k8s/namespace.yaml --ignore-not-found || true

echo ""
read -p "cert-manager도 삭제하시겠습니까? (y/N): " uninstall_cm
if [[ "$uninstall_cm" =~ ^[Yy]$ ]]; then
    echo "cert-manager 삭제 중..."
    helm uninstall cert-manager -n cert-manager || true
    kubectl delete namespace cert-manager --ignore-not-found || true
fi

echo ""
echo "════════════════════════════════════════════════════════════"
echo "✅ 정리 완료!"
echo "════════════════════════════════════════════════════════════"
echo ""
