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

# --- REMOVED ACM Certificate Resources ---
# Certificate creation and validation removed to simplify deployment
# TODO: Re-introduce ACM certificate management and HTTPS once validation issues in private zones are resolved
# or an alternative certificate strategy (e.g., existing wildcard, Private CA) is implemented.
# Currently, the ALB will be HTTP only.

# --- ALB Lookup and Alias Record ---

resource "time_sleep" "wait_for_lb_tagging" {
  depends_on = [
    helm_release.aws_load_balancer_controller,
    helm_release.langfuse
  ]
  create_duration = "120s" // Wait for ALB to be created and tagged by LBC
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
