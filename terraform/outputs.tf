output "s3_bucket_name" {
  description = "Name of the pipeline S3 bucket"
  value       = aws_s3_bucket.pipeline.bucket
}

output "dynamodb_table_daily_genre_kpis" {
  description = "Table name for scalar genre KPIs"
  value       = aws_dynamodb_table.daily_genre_kpis.name
}

output "dynamodb_table_top_songs_per_genre" {
  description = "Table name for top-3 songs per genre per day"
  value       = aws_dynamodb_table.top_songs_per_genre.name
}

output "dynamodb_table_top_genres_per_day" {
  description = "Table name for top-5 genres per day"
  value       = aws_dynamodb_table.top_genres_per_day.name
}

output "glue_job_validate" {
  description = "Name of the validate_streams Glue job"
  value       = aws_glue_job.validate_streams.name
}

output "glue_job_transform" {
  description = "Name of the transform_kpis Glue job"
  value       = aws_glue_job.transform_kpis.name
}

output "glue_job_load" {
  description = "Name of the load_dynamodb Glue job"
  value       = aws_glue_job.load_dynamodb.name
}

output "glue_role_arn" {
  description = "IAM role ARN assumed by all three Glue jobs"
  value       = aws_iam_role.glue.arn
}

output "step_functions_role_arn" {
  description = "IAM role ARN assumed by the Step Functions state machine"
  value       = aws_iam_role.step_functions.arn
}

output "eventbridge_role_arn" {
  description = "IAM role ARN assumed by the EventBridge rule"
  value       = aws_iam_role.eventbridge.arn
}

output "state_machine_arn" {
  description = "ARN of the Step Functions state machine"
  value       = aws_sfn_state_machine.pipeline.arn
}

output "eventbridge_rule_name" {
  description = "Name of the EventBridge rule watching raw/streams/"
  value       = aws_cloudwatch_event_rule.s3_put.name
}
