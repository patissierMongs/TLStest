@echo off
REM ============================================
REM Java TLS/SSL Lab - Cleanup Script
REM ============================================

echo.
echo ============================================================
echo         Java TLS/SSL Lab - Cleanup
echo ============================================================
echo.

set /p confirm="Are you sure you want to delete all resources? (y/N): "
if /i not "%confirm%"=="y" (
    echo Cancelled.
    exit /b 0
)

echo.
echo [1/4] Deleting Java lab...
kubectl delete -f k8s\java-lab\deployment.yaml --ignore-not-found

echo.
echo [2/4] Deleting TLS server and certificates...
kubectl delete -f k8s\tls-server\deployment.yaml --ignore-not-found
kubectl delete -f k8s\cert-manager\certificates.yaml --ignore-not-found

echo.
echo [3/4] Deleting monitoring stack...
kubectl delete -f k8s\monitoring\ --ignore-not-found

echo.
echo [4/4] Deleting namespaces...
kubectl delete -f k8s\namespace.yaml --ignore-not-found

echo.
set /p uninstall_cm="Also uninstall cert-manager? (y/N): "
if /i "%uninstall_cm%"=="y" (
    echo Uninstalling cert-manager...
    helm uninstall cert-manager -n cert-manager
    kubectl delete namespace cert-manager --ignore-not-found
)

echo.
echo ============================================================
echo Cleanup Complete!
echo ============================================================
echo.
