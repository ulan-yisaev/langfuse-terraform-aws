# Random password for ClickHouse
# Using a alphanumeric password to avoid issues with special characters on bash entrypoint
resource "random_password" "clickhouse_password" {
  length      = 64
  special     = false
  min_lower   = 1
  min_upper   = 1
  min_numeric = 1
}

# EFS Access Points for Clickhouse instances
resource "aws_efs_access_point" "clickhouse" {
  count          = var.clickhouse_instance_count
  file_system_id = aws_efs_file_system.langfuse.id

  root_directory {
    path = "/clickhouse/${count.index}"
    creation_info {
      owner_gid   = 1001
      owner_uid   = 1001
      permissions = "0755"
    }
  }

  posix_user {
    gid = 1001
    uid = 1001
  }

  tags = {
    Name = "${local.tag_name} Clickhouse"
  }
}

# EFS Access Points for Zookeeper instances
resource "aws_efs_access_point" "zookeeper" {
  count          = var.clickhouse_instance_count
  file_system_id = aws_efs_file_system.langfuse.id

  root_directory {
    path = "/zookeeper/${count.index}"
    creation_info {
      owner_gid   = 1001
      owner_uid   = 1001
      permissions = "0755"
    }
  }

  posix_user {
    gid = 1001
    uid = 1001
  }

  tags = {
    Name = "${local.tag_name} Zookeper"
  }
}