# Copyright 2019 The Tranquility Base Authors
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

###
# Root module (activates other modules)
###

provider "google" {
  region  = var.region
  zone    = var.region_zone
  version = "~> 2.5"
}

provider "google" {
  alias   = "vault"
  region  = var.region
  zone    = var.region_zone
  version = "~> 2.5"
}

provider "google-beta" {
  alias   = "shared-vpc"
  region  = var.region
  zone    = var.region_zone
  project = module.shared_projects.shared_networking_id
  version = "~> 2.5"
}

provider "kubernetes" {
  alias   = "k8s"
  version = "~> 1.10.0"
}

terraform {
  backend "gcs" {
    # The bucket name below is overloaded at every run with
    # `-backend-config="bucket=${terraform_state_bucket_name}"` parameter
    # templated into the `bootstrap.sh` script 
    bucket = "terraformdevstate"
  }
}

module "folder_structure" {
  source = "../../folder-structure-creation"

  region           = var.region
  region_zone      = var.region_zone
  root_id          = var.root_id
  tb_discriminator = var.tb_discriminator
}

module "shared_projects" {
  source = "../../shared-projects-creation"

  tb_discriminator               = var.tb_discriminator
  root_id                        = module.folder_structure.shared_services_id
  billing_account_id             = var.billing_account_id
  shared_networking_project_name = var.shared_networking_project_name
  shared_secrets_project_name    = var.shared_secrets_project_name
  shared_telemetry_project_name  = var.shared_telemetry_project_name
  shared_itsm_project_name       = var.shared_itsm_project_name
  shared_billing_project_name    = var.shared_billing_project_name
  shared_bastion_project_name    = var.shared_bastion_project_name
}

module "apis_activation" {
  source = "../../apis-activation"

  ec_project_id           = module.shared_projects.shared_ec_id
  bastion_project_id      = module.shared_projects.shared_bastion_id
  host_project_id         = module.shared_projects.shared_networking_id
  service_projects_number = var.service_projects_number
  service_project_ids     = [module.shared_projects.shared_secrets_id, module.shared_projects.shared_itsm_id, module.shared_projects.shared_ec_id]
}

module "shared-vpc" {
  source = "../../shared-vpc"

  host_project_id          = module.shared_projects.shared_networking_id
  region                   = var.region
  shared_vpc_name          = var.shared_vpc_name
  standard_network_subnets = var.standard_network_subnets
  bastion_subnet_cidr      = var.bastion_subnetwork_cidr
  enable_flow_logs         = var.enable_flow_logs
  tags                     = var.tags
  gke_network_subnets      = var.gke_network_subnets
  gke_pod_network_name     = var.gke_pod_network_name
  gke_service_network_name = var.gke_service_network_name
  router_name              = var.router_name
  create_nat_gateway       = var.create_nat_gateway
  router_nat_name          = var.router_nat_name
  service_projects_number  = var.service_projects_number
  service_project_ids      = [module.shared_projects.shared_secrets_id, module.shared_projects.shared_itsm_id, module.shared_projects.shared_ec_id]
}

module "bastion-security" {
  source = "../../shared-bastion"

  region                        = var.region
  region_zone                   = var.region_zone
  shared_bastion_id             = module.shared_projects.shared_bastion_id
  shared_networking_id          = module.shared_projects.shared_networking_id
  nat_static_ip                 = module.shared-vpc.nat_static_ip
  root_id                       = var.root_id
  shared_bastion_project_number = module.shared_projects.shared_bastion_project_number
}

module "gke-ec" {
  source = "../../kubernetes-cluster-creation"

  providers = {
    google                 = google
    google-beta.shared-vpc = google-beta.shared-vpc
  }

  region               = var.region
  sharedvpc_project_id = module.shared_projects.shared_networking_id
  sharedvpc_network    = var.shared_vpc_name

  cluster_enable_private_nodes    = var.cluster_ec_enable_private_nodes
  cluster_enable_private_endpoint = var.cluster_ec_enable_private_endpoint
  cluster_project_id              = module.shared_projects.shared_ec_id
  cluster_subnetwork              = var.cluster_ec_subnetwork
  cluster_service_account         = var.cluster_ec_service_account
  cluster_name                    = var.cluster_ec_name
  cluster_pool_name               = var.cluster_ec_pool_name
  cluster_master_cidr             = var.cluster_ec_master_cidr
  cluster_master_authorized_cidrs = concat(
    var.cluster_ec_master_authorized_cidrs,
    [
      merge(
        {
          "display_name" = "initial-admin-ip"
        },
        {
          "cidr_block" = "172.16.0.18/32"
        },
      ),
    ],
  )
  cluster_min_master_version = var.cluster_ec_min_master_version

  apis_dependency          = module.apis_activation.all_apis_enabled
  shared_vpc_dependency    = module.shared-vpc.gke_subnetwork_ids
  istio_status             = var.istio_status
  gke_pod_network_name     = var.gke_pod_network_name
  gke_service_network_name = var.gke_service_network_name
}

resource "google_sourcerepo_repository" "SSP" {
  name       = var.ec_repository_name
  project    = module.shared_projects.shared_ec_id
  depends_on = [module.apis_activation]
}

module "gke-secrets" {
  source = "../../kubernetes-cluster-creation"

  providers = {
    google                 = google.vault
    google-beta.shared-vpc = google-beta.shared-vpc
  }

  region               = var.region
  sharedvpc_project_id = module.shared_projects.shared_networking_id
  sharedvpc_network    = var.shared_vpc_name

  cluster_enable_private_nodes    = var.cluster_sec_enable_private_nodes
  cluster_enable_private_endpoint = var.cluster_sec_enable_private_endpoint
  cluster_project_id              = module.shared_projects.shared_secrets_id
  cluster_subnetwork              = var.cluster_sec_subnetwork
  cluster_service_account         = var.cluster_sec_service_account
  cluster_service_account_roles   = var.cluster_sec_service_account_roles
  cluster_name                    = var.cluster_sec_name
  cluster_pool_name               = var.cluster_sec_pool_name
  cluster_master_cidr             = var.cluster_sec_master_cidr
  cluster_master_authorized_cidrs = concat(
    var.cluster_sec_master_authorized_cidrs,
    [
      merge(
        {
          "display_name" = "initial-admin-ip"
        },
        {
          "cidr_block" = join("", [var.clusters_master_whitelist_ip, "/32"])
        },
      ),
    ],
  )
  cluster_min_master_version = var.cluster_sec_min_master_version
  istio_status               = var.istio_status
  cluster_oauth_scopes       = var.cluster_sec_oauth_scope

  apis_dependency          = module.apis_activation.all_apis_enabled
  shared_vpc_dependency    = module.shared-vpc.gke_subnetwork_ids
  gke_pod_network_name     = var.gke_pod_network_name
  gke_service_network_name = var.gke_service_network_name
}

#Vault being separated out into own activator
//module "vault" {
//  source = "../../vault"
//
//  vault_cluster_project             = module.shared_projects.shared_secrets_id
//  vault-gcs-location                = var.location
//  vault-region                      = var.region
//  vault_keyring_name                = var.sec-vault-keyring
//  vault_crypto_key_name             = var.sec-vault-crypto-key-name
//  vault-lb                          = var.sec-lb-name
//  vault-sa                          = module.gke-secrets.cluster_sa
//  vault-gke-sec-endpoint            = module.gke-secrets.cluster_endpoint
//  vault-gke-sec-master-auth-ca-cert = module.gke-secrets.cluster_endpoint
//  vault-gke-sec-username            = module.gke-secrets.cluster_master_auth_username
//  vault-gke-sec-password            = module.gke-secrets.cluster_master_auth_password
//  vault-gke-sec-client-ca           = module.gke-secrets.cluster_master_auth_0_client_certificate
//  vault-gke-sec-client-key          = module.gke-secrets.cluster_master_auth_0_client_key
//  vault-gke-sec-cluster_ca_cert     = module.gke-secrets.cluster_master_auth_0_cluster_ca_certificate
//  vault-gke-sec-name                = var.cluster_sec_name
//
//  vault-cert-common-name  = var.cert-common-name
//  vault-cert-organization = var.tls-organization
//
//  apis_dependency = module.apis_activation.all_apis_enabled
//  #  shared_vpc_dependency = "${module.shared-vpc.gke_subnetwork_ids}"
//
//  shared_bastion_project = module.shared_projects.shared_bastion_id
//
//}

module "gke-itsm" {
  source = "../../kubernetes-cluster-creation"

  providers = {
    google                 = google
    google-beta.shared-vpc = google-beta.shared-vpc
    kubernetes             = kubernetes.gke-itsm
  }

  region               = var.region
  sharedvpc_project_id = module.shared_projects.shared_networking_id
  sharedvpc_network    = var.shared_vpc_name

  cluster_enable_private_nodes    = var.cluster_opt_enable_private_nodes
  cluster_enable_private_endpoint = var.cluster_opt_enable_private_endpoint
  cluster_project_id              = module.shared_projects.shared_itsm_id
  cluster_subnetwork              = var.cluster_opt_subnetwork
  cluster_service_account         = var.cluster_opt_service_account
  cluster_name                    = var.cluster_opt_name
  cluster_pool_name               = var.cluster_opt_pool_name
  cluster_master_cidr             = var.cluster_opt_master_cidr
  cluster_master_authorized_cidrs = concat(
    var.cluster_opt_master_authorized_cidrs,
    [
      merge(
        {
          "display_name" = "initial-admin-ip"
        },
        {
          "cidr_block" = join("", [var.clusters_master_whitelist_ip, "/32"])
        },
      ),
    ],
  )
  cluster_min_master_version = var.cluster_opt_min_master_version

  apis_dependency          = module.apis_activation.all_apis_enabled
  istio_status             = var.istio_status
  istio_permissive_mtls    = "true"
  shared_vpc_dependency    = module.shared-vpc.gke_subnetwork_ids
  gke_pod_network_name     = var.gke_pod_network_name
  gke_service_network_name = var.gke_service_network_name
}

# Kubernetes provider for the gke-itsm cluster
provider "kubernetes" {
  alias                  = "gke-itsm"
  host                   = "https://${module.gke-itsm.cluster_endpoint}"
  load_config_file       = false
  cluster_ca_certificate = base64decode(module.gke-itsm.cluster_ca_certificate)
  token                  = data.google_client_config.current.access_token
  version                = "~> 1.10.0"
}

# Deploy gke-itsm cluster helm pre-requisite resources
module "gke_itsm_helm_pre_req" {
  source = "../../helm-pre-requisites"
  providers = {
    kubernetes = kubernetes.gke-itsm
  }
}

# Set GKE Operations cluster Helm provider
provider "helm" {
  alias = "gke-itsm"
  kubernetes {
    host                   = "https://${module.gke-itsm.cluster_endpoint}"
    load_config_file       = false
    cluster_ca_certificate = base64decode(module.gke-itsm.cluster_ca_certificate)
    token                  = data.google_client_config.current.access_token
  }
  service_account = module.gke_itsm_helm_pre_req.tiller_svc_accnt_name
  version         = "~> 0.10.4"
}

# Deploys itop on GKE Operations cluster

module "itop" {
  source = "../../itop"
  providers = {
    kubernetes = kubernetes.gke-itsm
    helm       = helm.gke-itsm
  }

  host_project_id       = module.shared_projects.shared_itsm_id
  itop_chart_local_path = "../../itop/helm"
  region                = var.region
  region_zone           = var.region_zone
  database_user_name    = var.itop_database_user_name
  k8_cluster_name       = var.cluster_sec_name

  dependency_vars = module.gke-itsm.node_id
}


module "k8s-ec_context" {
  source = "../../k8s-context"

  cluster_name    = var.cluster_ec_name
  region          = var.region
  cluster_project = module.shared_projects.shared_ec_id
  dependency_var  = module.gke-ec.node_id
}

resource "null_resource" "kubernetes_service_account_key_secret" {
  triggers = {
    content = module.k8s-ec_context.k8s-context_id
  }

  provisioner "local-exec" {
    command = "echo 'kubectl --context=${module.k8s-ec_context.context_name} create secret generic ec-service-account --from-file=${local_file.ec_service_account_key.filename}' | tee -a /opt/tb/repo/tb-gcp-tr/landingZone/kube.sh"
  }

  provisioner "local-exec" {
    command = "echo 'kubectl --context=${module.k8s-ec_context.context_name} delete secret ec-service-account' | tee -a /opt/tb/repo/tb-gcp-tr/landingZone/kube.sh"
    when    = destroy
  }
}

module "SharedServices_configuration_file" {
  source = "../../../tb-common-tr/start_service"

  k8s_template_file = local_file.ec_config_map.filename
  cluster_context   = module.k8s-ec_context.context_name
  dependency_var    = null_resource.kubernetes_service_account_key_secret.id
}

module "SharedServices_ec" {
  source = "../../../tb-common-tr/start_service"

  k8s_template_file = var.eagle_console_yaml_path
  cluster_context   = module.k8s-ec_context.context_name
  dependency_var    = module.SharedServices_configuration_file.id
}

# This is only temporrary piece of code.
# Creating the endpoint file is a part of istio module in tb-common-tr repository
# null_resource.get_endpoint behind can be removed if this module will be integrated (TBASE-194)
resource "null_resource" "get_endpoint" {
  provisioner "local-exec" {
    command = <<EOF
      echo 'echo -n 'http://' > ${var.endpoint_file}
      for i in $(seq -s " " 1 35); do
        sleep $i
        ENDPOINT=$(kubectl --context=${module.k8s-ec_context.context_name} get svc istio-ingressgateway -n istio-system -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
        if [ -n "$ENDPOINT" ]; then
          echo "$ENDPOINT" >> ${var.endpoint_file}
          exit 0
        fi
      done
      echo "Loadbalancer is not reachable after 10,5 minutes"
      exit 1' | tee -a /opt/tb/repo/tb-gcp-tr/landingZone/kube.sh
      EOF
  }

  #   command = "echo -n 'http://' > ${var.endpoint_file} && kubectl --context=${module.k8s-ec_context.context_name} get svc istio-ingressgateway -n istio-system -o jsonpath='{.status.loadBalancer.ingress[0].ip}' >> ${var.endpoint_file}"

  depends_on = [module.SharedServices_ec]
}

resource "google_sourcerepo_repository" "activator-terraform-code-store" {
  name       = "terraform-code-store"
  project    = module.shared_projects.shared_ec_id
  depends_on = [module.apis_activation]
}

resource "google_sourcerepo_repository_iam_binding" "terraform-code-store-admin-binding" {
  repository = google_sourcerepo_repository.activator-terraform-code-store.name
  project    = module.shared_projects.shared_ec_id
  role       = "roles/source.admin"

  members = [
    local.service_account_name,
  ]
  depends_on = [google_sourcerepo_repository.activator-terraform-code-store]
}
