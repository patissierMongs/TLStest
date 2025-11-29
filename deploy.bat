@echo off
chcp 65001 >nul 2>&1
REM ============================================
REM Java TLS/SSL Lab - Deployment Script
REM Docker Desktop Kubernetes
REM ============================================

echo.
echo ============================================================
echo         Java TLS/SSL Lab - Kubernetes Deployment
echo ============================================================
echo.

REM Check prerequisites
echo [1/7] Checking prerequisites...
kubectl version --client >nul 2>&1
if errorlevel 1 (
    echo [ERROR] kubectl is not installed.
    exit /b 1
)

helm version --short >nul 2>&1
if errorlevel 1 (
    echo [ERROR] Helm is not installed.
    echo         Install from: https://helm.sh/docs/intro/install/
    exit /b 1
)

kubectl cluster-info >nul 2>&1
if errorlevel 1 (
    echo [ERROR] Cannot connect to Kubernetes cluster.
    echo         Enable Kubernetes in Docker Desktop.
    exit /b 1
)

echo [OK] All prerequisites met

REM Create namespaces
echo.
echo [2/7] Creating namespaces...
kubectl apply -f k8s\namespace.yaml
echo [OK] Namespaces created

REM Install cert-manager
echo.
echo [3/7] Installing cert-manager...
kubectl get namespace cert-manager >nul 2>&1
if errorlevel 1 (
    helm repo add jetstack https://charts.jetstack.io
    helm repo update
    helm install cert-manager jetstack/cert-manager --namespace cert-manager --create-namespace --set installCRDs=true --wait
) else (
    echo      cert-manager already installed.
)
echo [OK] cert-manager ready

REM Wait for cert-manager
echo.
echo [4/7] Waiting for cert-manager (max 60s)...
kubectl wait --for=condition=available --timeout=60s deployment/cert-manager -n cert-manager
kubectl wait --for=condition=available --timeout=60s deployment/cert-manager-webhook -n cert-manager

REM Deploy certificates and TLS server
echo.
echo [5/7] Deploying certificates and TLS server...
kubectl apply -f k8s\cert-manager\certificates.yaml
echo      Waiting for certificate issuance...
timeout /t 10 /nobreak >nul
kubectl apply -f k8s\tls-server\deployment.yaml
echo [OK] TLS server deployed

REM Deploy monitoring stack
echo.
echo [6/7] Deploying monitoring stack...
kubectl apply -f k8s\monitoring\prometheus.yaml
kubectl apply -f k8s\monitoring\grafana.yaml
kubectl apply -f k8s\monitoring\loki.yaml
kubectl apply -f k8s\monitoring\jaeger.yaml
kubectl apply -f k8s\monitoring\kube-state-metrics.yaml
echo [OK] Monitoring stack deployed

REM Deploy Java lab
echo.
echo [7/7] Deploying Java TLS lab environment...
kubectl apply -f k8s\java-lab\deployment.yaml
echo [OK] Java lab deployed

REM Check deployment status
echo.
echo ============================================================
echo Checking deployment status...
echo ============================================================
echo.

echo [tls-lab namespace]
kubectl get pods -n tls-lab

echo.
echo [monitoring namespace]
kubectl get pods -n monitoring

echo.
echo ============================================================
echo Deployment Complete!
echo ============================================================
echo.
echo Access Methods:
echo.
echo   Java Lab Pod:
echo   kubectl exec -it -n tls-lab deploy/java-tls-lab -- /bin/bash
echo.
echo   Grafana Dashboard (localhost:3000, admin/admin):
echo   kubectl port-forward -n monitoring svc/grafana 3000:3000
echo.
echo   Prometheus UI (localhost:9090):
echo   kubectl port-forward -n monitoring svc/prometheus 9090:9090
echo.
echo   Jaeger UI (localhost:16686):
echo   kubectl port-forward -n monitoring svc/jaeger 16686:16686
echo.
echo See README.md for detailed guide.
echo.
