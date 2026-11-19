# Fila de eventos de doacao + DLQ (mensagens que falharam 5x nao se perdem).
resource "aws_sqs_queue" "dlq" {
  name                      = "${var.queue_name}-dlq"
  message_retention_seconds = 1209600 # 14 dias
  sqs_managed_sse_enabled   = true

  tags = { Service = "donation-service" }
}

resource "aws_sqs_queue" "this" {
  name                       = var.queue_name
  message_retention_seconds  = var.message_retention_seconds
  visibility_timeout_seconds = 60
  receive_wait_time_seconds  = 20 # long polling: menos requests = menos custo
  sqs_managed_sse_enabled    = true

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.dlq.arn
    maxReceiveCount     = 5
  })

  tags = { Service = "donation-service" }
}
