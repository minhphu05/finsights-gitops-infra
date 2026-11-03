# Finsights GitOps Infrastructure (`finsights-gitops-infra`)

Repository quản lý cấu hình GitOps tập trung cho cụm K3s (2 VPS Nodes), chịu trách nhiệm:
1. **Cài đặt & Bootstrap ArgoCD** trực tiếp lên cụm K3s (bao gồm manifests offline, NodePort 30200, Web Insecure mode).
2. **Quản lý AppProjects & App-of-Apps Root Applications** (điều phối cả Infra Add-ons và Platform Services).
3. **Quản lý các Cluster Add-ons cốt lõi**:
   - `ingress-nginx`: Ingress Controller (DaemonSet NodePort 30080/30443)
   - `cert-manager`: Tự động cấp phát và gia hạn chứng chỉ Let's Encrypt SSL/TLS
   - `headlamp`: Dashboard Web UI trực quan quản trị Kubernetes (NodePort 32003)

---

## 1. Cấu trúc thư mục (Directory Structure)

```
finsights-gitops-infra/
├── .gitignore
├── README.md
├── bootstrap/
│   ├── bootstrap.sh                  # 🚀 Script 1-click cài ArgoCD & kích hoạt GitOps
│   ├── 00-install-argocd/            # Toàn bộ manifests cài đặt ArgoCD v2.13.3 (chạy offline)
│   │   ├── upstream-install.yaml     # Manifests chính thức của ArgoCD
│   │   ├── argocd-cmd-params-cm-patch.yaml # Patch server.insecure: true
│   │   ├── argocd-server-service-patch.yaml # Patch mở NodePort 30200
│   │   ├── argocd-ingress.yaml       # Ingress trỏ domain argocd.finsights.biz
│   │   └── kustomization.yaml        # Kustomize bundle
│   ├── 01-git-credentials/          # Cấu hình Secret xác thực Private Git Repositories
│   │   └── argocd-git-credentials.yaml
│   ├── 02-projects/                  # Phân quyền AppProject trong ArgoCD
│   │   └── appproject.yaml           # Gồm finsights-infra và finsights-platform
│   ├── 03-apps/                      # Khai báo App-of-Apps Root & Individual Applications
│   │   ├── root-infra-addons.yaml    # Root App quản lý addons (Ingress, Cert-Manager, Headlamp)
│   │   ├── root-platform-apps.yaml   # Root App quản lý platform apps (Redis, Backend, v.v.)
│   │   └── addons/                   # Manifests ứng dụng cho từng Add-on
│   │       ├── ingress-nginx.yaml
│   │       ├── cert-manager.yaml
│   │       └── headlamp.yaml
│   └── applicationset.yaml           # ApplicationSet động quét thư mục addons/*
└── addons/                           # Toàn bộ Helm charts của hạ tầng (Cluster Add-ons)
    ├── ingress-nginx/
    │   ├── Chart.yaml
    │   ├── templates/
    │   ├── values.yaml
    │   └── values-dev.yaml
    ├── cert-manager/
    │   ├── Chart.yaml
    │   ├── templates/
    │   ├── values.yaml
    │   ├── values-dev.yaml
    │   └── cluster-issuers/
    │       └── letsencrypt-issuers.yaml
    └── headlamp/
        ├── Chart.yaml
        ├── templates/
        ├── values.yaml
        └── values-dev.yaml
```

---

## 2. Quy trình Cài đặt & Bootstrap ArgoCD (1-Click)

### Cách nhanh nhất: Chạy script tự động
```bash
cd bootstrap
./bootstrap.sh
```

### Cách cài thủ công từng bước (Manual Installation):
```bash
# Bước 1: Tạo namespace
kubectl create namespace argocd

# Bước 2: Cài đặt ArgoCD với NodePort 30200
kubectl apply -k bootstrap/00-install-argocd

# Bước 3: Đợi Pod argocd-server sẵn sàng
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=argocd-server -n argocd --timeout=300s

# Bước 4: Tạo AppProjects
kubectl apply -f bootstrap/02-projects/appproject.yaml

# Bước 5: Kích hoạt App-of-Apps
kubectl apply -f bootstrap/03-apps/root-infra-addons.yaml
kubectl apply -f bootstrap/03-apps/root-platform-apps.yaml

# Bước 6: Lấy mật khẩu admin đăng nhập
kubectl get secret argocd-initial-admin-secret -n argocd -o jsonpath="{.data.password}" | base64 -d
```

---

## 3. Cách truy cập các Dashboard Quản trị

| Dịch vụ | URL Truy cập | Tài khoản / Xác thực |
| :--- | :--- | :--- |
| **ArgoCD Web UI** | `http://103.249.117.232:30200`<br>`https://finsights-prod-node-01.tail73ddb8.ts.net` (Tailscale Cổng 443) | User: `admin`<br>Password: Lấy từ `argocd-initial-admin-secret` |
| **Headlamp K8s UI** | `http://103.249.117.232:32003`<br>`https://finsights-prod-node-01.tail73ddb8.ts.net:8443` (Tailscale Cổng 8443) | Lấy Token:<br>`kubectl get secret headlamp-admin-token -n platform -o jsonpath="{.data.token}" \| base64 -d` |
| **Dagster Web UI** | `http://103.249.117.232:31882`<br>`https://finsights-prod-node-01.tail73ddb8.ts.net:10000` (Tailscale Cổng 10000) | Quản trị Orchestration & Data Pipelines |
| **Ingress HTTP/HTTPS** | `http://103.249.117.232:30080`<br>`https://103.249.117.232:30443` | Cổng tiếp nhận lưu lượng cho toàn bộ domain (`finsights.biz`) |

---

## 4. Cơ chế đồng bộ giữa 2 Repository

Mô hình GitOps được kết nối thông qua 2 Root Applications:

```
                          +------------------------+
                          |   ArgoCD (Port 30200)  |
                          +-----------+------------+
                                      |
                 +--------------------+--------------------+
                 |                                         |
                 v                                         v
   +-----------------------------+           +-----------------------------+
   |      root-infra-addons      |           |     root-platform-apps      |
   | (Quản lý các Add-on hạ tầng)|           |  (Quản lý các Apps/Database)|
   +--------------+--------------+           +--------------+--------------+
                  |                                         |
                  v                                         v
       repo: finsights-gitops-infra          repo: finsights-platform-deployment
       path: bootstrap/03-apps/addons        path: applications/
         - ingress-nginx                       - redis.yaml
         - cert-manager                        - (các service tiếp theo)
         - headlamp
```
