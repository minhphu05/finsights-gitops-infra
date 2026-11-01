#!/usr/bin/env bash
# ==============================================================================
# Finsights ArgoCD Cluster Bootstrap Script
# Automatically provisions ArgoCD, AppProjects, and App-of-Apps onto K3s
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "===================================================================="
echo "      🚀 BOOTSTRAP ARGOCD & GITOPS CHO CỤM K3S FINSIGHTS            "
echo "===================================================================="

# 1. Kiểm tra kết nối Kubernetes
echo "🔍 [1/6] Kiểm tra kết nối cụm Kubernetes..."
if ! kubectl cluster-info > /dev/null 2>&1; then
    echo "❌ Lỗi: Không thể kết nối đến Kubernetes API. Vui lòng kiểm tra file KUBECONFIG!"
    exit 1
fi
echo "   ✅ Đã kết nối thành công tới cụm K3s."

# 2. Tạo Namespace argocd
echo "📦 [2/6] Khởi tạo namespace 'argocd'..."
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -

# 3. Cài đặt ArgoCD (NodePort 30200, HTTP Insecure backend)
echo "⚡ [3/6] Cài đặt ArgoCD v2.13.3 qua Kustomize..."
kubectl apply -k "${SCRIPT_DIR}/00-install-argocd"

# 4. Chờ Pod argocd-server sẵn sàng
echo "⏳ [4/6] Chờ Pod argocd-server khởi động (tối đa 300s)..."
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=argocd-server -n argocd --timeout=300s
echo "   ✅ Pod argocd-server đã sẵn sàng."

# 5. Khởi tạo AppProjects
echo "📂 [5/6] Đăng ký AppProjects (finsights-infra & finsights-platform)..."
kubectl apply -f "${SCRIPT_DIR}/02-projects/appproject.yaml"

# 6. Kích hoạt mô hình App-of-Apps
echo "🔗 [6/6] Khởi động App-of-Apps Root Applications..."
kubectl apply -f "${SCRIPT_DIR}/03-apps/root-infra-addons.yaml"
kubectl apply -f "${SCRIPT_DIR}/03-apps/root-platform-apps.yaml"

# Lấy mật khẩu admin ban đầu
ADMIN_PASSWORD=""
if kubectl get secret argocd-initial-admin-secret -n argocd > /dev/null 2>&1; then
    ADMIN_PASSWORD=$(kubectl get secret argocd-initial-admin-secret -n argocd -o jsonpath="{.data.password}" | base64 -d)
fi

CONTROL_PLANE_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')

echo ""
echo "===================================================================="
echo "🎉 CHÚC MỪNG! ARGOCD & GITOPS ĐÃ ĐƯỢC BOOTSTRAP THÀNH CÔNG!         "
echo "===================================================================="
echo "🌐 URL Giao diện Web:   http://${CONTROL_PLANE_IP:-103.249.117.232}:30200"
echo "👤 Username:             admin"
if [ -n "$ADMIN_PASSWORD" ]; then
    echo "🔑 Password:             ${ADMIN_PASSWORD}"
else
    echo "🔑 Password:             (Đã được đổi hoặc lấy qua kubectl get secret argocd-initial-admin-secret -n argocd)"
fi
echo "===================================================================="
echo "💡 Các bước tiếp theo:"
echo "1. Cấu hình Git Token trong: bootstrap/01-git-credentials/argocd-git-credentials.yaml"
echo "2. Kiểm tra trạng thái đồng bộ: kubectl get applications -n argocd"
echo "===================================================================="
