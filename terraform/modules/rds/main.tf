# =============================================================================
# terraform/modules/rds/main.tf
# Purpose: MySQL in private subnets; credentials in Secrets Manager.
#
# Flow: random_password -> Secrets Manager (petclinic/{env}/rds-credentials)
# -> RDS master password. Private subnets + DB subnet group + existing RDS SG.
#
# Linked: vpc (subnets/SG), secrets/ESO, k8s ExternalSecret rds-credentials;
# called from environments/{dev,prod}/main.tf.
# =============================================================================

# -----------------------------------------------------------------------------
# 1) Locals - naming prefix; tags from provider default_tags
# -----------------------------------------------------------------------------

locals {
  name_prefix = "${var.project}-${var.environment}"

  tags = var.tags
}

# -----------------------------------------------------------------------------
# 2) Master password - RDS-safe charset (no / @ " space); avoids JDBC quote breaks
# -----------------------------------------------------------------------------

resource "random_password" "master" {
  length           = 24
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?."
}

# -----------------------------------------------------------------------------
# 3) Secrets Manager secret - petclinic/{env}/rds-credentials shell
# -----------------------------------------------------------------------------

resource "aws_secretsmanager_secret" "rds" {
  name                    = "${var.project}/${var.environment}/rds-credentials"
  description             = "RDS master credentials for ${local.name_prefix}-mysql"
  recovery_window_in_days = 0

  tags = merge(local.tags, {
    Name = "${var.project}/${var.environment}/rds-credentials"
  })
}

# -----------------------------------------------------------------------------
# 4) Secret version - username petclinic + generated password
# -----------------------------------------------------------------------------

resource "aws_secretsmanager_secret_version" "rds" {
  secret_id = aws_secretsmanager_secret.rds.id
  secret_string = jsonencode({
    username = "petclinic"
    password = random_password.master.result
  })
}

# -----------------------------------------------------------------------------
# 5) DB subnet group - private subnets from the VPC module
# -----------------------------------------------------------------------------

resource "aws_db_subnet_group" "this" {
  name       = "${local.name_prefix}-db-subnet-group"
  subnet_ids = var.subnet_ids

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-db-subnet-group"
  })
}

# -----------------------------------------------------------------------------
# 6) Parameter group - utf8mb4 / unicode collation
# -----------------------------------------------------------------------------

resource "aws_db_parameter_group" "this" {
  name   = "${local.name_prefix}-mysql-params"
  family = "mysql8.0"

  parameter {
    name  = "character_set_server"
    value = "utf8mb4"
  }

  parameter {
    name  = "collation_server"
    value = "utf8mb4_unicode_ci"
  }

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-mysql-params"
  })
}

# -----------------------------------------------------------------------------
# 7) RDS instance - single shared petclinic MySQL database
# -----------------------------------------------------------------------------

resource "aws_db_instance" "this" {
  identifier                 = "${local.name_prefix}-mysql"
  engine                     = "mysql"
  engine_version             = var.engine_version
  auto_minor_version_upgrade = false
  instance_class             = var.instance_class
  db_name                    = "petclinic"
  username                   = "petclinic"
  password                   = random_password.master.result
  allocated_storage          = var.allocated_storage
  max_allocated_storage      = var.max_allocated_storage
  storage_type               = "gp3"
  storage_encrypted          = true
  db_subnet_group_name       = aws_db_subnet_group.this.name
  parameter_group_name       = aws_db_parameter_group.this.name
  vpc_security_group_ids     = [var.security_group_id]
  publicly_accessible        = false
  port                       = 3306
  multi_az                   = var.multi_az
  backup_retention_period    = var.backup_retention_period
  skip_final_snapshot        = var.skip_final_snapshot
  final_snapshot_identifier  = var.skip_final_snapshot ? null : "${local.name_prefix}-mysql-final"
  deletion_protection        = var.deletion_protection

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-mysql"
  })
}
