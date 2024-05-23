terraform {
  backend "s3" {

    bucket = "security-observability-microservice-bucket"
    key    = "devsecops/terraform.tfstate"
    region = "us-east-2"

    dynamodb_table = "terraform-backend-locks"
  }
}