
#Set Variables
variable "AZDO_GITHUB_SERVICE_CONNECTION_PAT" {
  type = string
  sensitive = true
}

variable "AZDO_ORG_SERVICE_URL" {
  type = string
}

variable "AZP_URL" {
  type = string
}

variable "AZP_TOKEN" {
  type      = string
  sensitive = true
}

variable "AZP_POOL" {
  type = string
}

variable "GITHUB_REPO_NAME" {
  type = string
}

variable "GITHUB_REPO_BRANCH" {
  type = string
  default = "main"
}

variable "GITHUB_AZURE_PIPELINE_PATH" {
  type = string
  default = "azure-pipelines.yml"
}

variable "PIPELINE_NAMESPACE" {
  type = string
  default = "ado-openshift"
}

variable "BUILD_NAMESPACE" {
  type = string
  default = "azure-build"
}

variable "BUILD_SERVICEACCOUNT_NAME" {
  type = string
  default = "azure-build-agent-openshift-sa"
}

variable "PIPELINE_SERVICEACCOUNT_NAME" {
  type = string
  default = "azure-sa"
}

variable "PIPELINE_SECRETNAME" {
  type = string
  default = "azure-sa-devops-secret"
}

variable "IMAGEREGISTRY_ROUTE_NAME" {
  type = string
  default = "default-route"
}

variable "IMAGEREGISTRY_ROUTE_NAMESPACE" {
  type = string
  default = "openshift-image-registry"
}

#Create Azure Agent Build via Helm on OCP
resource "helm_release" "azure-build-agent-openshift" {
  name             = "azure-build-agent-openshift"
  chart            = "../../charts/azure-build-agent-openshift"
  create_namespace = "true"
  namespace        = "${var.BUILD_NAMESPACE}"
  wait = "true"

  set {
    name  = "azp_url"
    value = var.AZP_URL
  }

  set {
    name  = "azp_token"
    value = var.AZP_TOKEN
  }

  set {
    name  = "azp_pool"
    value = var.AZP_POOL
  }

  set {
    name = "serviceAccount.name"
    value = var.BUILD_SERVICEACCOUNT_NAME
  }


}

#Create Azure Resources Pipeline will deploy into on OCP via Helm

resource "helm_release" "azure-pipeline" {
  depends_on = [helm_release.azure-build-agent-openshift]
  name             = "azure-devops-pipeline"
  chart            = "../../charts/azure-devops-pipeline"
  create_namespace = "true"
  namespace        = "${var.PIPELINE_NAMESPACE}"
  wait = "true"

  set {
    name = "serviceAccount.name"
    value = var.PIPELINE_SERVICEACCOUNT_NAME
  }

  set {
    name = "serviceAccount.secretname"
    value = var.PIPELINE_SECRETNAME
  }

  set {
    name = "buildNamespace"
    value = var.BUILD_NAMESPACE
  }

  set {
    name = "deploy_arogcd_app"
    value = "true"
  }

  set {
    name = "github_repo_devops"
    value = var.GITHUB_REPO_NAME
  }

  set {
    name = "github_repo_devops_ref"
    value = var.GITHUB_REPO_BRANCH
  }
  
}

#Get ImageRegistry Route(Will move to providers in the next version)

data "external" "imageregistry_route" {
  program = ["bash", "../../scripts/get-default-hostname.sh"]

  query = {
    namespace = var.IMAGEREGISTRY_ROUTE_NAMESPACE
    routename = var.IMAGEREGISTRY_ROUTE_NAME
  }
}

#Get Secret(Will move to providers in the next version)

data "external" "sa_secret" {
  depends_on = [helm_release.azure-pipeline]
  program = ["bash", "../../scripts/get-secret-token.sh"]

  query = {
    namespace = var.PIPELINE_NAMESPACE
    secretname = var.PIPELINE_SECRETNAME
  }
}

#Get Cluster Server Address(Will move to providers in the next version)

data "external" "server_url" {
  depends_on = [helm_release.azure-pipeline]
  program = ["bash", "../../scripts/get-server-info.sh"]

}

# Create an Azure DevOps Project

resource "azuredevops_project" "azure-devops-pipeline" {
  name       = "AzureDevOpsPipeline"
  visibility = "private"
}

#Create a Registry Service Connection

resource "azuredevops_serviceendpoint_dockerregistry" "openshift-registry" {
  project_id            = azuredevops_project.azure-devops-pipeline.id
  service_endpoint_name = "container-registry-connection"  
  docker_registry = chomp(format("%s://%s","https",base64decode(data.external.imageregistry_route.result.encoded_route)))
  docker_username            = "${var.PIPELINE_SERVICEACCOUNT_NAME}"
  docker_password            = base64decode(data.external.sa_secret.result.encoded_secret)
  registry_type = "Others"
  description = "Registry Service Connection"
}

#Create an OpenShift Cluster Service Connection

resource "azuredevops_serviceendpoint_kubernetes" "openshift-service-endpoint" {
  project_id            = azuredevops_project.azure-devops-pipeline.id
  service_endpoint_name = "openshift"
  apiserver_url         = chomp(base64decode(data.external.server_url.result.encoded_apiserver))
  authorization_type    = "ServiceAccount"

  service_account {
    token   = data.external.sa_secret.result.encoded_secret
    ca_cert = data.external.sa_secret.result.encoded_ca
  } 
}

#Create an Azure DevOps GitOps Connection

resource "azuredevops_serviceendpoint_github" "gitops-connection" {
  project_id            = azuredevops_project.azure-devops-pipeline.id
  service_endpoint_name = "GitOps Connection"
  auth_personal {
    personal_access_token = var.AZDO_GITHUB_SERVICE_CONNECTION_PAT
  }
}

resource "azuredevops_git_repository" "github_repo_devops" {
  project_id = azuredevops_project.azure-devops-pipeline.id
  name       = "Github DevOps Repository"
  initialization {
    init_type   = "Import"
    source_type = "Git"
    source_url  = chomp(format("%s://%s","https://github.com",var.GITHUB_REPO_NAME))
  }
}

# Create an Azure DevOps Build Definition Connection

resource "azuredevops_build_definition" "azuredevops_build_definition" {
  project_id = azuredevops_project.azure-devops-pipeline.id
  name       = "OpenShift Pipeline Example2"

  repository {
    repo_type             = "GitHub"
    repo_id               = var.GITHUB_REPO_NAME
    branch_name           = var.GITHUB_REPO_BRANCH
    yml_path              = var.GITHUB_AZURE_PIPELINE_PATH
    service_connection_id = azuredevops_serviceendpoint_github.gitops-connection.id
  }
}

# Create an Azure Agent Pool Definition Connection

resource "azuredevops_agent_pool" "azuredevops_agent_pool" {
  name           = var.AZP_POOL
  auto_provision = false
  auto_update    = false
}

# Create an Azure DevOps Agent Queue Connection

resource "azuredevops_agent_queue" "azuredevops_agent_queue" {
  project_id    = azuredevops_project.azure-devops-pipeline.id
  agent_pool_id = azuredevops_agent_pool.azuredevops_agent_pool.id
}

# Authorize Azure DevOps Pipeline to use Agent Queue

resource "azuredevops_pipeline_authorization" "azuredevops_pipeline_authorization_queue" {
  project_id  = azuredevops_project.azure-devops-pipeline.id
  resource_id = azuredevops_agent_queue.azuredevops_agent_queue.id
  type        = "queue"
  pipeline_id = azuredevops_build_definition.azuredevops_build_definition.id
}

# Authorize Azure DevOps Pipeline to use GitOps Connection

resource "azuredevops_pipeline_authorization" "azuredevops_pipeline_authorization_endpoint_gitops" {
  project_id  = azuredevops_project.azure-devops-pipeline.id
  resource_id = azuredevops_serviceendpoint_github.gitops-connection.id
  type        = "endpoint"
  pipeline_id = azuredevops_build_definition.azuredevops_build_definition.id
}

# Authorize Azure DevOps Pipeline to use OpenShift Registry Connection

resource "azuredevops_pipeline_authorization" "azuredevops_pipeline_authorization_endpoint_registry" {
  project_id  = azuredevops_project.azure-devops-pipeline.id
  resource_id = azuredevops_serviceendpoint_dockerregistry.openshift-registry.id
  type        = "endpoint"
  pipeline_id = azuredevops_build_definition.azuredevops_build_definition.id
}

# Authorize Azure DevOps Pipeline to use OpenShift Connection

resource "azuredevops_pipeline_authorization" "azuredevops_pipeline_authorization_endpoint_openshift" {
  project_id  = azuredevops_project.azure-devops-pipeline.id
  resource_id = azuredevops_serviceendpoint_kubernetes.openshift-service-endpoint.id
  type        = "endpoint"
  pipeline_id = azuredevops_build_definition.azuredevops_build_definition.id
}

# Create an IncomingWebHook

resource "azuredevops_serviceendpoint_incomingwebhook" "github-webhook" {
  project_id            = azuredevops_project.azure-devops-pipeline.id
  webhook_name          = "github-webhook"
  secret                = "secret"
  http_header           = "X-Hub-Signature"
  service_endpoint_name = "Example IncomingWebhook"
  description           = "Managed by Terraform"
}