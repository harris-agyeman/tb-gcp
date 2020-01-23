# Copyright 2017 Google Inc. All rights reserved.
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
COMPUTE_URL_BASE = 'https://www.googleapis.com/compute/v1/'
"""Creates a single project with specified service accounts and APIs enabled."""

import copy
import sys
from apis import ApiResourceName

def GenerateConfig(context):
  """Generates config."""

  project_id = context.env['name']
  hc_name = project_id + '-hc3'
  billing_name = 'billing_' + project_id
  rt_config_name = project_id + '-config2'
  fw_name = project_id + '-hc-fw'

  if not IsProjectParentValid(context.properties):
    sys.exit(('Invalid [organization-id, parent-folder-id], '
              'must specify at least one. If setting up Shared VPC, you '
              'must specify at least organization-id.'))

  parent_type = ''
  parent_id = ''

  if 'parent-folder-id' in context.properties:
    parent_type = 'folder'
    parent_id = context.properties['parent-folder-id']
  else:
    parent_type = 'organization'
    parent_id = context.properties['organization-id']

  if 'project-name' in context.properties:
    project_name = context.properties['project-name']
  else:
    project_name = project_id

  resources = [{
      'name': project_id,
      'type': 'cloudresourcemanager.v1.project',
      'properties': {
          'name': project_name,
          'projectId': project_id,
          'parent': {
              'type': parent_type,
              'id': parent_id
          }
      }
  }, {
      'name': billing_name,
      'type': 'deploymentmanager.v2.virtual.projectBillingInfo',
      'metadata': {
          'dependsOn': [project_id]
      },
      'properties': {
          'name': 'projects/' + project_id,
          'billingAccountName': context.properties['billing-account-name']
      }
  }, {
      'name': 'apis',
      'type': 'apis.py',
      'properties': {
          'project': project_id,
          'billing': billing_name,
          'apis': context.properties['apis'],
          'concurrent_api_activation':
              context.properties['concurrent_api_activation']
      }
   }, {
      'name': 'sub-network',
      'type': 'sub-network.py',
      'properties': {
          'project': project_id,
          'network': '$(ref.bootstrap-network3.selfLink)',
          'region': context.properties['region'],
          'ipCidrRange': '192.168.0.0/28',
          'networks': context.properties['networks']
        }
      }, {
      'name': 'network-tb4',
      'type': 'network-template.py',
      'properties': {
          'project': project_id,
          'networks': context.properties['networks']
        }
      }, {
      'name': 'service-account',
      'type': 'service-accounts.py',
      'properties': {
          'project': project_id,
          'service-accounts': context.properties['service-accounts']
      }
   }, {
      'name': 'vm'+ context.env['name'],
      'type': 'vm-template.py',
      'properties': {
          'project': project_id,
          'zone': context.properties['zone'],
          'machineType': context.properties['machineType'],
          'vm': context.properties['vm'],
          'startup-script': context.properties['startup-script']
        },
    }, {
      'name': 'cloud-storage-bucket',
      'type': 'cloud-storage-bucket.py',
      'properties': {
          'project': project_id,
          'zone': context.properties['zone'],
          'bucket-export-settings':{
                'create-bucket': 'true'
          }
        }
    }, {
      'name': 'static-ip-address',
      'type': 'gcp-types/compute-v1:addresses',
      'properties': {
          'project': project_id,
          'region': context.properties['region']
        }
    }, {
      'name': 'nat-gateway',
      'type': 'nat-gateway.py',
      'properties': {
          'project': project_id,
          'region': context.properties['region'],
          'zone': context.properties['zone'],
          'machineType': context.properties['machineType'],
          'image': 'https://www.googleapis.com/compute/v1/projects/debian-cloud/global/images/family/debian-9',
          'diskType': 'pd-ssd',
          'diskSizeGb': '50',
          'nat-gw-tag': 'natgw',
          'startupScript': context.properties['startupScript'],
          'nated-vm-tag': 'no-ip',
          'healthCheck': '$(ref.' + hc_name + '.selfLink)',
          'network': '$(ref.bootstrap-network-subnet.selfLink)',
          'runtimeConfig': '$(ref.' + rt_config_name + '.name)',
          'runtimeConfigName': rt_config_name,
          'hc_name': '$(ref.' + hc_name + '.selfLink)'

        }
     }, {
      'name': hc_name,
      'type': 'gcp-types/compute-v1:httpHealthChecks',
      'properties': {
          'project': project_id,
          'port': 80,
          'requestPath': '/health-check',
          'healthyThreshold': 1,
          'unhealthyThreshold': 3,
          'description': 'integration test http health check',
          'checkIntervalSec': 10
        }
    }, {
      'name': rt_config_name,
      'type': 'gcp-types/runtimeconfig-v1beta1:projects.configs',
      'properties': {
          'config':  rt_config_name
      }
   }, {
      'name': fw_name,
      'type': 'gcp-types/compute-v1:firewalls',
      'properties': {
          'project': project_id,
          'network': '$(ref.bootstrap-network3.selfLink)',
          'sourceRanges': ['209.85.152.0/22', '209.85.204.0/22', '35.191.0.0/16', '130.211.0.0/22'],
          'targetTags': ['natgw'],
          'allowed': [{
              'IPProtocol': 'TCP',
              'ports': [80]
          }]
      }
  }, {
      'name': 'fw-iap',
      'type': 'gcp-types/compute-v1:firewalls',
      'properties': {
          'project': project_id,
          'network': '$(ref.bootstrap-network3.selfLink)',
          'sourceRanges': ['35.235.240.0/20'],
          'targetTags': ['iap'],
          'allowed': [{
              'IPProtocol': 'TCP'
          }]
      }
  }]
  if context.properties.get('set-dm-service-account-as-owner'):
        svc_acct = 'serviceAccount:{}@cloudservices.gserviceaccount.com'.format(project_id)
  if (context.properties.get('iam-policy-patch') or
      context.properties.get('set-dm-service-account-as-owner')):
    iam_policy_patch = context.properties.get('iam-policy-patch', {})
    if iam_policy_patch.get('add'):
      policies_to_add = iam_policy_patch['add']
    else:
      policies_to_add = []
    if iam_policy_patch.get('remove'):
      policies_to_remove = iam_policy_patch['remove']
    else:
      policies_to_remove = []
      # Merge the default DM service account into the owner role if it exists
      owner_idx = [bind['role'] == 'roles/owner' for bind in policies_to_add]
      try:
        # Determine where in policies_to_add the owner role is.
        idx = owner_idx.index(True)
      except ValueError:
        # If the owner role is not defined just append to what to add.
        policies_to_add.append({'role': 'roles/owner', 'members': [svc_acct]})
      else:
        # Append the default DM service account to the owner role members
        if svc_acct not in policies_to_add[idx]['members']:
          policies_to_add[idx]['members'].append(svc_acct)

    get_iam_policy_dependencies = [ project_id ]
    for api in context.properties['apis']:
      get_iam_policy_dependencies.append(ApiResourceName(project_id, api))

    resources.extend([{
        # Get the IAM policy first so that we do not remove any existing bindings.
        'name': 'get-iam-policy-' + project_id,
        'action': 'gcp-types/cloudresourcemanager-v1:cloudresourcemanager.projects.getIamPolicy',
        'properties': {
          'resource': project_id,
        },
        'metadata': {
          'dependsOn': get_iam_policy_dependencies,
          'runtimePolicy': ['UPDATE_ALWAYS']
        }
    }, {
        # Set the IAM policy patching the existing policy with what ever is currently in the
        # config.
        'name': 'patch-iam-policy-' + project_id,
        'action': 'gcp-types/cloudresourcemanager-v1:cloudresourcemanager.projects.setIamPolicy',
        'properties': {
          'resource': project_id,
          'policy': '$(ref.get-iam-policy-' + project_id + ')',
          'gcpIamPolicyPatch': {
             'add': policies_to_add,
             'remove': policies_to_remove
          }
        }
    }])
  return {'resources': resources}

def IsProjectParentValid(properties):
  """ A helper function to validate that the project is either under a folder
      or under an organization.
      If we are setting up Shared VPC, we always need organization-id.
      If not, we can work with either organization-id or parent-folder-id.
  """
  if ('shared_vpc_service_of' in properties or 'shared_vpc_host' in properties):
    return 'organization-id' in properties
  else:
    return ('organization-id' in properties or 'parent-folder-id' in properties)