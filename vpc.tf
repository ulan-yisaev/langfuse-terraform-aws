# Get information about the existing VPC and subnets instead of creating new ones
data "aws_vpc" "selected_vpc_data" {
  id = var.existing_vpc_id
}

# Helper data source to get full details of each provided subnet ID
data "aws_subnet" "selected_private_subnets_details" {
  for_each = toset(var.existing_private_subnet_ids)
  id       = each.value
}

data "aws_subnet" "selected_public_subnets_details" {
  for_each = length(var.existing_public_subnet_ids) > 0 ? toset(var.existing_public_subnet_ids) : toset([])
  id       = each.value
}

data "aws_region" "current" {}

locals {
  # This 'vpc_config' local is the key. Other files will reference its attributes.
  # The attribute names (vpc_id, private_subnets, etc.) are chosen to match
  # the output names of the original 'terraform-aws-modules/vpc/aws' module.
  vpc_config = {
    vpc_id          = data.aws_vpc.selected_vpc_data.id
    vpc_cidr_block  = data.aws_vpc.selected_vpc_data.cidr_block
    private_subnets = var.existing_private_subnet_ids
    public_subnets  = var.existing_public_subnet_ids

    # Fetching route table IDs associated with the private subnets.
    # This assumes each private subnet has an explicitly associated route table.
    private_route_table_ids = []
    # private_route_table_ids = [
    #   for s in data.aws_subnet.selected_private_subnets_details :
    #   s.route_table_id != null ? s.route_table_id : null
    # ]

    azs = distinct([for s in data.aws_subnet.selected_private_subnets_details : s.availability_zone])
  }
}

resource "aws_security_group" "vpc_endpoints_sg" { # Renamed to avoid conflict if original was "vpc_endpoints"
  name        = "${var.name}-vpc-endpoints-sg" // var.name is the Langfuse deployment name
  description = "Security group for VPC interface endpoints used by Langfuse EKS"
  vpc_id      = local.vpc_config.vpc_id // Uses the existing VPC ID

  ingress {
    description = "Allow HTTPS from VPC CIDR"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [local.vpc_config.vpc_cidr_block] // Allow from within the VPC
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${local.tag_name} VPC Endpoints SG" // local.tag_name from module's locals.tf
  }
}

resource "aws_vpc_endpoint" "sts" {
  vpc_id              = local.vpc_config.vpc_id
  service_name        = "com.amazonaws.${data.aws_region.current.name}.sts"
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = true
  subnet_ids          = local.vpc_config.private_subnets // Place endpoint ENIs in your private subnets

  security_group_ids = [
    aws_security_group.vpc_endpoints_sg.id,
    // You might also need to allow traffic from the EKS cluster security group
    // if specific pod-to-endpoint SG rules are more restrictive.
    // For STS, typically allowing from the VPC CIDR to the endpoint SG on 443 is enough.
  ]

  tags = {
    Name = "${local.tag_name} STS VPC Endpoint"
  }
}
# Remove all other VPC Endpoint resources - they are assumed to exist in the target VPC
# Removed:
# - resource "aws_vpc_endpoint" "s3" { ... }
