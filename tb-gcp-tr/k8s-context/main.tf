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

resource "null_resource" "k8s_config" {
  triggers = {
    content = var.dependency_var
  }
  provisioner "local-exec" {
    command = <<EOT
    gcloud compute ssh proxyuser@tb-kube-proxy --quiet --project=shared-bastion-404a9ed6 --zone=europe-west2-a --command="gcloud beta container clusters get-credentials "${var.cluster_name}" --region="${var.region}" --project="${var.cluster_project}""
    EOT
  }
}

