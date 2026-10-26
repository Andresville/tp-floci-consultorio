# TP – Sitio web en un bucket S3 simulado con Floci + Terraform

Despliegue del sitio del **Consultorio Dra. Ronconi** en un bucket **S3** que corre
localmente dentro de **Floci** (emulador de AWS) en un contenedor **Docker**.
Toda la infraestructura se crea con **Terraform** (`main.tf`).

## Estructura

```
.
├── main.tf     # Infraestructura: contenedor Floci + bucket S3 + subida de archivos
└── sitio/      # Sitio web (index.html, JS, CSS, imágenes)
```

## Qué hace `main.tf`

1. Descarga la imagen `floci/floci` y levanta el contenedor `floci` en el puerto **4566**.
2. Espera a que Floci responda.
3. Configura el proveedor de AWS para que apunte a Floci (`http://localhost:4566`) con credenciales falsas.
4. Crea el bucket `consultorio-ronconi`, lo hace público y lo configura como sitio web
   (`index.html` como página principal).
5. Sube **todos** los archivos de `sitio/` con su tipo MIME correcto (html, js, css, jpg, png…).

## Cómo ejecutarlo

Requisitos: Docker Engine y Terraform.

```bash
terraform init
terraform apply
```

Abrir en el navegador: **http://localhost:4566/consultorio-ronconi/index.html**

## Verificación

```bash
docker ps --filter name=floci                                   # contenedor corriendo
curl -I http://localhost:4566/consultorio-ronconi/index.html    # HTTP/1.1 200 OK
terraform output cantidad_archivos                               # archivos subidos
```

## Borrar todo

```bash
terraform destroy
```
