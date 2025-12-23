variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "schedule_name" {
  type    = string
  default = "invoke-lambda-every-30m"
}
variable "lambda_name"  {
    type = string
    default = "get-post-job"
}

variable "secrets_id"   {
    type = string
    default = ""
}

variable "api_get_url" {
    type = string
    default = "https://jsonplaceholder.typicode.com/posts/1"
}

variable "api_post_url" {
    type = string
    default = "https://jsonplaceholder.typicode.com/posts"
}