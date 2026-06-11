# Innovatech Chile — Sistema de Despachos y Ventas
**ISY1101 — Introducción a Herramientas DevOps | Evaluación Parcial N°2**

**Integrante:** Rodrigo Concha / Benjamín Belmar
**Profesor:** Israel Villagra

---

## Descripción del Proyecto

Sistema de gestión de ventas y despachos para Innovatech Chile, compuesto por tres microservicios contenedorizados y desplegados en AWS EC2 mediante un pipeline CI/CD automatizado con GitHub Actions.

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
│   ├── nginx.conf              ← proxy inverso a los backends
│   └── src/
├── Terraform/
│   └── main.tf                 ← infraestructura AWS como código
├── docker-compose.yml          ← stack completo local
├── .env.example                ← plantilla de variables de entorno
└── .github/
    └── workflows/
        ├── deploy-backend.yml
        ├── deploy-back-ventas.yml
        └── deploy-frontend.yml
```

---

## Requisitos Previos

- Docker Desktop instalado y corriendo
- AWS CLI configurado (`aws configure`)
- Git
- Terraform

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

## Arquitectura en AWS

```
Internet
    ↓
[ec2-web — IP pública] ← solo el frontend es accesible desde internet
    ↓ (red privada)
[ec2-app — IP privada] ← backend Despachos (8081) y Ventas (8080)
    ↓ (red privada)
[MySQL] ← base de datos
```

Infraestructura creada con **Terraform**:
- VPC con subnets pública y privada
- 2 instancias EC2 (t3.micro)
- Security Groups con reglas restrictivas
- 3 repositorios ECR (frontend, backend-despachos, backend-ventas)
- NAT Gateway para acceso desde subnets privadas
- IP elástica para el frontend

---

## Dockerfiles — Multi-stage Build

Todos los servicios usan **multi-stage build** para minimizar el tamaño de la imagen final:

**Frontend (React + Nginx):**
- Stage 1: `node:20-alpine` — instala dependencias y ejecuta `npm run build`
- Stage 2: `nginx:stable-alpine` — sirve los archivos estáticos compilados

**Backends (Spring Boot):**
- Stage 1: `eclipse-temurin:17-jdk-alpine` — compila el proyecto con Maven
- Stage 2: `eclipse-temurin:17-jre-alpine` — ejecuta solo el JAR (sin JDK)
- Usuario no root: `adduser appuser` para mayor seguridad

---

## Docker Compose — Stack Completo

El archivo `docker-compose.yml` define 4 servicios:

| Servicio | Imagen | Puerto | Red |
|---|---|---|---|
| mysql-db | mysql:8.0 | 3307:3306 | backend-net |
| back-despachos | build local | 8081:8081 | backend-net, frontend-net |
| back-ventas | build local | 8080:8080 | backend-net, frontend-net |
| front-despacho | build local | 80:80 | frontend-net |

### Persistencia de Datos

Se usa **named volume** `mysql_data` para MySQL:

```yaml
volumes:
  mysql_data:
    driver: local
```

**¿Por qué named volume y no bind mount?**
El named volume es gestionado por Docker, es portable entre sistemas operativos, sobrevive a `docker compose down` y es la práctica recomendada para bases de datos en producción. El bind mount requiere una ruta del sistema host, lo que genera dependencia del entorno.

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
  SSH a instancia EC2
        ↓
  docker pull + docker run
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
| `EC2_PUBLIC_IP` | IP pública de ec2-web |
| `EC2_HOST_BACKEND` | IP de la instancia backend |
| `EC2_SSH_KEY` | Clave privada SSH (.pem) |
| `DB_NAME` | Nombre de la base de datos |
| `DB_USERNAME` | Usuario de la base de datos |
| `DB_PASSWORD` | Contraseña de la base de datos |

---

## Principios DevOps Aplicados

| Práctica | Implementación |
|---|---|
| Contenedorización | Docker multi-stage para los 3 servicios |
| Inmutabilidad | Imágenes versionadas por SHA del commit en ECR |
| CI/CD | GitHub Actions con trigger en rama `deploy` |
| Seguridad | GitHub Secrets, usuario no root en contenedores |
| Persistencia | Named volume para MySQL |
| Control de versiones | Git con ramas `main` y `deploy` |
| IaC | Terraform gestiona toda la infraestructura AWS |

---

## Cómo Levantar la Infraestructura en AWS

```bash
# 1. Configurar credenciales AWS Academy
aws configure set aws_access_key_id TU_KEY
aws configure set aws_secret_access_key TU_SECRET
aws configure set aws_session_token TU_TOKEN

# 2. Crear infraestructura con Terraform
cd Terraform
terraform apply

# 3. Actualizar secrets en GitHub con nueva IP y credenciales

# 4. Disparar el pipeline
git commit --allow-empty -m "deploy: levantar servicios"
git push origin deploy
```

---

## Cómo Bajar la Infraestructura

```bash
cd Terraform
terraform destroy
```

> ⚠️ Las credenciales de AWS Academy expiran cada ~4 horas. Actualiza los secrets en GitHub y reconfigura AWS CLI cada vez que inicies el laboratorio.
