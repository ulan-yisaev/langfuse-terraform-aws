output "cluster_name" {
  description = "EKS Cluster Name to use for a Kubernetes terraform provider"
  value       = aws_eks_cluster.langfuse.name
}

output "cluster_host" {
  description = "EKS Cluster host to use for a Kubernetes terraform provider"
  value       = aws_eks_cluster.langfuse.endpoint
}

output "cluster_ca_certificate" {
  description = "EKS Cluster CA certificate to use for a Kubernetes terraform provider"
  value       = base64decode(aws_eks_cluster.langfuse.certificate_authority[0].data)
  sensitive   = true
}

output "cluster_token" {
  description = "EKS Cluster Token to use for a Kubernetes terraform provider"
  value       = data.aws_eks_cluster_auth.langfuse.token
  sensitive   = true
}

output "route53_nameservers" {
  description = "Nameserver for the Route53 zone"
  value       = data.aws_route53_zone.selected_hosted_zone.name_servers
}

output "langfuse_kubernetes_secret_name" {
  description = "Name of the Kubernetes secret holding Langfuse credentials."
  value       = kubernetes_secret.langfuse.metadata[0].name
}

output "langfuse_kubernetes_secret_namespace" {
  description = "Namespace of the Kubernetes secret."
  value       = kubernetes_secret.langfuse.metadata[0].namespace
}
