variable "name" {
  description = "Name prefix for resources"
  type        = string
  default     = "langfuse"
}

variable "domain" {
  description = "Domain name for Langfuse (e.g., langfuse.ai-test.aws.lhv.eu)"
  type        = string
}

variable "existing_vpc_id" {
  description = "The ID of the existing VPC to deploy Langfuse into."
  type        = string
}

variable "existing_private_subnet_ids" {
  description = "A list of existing private subnet IDs to use for Langfuse components."
  type        = list(string)
}

variable "existing_public_subnet_ids" {
  description = "A list of existing public subnet IDs (e.g., where NAT Gateways reside, if module logic needs this context)."
  type        = list(string)
  default     = [] // Often not directly needed by app components if NATs are just a route target
}

variable "loadbalancer_inbound_cidrs" {
  description = "List of CIDR blocks to allow access to the internal load balancer."
  type        = list(string)
  default     = ["0.0.0.0/0"] // Default to allow all if not specified, adjust as needed
}

variable "kubernetes_version" {
  description = "Kubernetes version to use for the EKS cluster"
  type        = string
  default     = "1.32"
}

variable "use_encryption_key" {
  description = "Whether to use an Encryption key for LLM API credential and integration credential store."
  type        = bool
  default     = true // Changed default to true as per general recommendation
}

variable "target_route53_zone_name" {
  description = "The name of the existing private Route53 zone (e.g., ai-test.aws.lhv.eu)."
  type        = string
  // No default, must be provided
}

variable "existing_acm_certificate_arn" {
  description = "Optional ARN of an existing ACM certificate to use for the ALB. If provided, no new certificate will be created."
  type        = string
  default     = null
}

variable "disable_certificate_validation" {
 description = "Set to true to skip waiting for ACM certificate validation (useful for private Route53 zones)"
 type        = bool
 default     = false
}

variable "helm_release_name" {
description = "Custom name for the Helm release to avoid conflicts with existing releases"
type        = string
default     = null
}

variable "helm_release_config" {
  description = "Configuration options for the Helm release (timeout, wait, values_overrides)"
  type = object({
    timeout = optional(number, 300)
    wait = optional(bool, true)
    values_overrides = optional(list(string), [])
  })
  default = {}
}

variable "disable_s3_public_access_block" {
description = "Set to true to skip creating S3 public access block (for organizations with restrictive SCPs)"
type        = bool
default     = false
}

variable "postgres_instance_count" {
  description = "Number of PostgreSQL instances to create"
  type        = number
  default     = 2 # Default to 2 instances for high availability
}

variable "postgres_min_capacity" {
  description = "Minimum ACU capacity for PostgreSQL Serverless v2"
  type        = number
  default     = 0.5
}

variable "postgres_max_capacity" {
  description = "Maximum ACU capacity for PostgreSQL Serverless v2"
  type        = number
  default     = 2.0 # Higher default for production readiness
}

variable "cache_node_type" {
  description = "ElastiCache node type"
  type        = string
  default     = "cache.t4g.small"
}

variable "cache_instance_count" {
  description = "Number of ElastiCache instances used in the cluster"
  type        = number
  default     = 2
}

variable "clickhouse_instance_count" {
  description = "Number of ClickHouse instances used in the cluster"
  type        = number
  default     = 3
}

variable "fargate_profile_namespaces" {
  description = "List of Namespaces which are created with a fargate profile"
  type        = list(string)
  default = [
    "default",
    "langfuse",
    "kube-system",
  ]
}
