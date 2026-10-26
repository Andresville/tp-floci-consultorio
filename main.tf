############################################################################
# TP - Despliegue del sitio "Consultorio Dra. Ronconi" en un bucket S3
#      simulado con Floci (emulador de AWS) dentro de Docker.
#
# La carpeta ./sitio contiene el sitio ya compilado (HTML, JS, CSS, imágenes).
#
# Uso:
#   terraform init
#   terraform apply
############################################################################

terraform {
  required_providers {
    docker = {
      source  = "kreuzwerker/docker"
      version = "~> 3.0"
    }
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# --------------------------------------------------------------------------
# Variables y valores locales
# --------------------------------------------------------------------------
variable "bucket_name" {
  description = "Nombre del bucket S3 donde se publica el sitio"
  type        = string
  default     = "consultorio-ronconi"
}

variable "floci_port" {
  description = "Puerto local donde escucha Floci"
  type        = number
  default     = 4566
}

locals {
  # Carpeta con los archivos del sitio
  build_dir = "${path.module}/sitio"

  # Todos los archivos del sitio compilado (html, js, css, imágenes, fuentes...)
  site_files = fileset(local.build_dir, "**")

  # Tipo MIME según la extensión: sin esto el navegador descargaría los
  # archivos en vez de mostrarlos.
  mime_types = {
    html  = "text/html; charset=utf-8"
    css   = "text/css"
    js    = "application/javascript"
    json  = "application/json"
    map   = "application/json"
    txt   = "text/plain"
    ico   = "image/x-icon"
    png   = "image/png"
    jpg   = "image/jpeg"
    jpeg  = "image/jpeg"
    svg   = "image/svg+xml"
    webp  = "image/webp"
    woff  = "font/woff"
    woff2 = "font/woff2"
  }
}

# --------------------------------------------------------------------------
# 1. Contenedor Floci (emulador de AWS) dentro de Docker
# --------------------------------------------------------------------------
provider "docker" {}

resource "docker_image" "floci" {
  name         = "floci/floci:latest"
  keep_locally = true
}

resource "docker_container" "floci" {
  name  = "floci"
  image = docker_image.floci.image_id

  ports {
    internal = 4566
    external = var.floci_port
  }
}

# Espera a que Floci responda antes de crear el bucket
# (el contenedor tarda unos segundos en arrancar).
resource "terraform_data" "esperar_floci" {
  triggers_replace = [docker_container.floci.id]

  provisioner "local-exec" {
    command = "for i in $(seq 1 30); do curl -s -o /dev/null http://localhost:${var.floci_port} && exit 0; sleep 1; done; echo 'Floci no respondio' >&2; exit 1"
  }

  lifecycle {
    precondition {
      condition     = length(local.site_files) > 0
      error_message = "La carpeta ./sitio está vacía o no existe."
    }
  }
}

# --------------------------------------------------------------------------
# 2. Proveedor AWS apuntando a Floci (credenciales falsas)
# --------------------------------------------------------------------------
provider "aws" {
  region                      = "us-east-1"
  access_key                  = "mock"
  secret_key                  = "mock"
  skip_credentials_validation = true
  skip_metadata_api_check     = true
  skip_requesting_account_id  = true
  s3_use_path_style           = true

  endpoints {
    s3 = "http://localhost:${var.floci_port}"
  }
}

# --------------------------------------------------------------------------
# 3. Bucket S3 público configurado como sitio web
# --------------------------------------------------------------------------
resource "aws_s3_bucket" "sitio" {
  bucket        = var.bucket_name
  force_destroy = true # permite "terraform destroy" aunque tenga archivos

  depends_on = [terraform_data.esperar_floci]
}

# Floci (igual que AWS) crea los buckets con "BucketOwnerEnforced", que
# deshabilita las ACL. Lo cambiamos para poder usar "public-read".
resource "aws_s3_bucket_ownership_controls" "sitio" {
  bucket = aws_s3_bucket.sitio.id

  rule {
    object_ownership = "BucketOwnerPreferred"
  }
}

# Sacamos el bloqueo de acceso público (si no, las ACL públicas dan 403)
resource "aws_s3_bucket_public_access_block" "sitio" {
  bucket = aws_s3_bucket.sitio.id

  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}

resource "aws_s3_bucket_acl" "sitio" {
  bucket = aws_s3_bucket.sitio.id
  acl    = "public-read"

  depends_on = [
    aws_s3_bucket_ownership_controls.sitio,
    aws_s3_bucket_public_access_block.sitio,
  ]
}

# "Static website hosting": index.html como página principal y de error
resource "aws_s3_bucket_website_configuration" "sitio" {
  bucket = aws_s3_bucket.sitio.id

  index_document {
    suffix = "index.html"
  }

  error_document {
    key = "index.html"
  }
}

# --------------------------------------------------------------------------
# 4. Subida de TODOS los archivos de ./sitio al bucket
# --------------------------------------------------------------------------
resource "aws_s3_object" "archivos" {
  for_each = local.site_files

  bucket       = aws_s3_bucket.sitio.id
  key          = each.value
  source       = "${local.build_dir}/${each.value}"
  etag         = filemd5("${local.build_dir}/${each.value}") # re-sube si cambia
  content_type = lookup(local.mime_types, lower(reverse(split(".", each.value))[0]), "application/octet-stream")
  acl          = "public-read"

  depends_on = [aws_s3_bucket_acl.sitio]
}

# --------------------------------------------------------------------------
# Salidas
# --------------------------------------------------------------------------
output "website_url" {
  description = "Abrí esta URL en el navegador para ver el sitio"
  value       = "http://localhost:${var.floci_port}/${aws_s3_bucket.sitio.id}/index.html"
}

output "website_hosting_url" {
  description = "Misma web usando el endpoint de 'static website hosting' de S3"
  value       = "http://${aws_s3_bucket.sitio.id}.s3-website-us-east-1.localhost:${var.floci_port}/"
}

output "cantidad_archivos" {
  description = "Cantidad de archivos subidos al bucket"
  value       = length(aws_s3_object.archivos)
}
