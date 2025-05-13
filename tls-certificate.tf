# Use existing Route53 zone instead of creating a new one
data "aws_route53_zone" "selected_hosted_zone" {
  name         = var.target_route53_zone_name
  private_zone = true
}

locals {
  # Determine ACM certificate ARN: use existing if provided, otherwise create a new one.
  acm_certificate_arn_to_use = var.existing_acm_certificate_arn != null ? var.existing_acm_certificate_arn : aws_acm_certificate.cert[0].arn
  create_new_acm_cert        = var.existing_acm_certificate_arn == null
}

# ACM Certificate for the domain
resource "aws_acm_certificate" "cert" {
  count             = local.create_new_acm_cert ? 1 : 0
  domain_name       = var.domain
  validation_method = "DNS"

  tags = {
    Name = local.tag_name
  }

  lifecycle {
    create_before_destroy = true
  }
}

# Create DNS records for certificate validation
resource "aws_route53_record" "cert_validation" {
  # Only create validation records if a new cert is being created
  for_each = local.create_new_acm_cert ? {
    for dvo in aws_acm_certificate.cert[0].domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  } : {}

  allow_overwrite = true
  name            = each.value.name
  records         = [each.value.record]
  ttl             = 60
  type            = each.value.type
  zone_id         = data.aws_route53_zone.selected_hosted_zone.zone_id
}

# ACM certificate validation doesn't work with private Route 53 zones
resource "aws_acm_certificate_validation" "cert_validation_resource" {
 count = local.create_new_acm_cert && !var.disable_certificate_validation ? 1 : 0

 certificate_arn         = aws_acm_certificate.cert[0].arn
 validation_record_fqdns = [for record in aws_route53_record.cert_validation : record.fqdn]
}

# Get the ALB details
data "aws_lb" "ingress" {
  tags = {
    "elbv2.k8s.aws/cluster"    = var.name
    "ingress.k8s.aws/stack"    = "langfuse/langfuse"
    "ingress.k8s.aws/resource" = "LoadBalancer"
  }

  depends_on = [
    helm_release.aws_load_balancer_controller,
    helm_release.langfuse
  ]
}

# Create Route53 record for the ALB
resource "aws_route53_record" "langfuse_app_alias" {
  zone_id = data.aws_route53_zone.selected_hosted_zone.zone_id
  name    = var.domain
  type    = "A"

  alias {
    name                   = data.aws_lb.ingress.dns_name
    zone_id                = data.aws_lb.ingress.zone_id
    evaluate_target_health = true
  }
}
