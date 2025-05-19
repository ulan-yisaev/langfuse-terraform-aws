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

# Create the Clickhouse PVs for Fargate with static provisioning
resource "kubernetes_persistent_volume" "clickhouse_data" {
  count = var.clickhouse_instance_count

  metadata {
    name = "${var.helm_release_name != null ? var.helm_release_name : "langfuse"}-clickhouse-data-${count.index}"
  }

  spec {
    capacity = {
      storage = "8Gi"
    }
    volume_mode                      = "Filesystem"
    access_modes                     = ["ReadWriteOnce"]
    persistent_volume_reclaim_policy = "Retain"
    storage_class_name               = kubernetes_storage_class.efs.metadata[0].name
    persistent_volume_source {
      csi {
        driver        = "efs.csi.aws.com"
        volume_handle = "${aws_efs_file_system.langfuse.id}::${aws_efs_access_point.clickhouse[count.index].id}"
        volume_attributes = {
          # No need for additional attributes with static provisioning
        }
      }
    }
    claim_ref {
      name      = "data-${var.helm_release_name != null ? var.helm_release_name : "langfuse"}-clickhouse-shard0-${count.index}"
      namespace = var.kubernetes_namespace
    }
  }

  depends_on = [
    kubernetes_storage_class.efs,
    aws_efs_access_point.clickhouse,
  ]
}

resource "kubernetes_persistent_volume" "clickhouse_zookeeper" {
  count = var.clickhouse_instance_count

  metadata {
    name = "${var.helm_release_name != null ? var.helm_release_name : "langfuse"}-zookeeper-data-${count.index}"
  }

  spec {
    capacity = {
      storage = "8Gi"
    }
    volume_mode                      = "Filesystem"
    access_modes                     = ["ReadWriteOnce"]
    persistent_volume_reclaim_policy = "Retain"
    storage_class_name               = kubernetes_storage_class.efs.metadata[0].name
    persistent_volume_source {
      csi {
        driver        = "efs.csi.aws.com"
        volume_handle = "${aws_efs_file_system.langfuse.id}::${aws_efs_access_point.zookeeper[count.index].id}"
        volume_attributes = {
          # No need for additional attributes with static provisioning
        }
      }
    }
    claim_ref {
      name      = "data-${var.helm_release_name != null ? var.helm_release_name : "langfuse"}-zookeeper-${count.index}"
      namespace = var.kubernetes_namespace
    }
  }

  depends_on = [
    kubernetes_storage_class.efs,
    aws_efs_access_point.zookeeper,
  ]
}