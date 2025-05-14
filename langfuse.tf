locals {
  # Convert the list of private subnet IDs to a comma-separated string for the annotation
  subnet_ids_for_alb_annotation = join(",", var.existing_private_subnet_ids)
  inbound_cidrs_annotation_value = join(",", var.loadbalancer_inbound_cidrs)

  langfuse_values = <<EOT
global:
  defaultStorageClass: efs
langfuse:
  salt:
    secretKeyRef:
      name: langfuse
      key: salt
  nextauth:
    url: "http://${var.domain}"
    secret:
      secretKeyRef:
        name: langfuse
        key: nextauth-secret
  serviceAccount:
    annotations:
      eks.amazonaws.com/role-arn: ${aws_iam_role.langfuse_irsa.arn}
  # The Web container needs slightly increased initial grace period on Fargate
  web:
    livenessProbe:
      initialDelaySeconds: 60
    readinessProbe:
      initialDelaySeconds: 60
postgresql:
  deploy: false
  host: ${aws_rds_cluster.postgres.endpoint}:5432
  auth:
    username: langfuse
    database: langfuse
    existingSecret: langfuse
    secretKeys:
      userPasswordKey: postgres-password
clickhouse:
  auth:
    existingSecret: langfuse
    existingSecretKey: clickhouse-password
redis:
  deploy: false
  host: ${aws_elasticache_replication_group.redis.primary_endpoint_address}
  auth:
    existingSecret: langfuse
    existingSecretPasswordKey: redis-password
  tls:
    enabled: true
s3:
  deploy: false
  bucket: ${aws_s3_bucket.langfuse.id}
  region: ${data.aws_region.current.name}
  forcePathStyle: false
  eventUpload:
    prefix: "events/"
  batchExport:
    prefix: "exports/"
  mediaUpload:
    prefix: "media/"
EOT

  ingress_values = <<EOT
langfuse:
  ingress:
    enabled: true
    className: alb
    annotations:
      alb.ingress.kubernetes.io/scheme: internal
      alb.ingress.kubernetes.io/target-type: 'ip'
      # Configure for HTTP only
      alb.ingress.kubernetes.io/listen-ports: '[{"HTTP":80}]'
      # Explicitly specify subnets to use for the ALB
      alb.ingress.kubernetes.io/subnets: "${local.subnet_ids_for_alb_annotation}"
      ${length(var.loadbalancer_inbound_cidrs) > 0 && var.loadbalancer_inbound_cidrs[0] != "0.0.0.0/0" ? "alb.ingress.kubernetes.io/inbound-cidrs: \"${local.inbound_cidrs_annotation_value}\"" : ""}
    hosts:
    - host: ${var.domain}
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: ${var.helm_release_name != null ? var.helm_release_name : "langfuse"}-web
            port:
              number: 3000
EOT

  encryption_values = var.use_encryption_key == false ? "" : <<EOT
langfuse:
  encryptionKey:
    secretKeyRef:
      name: ${kubernetes_secret.langfuse.metadata[0].name}
      key: encryption_key
EOT
}

resource "kubernetes_namespace" "langfuse" {
  metadata {
    name = "langfuse"
  }
}

resource "random_bytes" "salt" {
  # Should be at least 256 bits (32 bytes): https://langfuse.com/self-hosting/configuration#core-infrastructure-settings ~> SALT
  length = 32
}

resource "random_bytes" "nextauth_secret" {
  # Should be at least 256 bits (32 bytes): https://langfuse.com/self-hosting/configuration#core-infrastructure-settings ~> NEXTAUTH_SECRET
  length = 32
}

resource "random_bytes" "encryption_key" {
  count = var.use_encryption_key ? 1 : 0
  # Must be exactly 256 bits (32 bytes): https://langfuse.com/self-hosting/configuration#core-infrastructure-settings ~> ENCRYPTION_KEY
  length = 32
}

resource "kubernetes_secret" "langfuse" {
  metadata {
    name      = "langfuse"
    namespace = "langfuse"
  }

  data = {
    "redis-password"      = random_password.redis_password.result
    "postgres-password"   = random_password.postgres_password.result
    "salt"                = random_bytes.salt.base64
    "nextauth-secret"     = random_bytes.nextauth_secret.base64
    "clickhouse-password" = random_password.clickhouse_password.result
    "encryption_key"      = var.use_encryption_key ? random_bytes.encryption_key[0].hex : ""
  }
}

resource "helm_release" "langfuse" {
  name       = var.helm_release_name != null ? var.helm_release_name : "langfuse"
  repository       = "https://langfuse.github.io/langfuse-k8s"
  version          = "1.1.0"
  chart            = "langfuse"
  namespace        = "langfuse"
  create_namespace = true
  
  # Apply configuration from var.helm_release_config
  timeout = lookup(var.helm_release_config, "timeout", 300)
  wait    = lookup(var.helm_release_config, "wait", true)

  values = compact(concat(
    [local.langfuse_values],
    [local.ingress_values],
    var.use_encryption_key ? [local.encryption_values] : [],
    lookup(var.helm_release_config, "values_overrides", [])
  ))

  depends_on = [
    aws_iam_role.langfuse_irsa,
    aws_iam_role_policy.langfuse_s3_access,
    aws_eks_fargate_profile.namespaces,
    kubernetes_storage_class.efs,
    kubernetes_persistent_volume.clickhouse_data,
    kubernetes_persistent_volume.clickhouse_zookeeper
  ]
}
