# Use existing Route53 zone instead of creating a new one
data "aws_route53_zone" "selected_hosted_zone" {
  name         = var.target_route53_zone_name
  private_zone = true
}

locals {
  # Determine the expected stack tag for the load balancer
  # The Langfuse Ingress is in the "langfuse" namespace.
  # The Ingress resource name typically matches the Helm release name.
  langfuse_actual_helm_release_name = var.helm_release_name != null ? var.helm_release_name : "langfuse"
  expected_lb_stack_tag             = "langfuse/${local.langfuse_actual_helm_release_name}"
}

# ACM Certificate for the domain
resource "aws_acm_certificate" "cert" {
  domain_name       = var.domain
  validation_method = "DNS"

  options {
    certificate_transparency_logging_preference = "DISABLED"
  }

  tags = {
    Name = "${local.tag_name}-langfuse-cert"
  }

  lifecycle {
    create_before_destroy = true
  }
}

# Create DNS records for certificate validation
resource "aws_route53_record" "cert_validation" {
  for_each = {
    for dvo in aws_acm_certificate.cert.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }

  allow_overwrite = true
  name            = each.value.name
  records         = [each.value.record]
  ttl             = 60
  type            = each.value.type
  zone_id         = data.aws_route53_zone.selected_hosted_zone.zone_id
}

resource "aws_acm_certificate_validation" "cert_validation_resource" {
  certificate_arn         = aws_acm_certificate.cert.arn
  validation_record_fqdns = [for record in aws_route53_record.cert_validation : record.fqdn]

  # You might need to increase timeouts if validation in private zone is slow or problematic
  timeouts {
    create = "45m"
  }
}

# --- ALB Lookup and Alias Record ---

resource "time_sleep" "wait_for_lb_tagging" {
  depends_on = [
    helm_release.aws_load_balancer_controller,
    helm_release.langfuse,
    aws_acm_certificate_validation.cert_validation_resource
  ]
  create_duration = "120s" // Wait for ALB to be created, tagged, and for cert to be associated
}

# Get the ALB details
data "aws_lb" "ingress" {
  tags = {
    "elbv2.k8s.aws/cluster"    = var.name
    "ingress.k8s.aws/stack"    = local.expected_lb_stack_tag
    "ingress.k8s.aws/resource" = "LoadBalancer"
  }

  depends_on = [
    time_sleep.wait_for_lb_tagging
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
