terraform {
  backend "s3" {
    bucket       = "terraform-states-816290781811-eu-south-2-an"
    key          = "ZeroInfra/terraform.tfstate"
    region       = "eu-south-2"
    encrypt      = true
    use_lockfile = true
  }
}