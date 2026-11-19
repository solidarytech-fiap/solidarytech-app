output "endpoints" {
  description = "host por banco"
  value       = { for k, v in aws_db_instance.this : k => v.address }
}

output "identifiers" {
  value = { for k, v in aws_db_instance.this : k => v.identifier }
}

output "arns" {
  value = { for k, v in aws_db_instance.this : k => v.arn }
}

output "security_group_id" {
  value = aws_security_group.postgres.id
}
