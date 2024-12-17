terraform {
  backend "s3" {
    bucket = "my-anon-bucket" # Replace with your bucket name
    key    = "terraform.tfstate"
    region = "us-west-1" # Replace with your AWS region
  }
}