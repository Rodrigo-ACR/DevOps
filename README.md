# Innovatech Chile — Sistema de Despachos y Ventas
**ISY1101 — Introducción a Herramientas DevOps | Evaluación Parcial N°3**

**Integrante:** Rodrigo Concha  
**Profesor:** Israel Villagra

---

## Descripción del Proyecto

Sistema de gestión de ventas y despachos para Innovatech Chile, compuesto por tres microservicios contenedorizados y orquestados en **AWS EKS (Kubernetes)** mediante un pipeline CI/CD automatizado con GitHub Actions.

| Servicio | Tecnología | Puerto |
|---|---|---|
| Frontend | React 18 + Vite + Tailwind + Nginx | 80 |
| Backend Despachos | Spring Boot 3.4.4 + Java 17 | 8081 |
| Backend Ventas | Spring Boot 3.4.4 + Java 17 | 8080 |
| Base de datos | MySQL 8.0 | 3306 |

---

## Estructura del Repositorio

```
.
├── back-Despachos_SpringBoot/
│   └── Springboot-API-REST-DESPACHO/
│       ├── Dockerfile          ← multi-stage, usuario no root
│       └── src/
├── back-Ventas_SpringBoot/
│   └── Springboot-API-REST/
│       ├── Dockerfile          ← multi-stage, usuario no root
│       └── src/
├── front_despacho/
│   ├── Dockerfile              ← multi-stage Node + Nginx
│   ├── default.conf.template   ← proxy inverso parametrizado por env vars
│   └── src/
├── k8s/                        ← manifiestos Kubernetes (EP3)
│   ├── 00-namespace.yaml       ← namespace innovatech
│   ├── 00-storageclass.yaml    ← StorageClass gp2-immediate
│   ├── 01-mysql.yaml           ← Deployment + Service MySQL
│   ├── 02-backend-despachos.yaml
│   ├── 03-backend-ventas.yaml
│   ├── 04-frontend.yaml        ← Deployment + Service LoadBalancer
│   └── 05-hpa.yaml             ← HorizontalPodAutoscaler x3
├── eks-cluster.yaml            ← configuración del clúster EKS (eksctl)
├── docker-compose.yml          ← stack completo local
└── .github/
    └── workflows/
        ├── deploy-backend.yml
        ├── deploy-back-ventas.yml
        └── deploy-frontend.yml
```

---

## Arquitectura EP3 — AWS EKS

```
Internet
    ↓
[Application Load Balancer — DNS público]
    ↓
[EKS Cluster — innovatech-cluster]
    ├── Namespace: innovatech
    │   ├── Pod: front-despacho  (nginx, puerto 80)
    │   │       ↓ proxy interno K8s
    │   ├── Pod: back-despachos  (Spring Boot, puerto 8081)
    │   ├── Pod: back-ventas     (Spring Boot, puerto 8080)
    │   └── Pod: mysql           (MySQL 8.0, puerto 3306)
    └── Node Group: nodos-innovatech (2x t3.medium, subredes privadas)
```

### Componentes AWS
| Componente | Detalle |
|---|---|
| EKS Cluster | `innovatech-cluster` — Kubernetes 1.32 |
| Node Group | 2 nodos `t3.medium` en subredes privadas |
| ECR | 3 repositorios: frontend, backend-despachos, backend-ventas |
| LoadBalancer | ELB creado automáticamente por K8s (tipo LoadBalancer) |
| CloudWatch | Logs del clúster: api, audit, authenticator |
| IAM | `LabRole` para permisos de nodos y addons |

### Autoscaling — HPA
Los 3 servicios tienen **HorizontalPodAutoscaler** configurado:

| Servicio | Min Pods | Max Pods | Umbral CPU |
|---|---|---|---|
| back-despachos | 1 | 3 | 50% |
| back-ventas | 1 | 3 | 50% |
| front-despacho | 1 | 3 | 50% |

El HPA escala automáticamente cuando el uso de CPU supera el 50% del request definido, y reduce réplicas cuando baja del umbral. Durante el despliegue se evidenció escalado real: `New size: 2` al detectar carga, y `New size: 1` al normalizarse.

---

## Requisitos Previos

- Docker Desktop instalado y corriendo
- AWS CLI configurado
- `kubectl` instalado
- `eksctl` instalado
- Git

---

## Levantar el Proyecto Localmente

### 1. Clonar el repositorio

```bash
git clone https://github.com/Rodrigo-ACR/DevOps.git
cd DevOps
```

### 2. Crear el archivo de variables de entorno

```bash
cp .env.example .env
# Edita .env con tus valores reales
```

### 3. Levantar todos los servicios

```bash
docker compose up --build
```

### 4. URLs locales

| Servicio | URL |
|---|---|
| Frontend | http://localhost |
| API Despachos | http://localhost:8081/api/v1/despachos |
| API Ventas | http://localhost:8080/api/v1/ventas |

---

## Despliegue en AWS EKS

### 1. Configurar credenciales AWS Academy

```bash
aws configure set aws_access_key_id TU_KEY
aws configure set aws_secret_access_key TU_SECRET
aws configure set aws_session_token TU_TOKEN
aws configure set region us-east-1
```

### 2. Crear repositorios ECR

```bash
aws ecr create-repository --repository-name innovatech-frontend --region us-east-1
aws ecr create-repository --repository-name innovatech-backend-despachos --region us-east-1
aws ecr create-repository --repository-name innovatech-backend-ventas --region us-east-1
```

### 3. Crear el clúster EKS

```bash
eksctl create cluster -f eks-cluster.yaml
# Tarda ~15-20 minutos
```

### 4. Aplicar manifiestos Kubernetes

```bash
# Crear namespace y StorageClass
kubectl apply -f k8s/00-namespace.yaml
kubectl apply -f k8s/00-storageclass.yaml

# Crear Secret con credenciales de BD
kubectl create secret generic db-secret \
  --namespace innovatech \
  --from-literal=MYSQL_ROOT_PASSWORD=tu_root_pass \
  --from-literal=DB_NAME=innovatech_db \
  --from-literal=DB_USERNAME=appuser \
  --from-literal=DB_PASSWORD=tu_pass

# Desplegar todos los servicios
kubectl apply -f k8s/
```

### 5. Obtener URL pública

```bash
kubectl get svc front-despacho-service -n innovatech
# Usar el campo EXTERNAL-IP (DNS del LoadBalancer)
```

### 6. Disparar pipeline CI/CD

```bash
git push origin deploy
# Los 3 workflows se disparan automáticamente
```

---

## Pipeline CI/CD — GitHub Actions

Cada push en la rama `deploy` dispara automáticamente los 3 pipelines.

### Flujo del Pipeline

```
push en rama deploy
        ↓
  Checkout código
        ↓
  Configurar credenciales AWS (secrets)
        ↓
  Login a Amazon ECR
        ↓
  docker build (multi-stage)
        ↓
  docker push → ECR (tag: latest + SHA del commit)
        ↓
  Configurar kubectl (desde KUBECONFIG_B64)
        ↓
  kubectl set image → actualiza el pod en EKS
        ↓
  kubectl rollout status → verifica el deploy
```

### Secrets Requeridos en GitHub

| Secret | Descripción |
|---|---|
| `AWS_ACCESS_KEY_ID` | Clave de acceso AWS |
| `AWS_SECRET_ACCESS_KEY` | Clave secreta AWS |
| `AWS_SESSION_TOKEN` | Token de sesión (AWS Academy) |
| `AWS_REGION` | Región (`us-east-1`) |
| `ECR_REGISTRY_URL` | URL base del registro ECR |
| `ECR_REPO_FRONTEND` | Nombre repo ECR frontend |
| `ECR_REPO_BACKEND` | Nombre repo ECR backend despachos |
| `ECR_REPO_VENTAS` | Nombre repo ECR backend ventas |
| `KUBECONFIG_B64` | kubeconfig del clúster EKS en base64 |
| `DB_NAME` | Nombre de la base de datos |
| `DB_USERNAME` | Usuario de la base de datos |
| `DB_PASSWORD` | Contraseña de la base de datos |
| `MYSQL_ROOT_PASSWORD` | Contraseña root de MySQL |

---

## Dockerfiles — Multi-stage Build

Todos los servicios usan **multi-stage build** para minimizar el tamaño de la imagen final:

**Frontend (React + Nginx):**
- Stage 1: `node:20-alpine` — instala dependencias y ejecuta `npm run build`
- Stage 2: `nginx:stable-alpine` — sirve los archivos estáticos compilados con proxy parametrizado por variables de entorno

**Backends (Spring Boot):**
- Stage 1: `eclipse-temurin:17-jdk-alpine` — compila el proyecto con Maven
- Stage 2: `eclipse-temurin:17-jre-alpine` — ejecuta solo el JAR (sin JDK)
- Usuario no root: `adduser appuser` para mayor seguridad

---

## Comandos Útiles Kubernetes

```bash
# Ver estado de todos los recursos
kubectl get all -n innovatech

# Ver logs de un servicio
kubectl logs -l app=back-despachos -n innovatech --tail=50

# Ver métricas de pods y nodos
kubectl top pods -n innovatech
kubectl top nodes

# Ver estado del autoscaling
kubectl get hpa -n innovatech
kubectl describe hpa -n innovatech

# Ver eventos del clúster
kubectl get events -n innovatech --sort-by='.lastTimestamp'
```

---

## Principios DevOps Aplicados

| Práctica | Implementación |
|---|---|
| Contenedorización | Docker multi-stage para los 3 servicios |
| Orquestación | Kubernetes en AWS EKS |
| Inmutabilidad | Imágenes versionadas por SHA del commit en ECR |
| CI/CD | GitHub Actions con trigger en rama `deploy` |
| Autoscaling | HPA por CPU al 50% para los 3 servicios |
| Balanceo de carga | ELB creado automáticamente por K8s |
| Seguridad | GitHub Secrets, usuario no root, K8s Secrets para BD |
| Observabilidad | Logs en CloudWatch (`/aws/eks/innovatech-cluster/cluster`) |
| IaC | eksctl + manifiestos K8s gestionan toda la infraestructura |

---

## Notas AWS Academy

> ⚠️ Las credenciales de AWS Academy expiran cada ~4 horas. Al reiniciar el laboratorio:
> 1. Actualizar `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY` y `AWS_SESSION_TOKEN` en GitHub Secrets
> 2. Actualizar las credenciales locales en `~/.aws/credentials`
> 3. Actualizar el secret `KUBECONFIG_B64` si el clúster fue recreado
>
> El clúster EKS **no se detiene** al cerrar el lab (a diferencia de las EC2). Los pods siguen corriendo entre sesiones.