@echo off
REM ============================================
REM Monitoring Dashboard Port-Forward Script
REM ============================================

echo.
echo Starting monitoring dashboards...
echo.
echo Access URLs:
echo   - Grafana:    http://localhost:3000 (admin/admin)
echo   - Prometheus: http://localhost:9090
echo   - Jaeger:     http://localhost:16686
echo.
echo Press Ctrl+C in each window to stop.
echo.

start "Grafana" cmd /c "kubectl port-forward -n monitoring svc/grafana 3000:3000"
start "Prometheus" cmd /c "kubectl port-forward -n monitoring svc/prometheus 9090:9090"
start "Jaeger" cmd /c "kubectl port-forward -n monitoring svc/jaeger 16686:16686"

echo Port-forwarding started in background windows.
echo Close each window to stop the respective service.
pause
