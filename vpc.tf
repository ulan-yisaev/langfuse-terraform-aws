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

# Remove all VPC Endpoint resources - they are assumed to exist in the target VPC
# Removed:
# - resource "aws_vpc_endpoint" "sts" { ... }
# - resource "aws_vpc_endpoint" "s3" { ... }
# - resource "aws_security_group" "vpc_endpoints" { ... }
