terraform {
  required_version = ">=1.0.0"
  /*
  backend "s3" {
    bucket = "backend-test-jm"
    key    = "prod/state"
    region = "us-east-1"
  } 

  backend "local" {
    path = "terraform.tfstate"
  } */

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 4.0"
    }
    // all provider syntax can be found on the terraform.io registry
    http = {
      source  = "hashicorp/http"
      version = "~> 3.0"
    }

    // this was referenced previously in the main.tf file so this provider was probably already installed using the default/latest version
    // best practice to require and specify a specific version
    // can use init -upgrade to downgrade as well
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }

    // used to create local files where terraform is run
    local = {
      source  = "hashicorp/local"
      version = "~> 2.0"
    }

    tls = {
      source  = "hashicorp/tls"
      version = "~> 3.1.0"
    }

  }
}