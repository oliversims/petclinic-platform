# =============================================================================
# terraform/modules/rds/outputs.tf
# Purpose: Endpoint and database name for the app JDBC URL.
#
# Linked: environments/{dev,prod}/outputs.tf; helm-values SPRING_DATASOURCE_URL.
# =============================================================================

# -----------------------------------------------------------------------------
# 1) Connection - hostname, port, and shared database name
# -----------------------------------------------------------------------------

output "endpoint" {
  description = "RDS endpoint hostname."
  value       = aws_db_instance.this.address
}

output "port" {
  description = "RDS port."
  value       = aws_db_instance.this.port
}

output "database_name" {
  description = "Shared database name (petclinic)."
  value       = aws_db_instance.this.db_name
}
