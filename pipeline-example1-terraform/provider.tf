terraform {
  required_providers {
    azuredevops = {
      source  = "microsoft/azuredevops"
      version = "1.4.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "2.16.1"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "2.34.0"
    }
    external = {
      source  = "hashicorp/external"
      version = "2.3.4"
    }
  }
}

# Configure the Azure DevOps provider - using environment variables from readme

#Configure Helm Provider - using environment variables from readme
# https://registry.terraform.io/providers/hashicorp/helm/latest/docs#argument-reference

#Configure Kubernetes Provider - using environment variables from readme
#https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs#argument-reference