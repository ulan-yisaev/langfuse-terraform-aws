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

# Add fallback mechanism for load balancer discovery
data "aws_lbs" "all_lbs" {
  depends_on = [
    time_sleep.wait_for_lb_creation
  ]
}

locals {
  # Determine if we need to use the fallback method
  use_lb_name_fallback = length(data.aws_lbs.all_lbs.arns) > 0 && !var.disable_lb_fallback

  # Logic for fallback to find the load balancer
  fallback_lb_details = local.use_lb_name_fallback ? {
    for lb_arn in data.aws_lbs.all_lbs.arns : lb_arn => {
      name    = element(split("/", lb_arn), 2)
      arn     = lb_arn
      dns_name = data.aws_lb.fallback[lb_arn].dns_name
      zone_id  = data.aws_lb.fallback[lb_arn].zone_id
    }
  } : {}

  # Choose the first LB with a name that contains the cluster name if fallback is needed
  chosen_lb_key = local.use_lb_name_fallback ? [
    for k, v in local.fallback_lb_details : k
    if contains([for substring in [var.name, "k8s"] : contains(lower(v.name), lower(substring))], true)
  ][0] : null

  # Final values to use for Route53 record
  load_balancer_dns_name = try(data.aws_lb.ingress.dns_name, local.use_lb_name_fallback ? local.fallback_lb_details[local.chosen_lb_key].dns_name : null)
  load_balancer_zone_id  = try(data.aws_lb.ingress.zone_id, local.use_lb_name_fallback ? local.fallback_lb_details[local.chosen_lb_key].zone_id : null)
}

# Fallback method to get individual load balancer details
data "aws_lb" "fallback" {
  for_each = local.use_lb_name_fallback ? toset(data.aws_lbs.all_lbs.arns) : []
  arn      = each.key
}

# Get the ALB details
data "aws_lb" "ingress" {
  tags = {
    "elbv2.k8s.aws/cluster" = var.name
    # More flexible matching - don't specify exact stack name which may vary depending on the helm release
    # "ingress.k8s.aws/stack"    = "langfuse/langfuse" 
    "ingress.k8s.aws/resource" = "LoadBalancer"
  }

  depends_on = [
    helm_release.aws_load_balancer_controller,
    helm_release.langfuse,
    # Add time_sleep to ensure ALB is fully created and tagged
    time_sleep.wait_for_lb_creation
  ]
}

# Add a delay to ensure AWS Load Balancer Controller has time to create and tag the load balancer
resource "time_sleep" "wait_for_lb_creation" {
  depends_on = [
    helm_release.aws_load_balancer_controller,
    helm_release.langfuse,
    aws_eks_fargate_profile.coredns
  ]

  # Wait for 3 minutes to ensure the load balancer is created and tagged
  create_duration = "3m"
}

# Create Route53 record for the ALB
resource "aws_route53_record" "langfuse_app_alias" {
  zone_id = data.aws_route53_zone.selected_hosted_zone.zone_id
  name    = var.domain
  type    = "A"

  alias {
    name                   = local.load_balancer_dns_name
    zone_id                = local.load_balancer_zone_id
    evaluate_target_health = true
  }

  depends_on = [
    time_sleep.wait_for_lb_creation
  ]
}
