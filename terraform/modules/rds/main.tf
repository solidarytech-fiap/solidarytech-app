# Uma instancia PostgreSQL por servico (database-per-service).
# Subnets privadas, sem acesso publico, criptografado, com backup automatico
# (PITR) -> base do RPO definido no PCN.

resource "aws_db_subnet_group" "this" {
  name       = "${var.name}-db-subnets"
  subnet_ids = var.subnet_ids
  tags       = { Name = "${var.name}-db-subnets" }
}

resource "aws_security_group" "postgres" {
  name        = "${var.name}-postgres-sg"
  description = "PostgreSQL acessivel apenas de dentro da VPC (pods EKS)"
  vpc_id      = var.vpc_id

  ingress {
    description = "PostgreSQL a partir da VPC"
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr_block]
  }

  egress {
    description = "Saida restrita a VPC"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [var.vpc_cidr_block]
  }

  tags = { Name = "${var.name}-postgres-sg" }
}

resource "aws_db_parameter_group" "postgres" {
  name   = "${var.name}-pg16"
  family = "postgres16"

  # Forca TLS nas conexoes.
  parameter {
    name  = "rds.force_ssl"
    value = "1"
  }
  # Loga queries lentas (> 500ms) - apoio ao diagnostico (MTTR).
  parameter {
    name  = "log_min_duration_statement"
    value = "500"
  }
}

resource "aws_db_instance" "this" {
  for_each = var.databases

  identifier     = "${var.name}-${each.key}"
  engine         = "postgres"
  engine_version = var.engine_version
  instance_class = var.instance_class

  allocated_storage     = var.allocated_storage
  max_allocated_storage = var.max_allocated_storage
  storage_type          = "gp3"
  storage_encrypted     = true

  db_name  = each.value.db_name
  username = var.credentials[each.key].username
  password = var.credentials[each.key].password
  port     = 5432

  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = [aws_security_group.postgres.id]
  parameter_group_name   = aws_db_parameter_group.postgres.name
  publicly_accessible    = false
  multi_az               = var.multi_az

  backup_retention_period  = var.backup_retention_period
  backup_window            = "06:00-07:00"
  maintenance_window       = "sun:07:30-sun:08:30"
  copy_tags_to_snapshot    = true
  delete_automated_backups = false

  auto_minor_version_upgrade = true
  apply_immediately          = true
  deletion_protection        = var.deletion_protection
  skip_final_snapshot        = var.skip_final_snapshot
  final_snapshot_identifier  = var.skip_final_snapshot ? null : "${var.name}-${each.key}-final"

  # Logs do postgres para o CloudWatch (apoia diagnostico; reduz MTTR).
  enabled_cloudwatch_logs_exports = ["postgresql"]

  performance_insights_enabled = false
  monitoring_interval          = 0

  tags = {
    Name               = "${var.name}-${each.key}"
    Service            = each.value.service
    DataClassification = each.value.data_classification
  }
}
