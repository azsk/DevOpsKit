# ------------------------------------------------------------------------------
# Copyright (c) Microsoft Corporation. All rights reserved.
# Licensed under the MIT License. See License in the project root for
# license information.
# ------------------------------------------------------------------------------

from kubernetes import client, config
from kubernetes.client import configuration
from applicationinsights import TelemetryClient
import pandas as pd
import numpy as np
import os
import copy
from .utils import fail_with_manual
from distutils.version import StrictVersion


class AKSBootstrap:
	__instance = None

	def __init__(self):
		if AKSBootstrap.__instance != None:
			raise Exception("Something went wrong.")
		else:
			self.resources = {
				"APP_INSIGHT_KEY":  None,
				"SUBSCRIPTION_ID":  None,
				"RG_NAME":          None,
				"RESOURCE_NAME":    None,
				"pods":             [],
				"service_accounts": []
			}
			try:
				# TODO: Add LATEST_KUBERNETES_VERSION, PODS_ALLOWED_NAMESPACES, SERVICE_ACCOUNTS_ALLOWED_NAMESPACES, TRUSTWORTHY_IMAGE_SOURCES to env from configmap ( Deployment Manifest )
				# Intended values given below
				'''
				self.resources['pods_allowed_namespaces'] = set(["azsk-scanner", "gatekeeper-system", "kube-node-lease", "kube-public", "kube-system", "kured"])
				self.resources['service_accounts_allowed_namespaces'] = set(["azsk-scanner", "gatekeeper-system", "kube-node-lease", "kube-public", "kube-system", "kured"])
				self.resources['trustworthy_image_sources'] = set(['k8s.gcr.io','microsoft','mcr.microsoft.com','azskteam'])
				'''

				config.load_incluster_config()

				v1 = client.CoreV1Api()

				self.resources['pods_allowed_namespaces'] = set(os.environ.get("PODS_ALLOWED_NAMESPACES", "").split(","))
				self.resources['service_accounts_allowed_namespaces'] = set(os.environ.get("SERVICE_ACCOUNTS_ALLOWED_NAMESPACES", "").split(","))
				self.resources['trustworthy_image_sources'] = set(os.environ.get("TRUSTWORTHY_IMAGE_SOURCES", "").split(","))

				pod_response = v1.list_pod_for_all_namespaces(watch=False)
				pods = list(filter(lambda x: x.metadata.namespace not in self.resources['pods_allowed_namespaces'], pod_response.items))
				self.resources['pods'] = pods

				serviceacc_response = v1.list_service_account_for_all_namespaces(watch=False)
				service_accounts = list(filter(lambda x: x.metadata.namespace not in self.resources['service_accounts_allowed_namespaces'], serviceacc_response.items))
				self.resources['service_accounts'] = service_accounts

				self.resources['SUBSCRIPTION_ID'] = os.environ.get("SUBSCRIPTION_ID", None)
				self.resources['RG_NAME'] = os.environ.get("RG_NAME", None)
				self.resources['RESOURCE_NAME'] = os.environ.get("RESOURCE_NAME", None)
				self.resources['APP_INSIGHT_KEY'] = os.environ.get("APP_INSIGHT_KEY", None)
				self.resources['LATEST_KUBERNETES_VERSION'] = os.environ.get("LATEST_KUBERNETES_VERSION", "1.14.7")
			except Exception as e:
				print(e)

			AKSBootstrap.__instance = self

	@staticmethod
	def get_config():
		if AKSBootstrap.__instance == None:
			AKSBootstrap()
		return AKSBootstrap.__instance


class AKSBaseControlTest:

	def __init__(self):
		cluster_config = AKSBootstrap.get_config()
		self.pods = cluster_config.resources['pods']
		self.service_accounts = cluster_config.resources['service_accounts']
		self.APP_INSIGHT_KEY = cluster_config.resources['APP_INSIGHT_KEY']
		self.SUBSCRIPTION_ID = cluster_config.resources['SUBSCRIPTION_ID']
		self.RG_NAME = cluster_config.resources['RG_NAME']
		self.RESOURCE_NAME = cluster_config.resources['RESOURCE_NAME']
		self.LATEST_KUBERNETES_VERSION = cluster_config.resources['LATEST_KUBERNETES_VERSION']
		self.pods_allowed_namespaces = cluster_config.resources['pods_allowed_namespaces']
		self.service_accounts_allowed_namespaces = cluster_config.resources['service_accounts_allowed_namespaces']
		self.trustworthy_image_sources = cluster_config.resources['trustworthy_image_sources']
		self.detailed_logs = { "control_id": "", "type": "", "desc": "", "logs": [] }

	def test(self) -> str:
		raise NotImplementedError

	def CheckSecurityConfig(self, property, expected_value):
		result = []
		for pod in self.pods:
			security_context = pod.spec.security_context
			info = {
				"namespace":                  pod.metadata.namespace,
				"pod_name":                   pod.metadata.name,
				"container":                  None,
				"run_as_non_root":            None,
				"allow_privilege_escalation": None,
				"read_only_root_filesystem":  None
			}
			if security_context != None:
				pod_run_as_non_root = getattr(security_context, 'run_as_non_root', None)
				pod_allow_privilege_escalation = getattr(security_context, 'allow_privilege_escalation', None)
				pod_read_only_root_filesystem = getattr(security_context, 'read_only_root_filesystem', None)
			for container in pod.spec.containers:
				security_context = container.security_context
				run_as_non_root = getattr(security_context, 'run_as_non_root', pod_run_as_non_root)
				if run_as_non_root == None:
					run_as_non_root = pod_run_as_non_root
				allow_privilege_escalation = getattr(security_context, 'allow_privilege_escalation', pod_allow_privilege_escalation)
				read_only_root_filesystem = getattr(security_context, 'read_only_root_filesystem', pod_read_only_root_filesystem)
				info = copy.deepcopy(info)
				info['container'] = container.name
				info['run_as_non_root'] = run_as_non_root
				info['allow_privilege_escalation'] = allow_privilege_escalation
				info['read_only_root_filesystem'] = read_only_root_filesystem
				result.append(info)
		non_compliant_containers = filter(lambda x: x[property] != expected_value, result)
		return non_compliant_containers

	def set_credentials(self, uname, password):
		# TODO: Needs to be implemented? Check
		pass

	def send_telemetry(self, event_name, custom_properties):
		if self.APP_INSIGHT_KEY != None:
			try:
				tc = TelemetryClient(self.APP_INSIGHT_KEY)
				# Add common properties
				custom_properties['SubscriptionId'] = self.SUBSCRIPTION_ID
				custom_properties['ResourceGroupName'] = self.RG_NAME
				custom_properties['ResourceName'] = self.RESOURCE_NAME
				# Send telemetry event
				tc.track_event(event_name, custom_properties)
				tc.flush()
			except:
				pass
			# No need to break execution, if any exception occurs while sending telemetry


@fail_with_manual
class CheckContainerRunAsNonRoot(AKSBaseControlTest):
	name = "Dont_Run_Container_As_Root"

	def __init__(self):
		super().__init__()
		self.desc = ("Container must run as a non-root user")

	@fail_with_manual
	def test(self):
		non_compliant_containers = []
		if len(self.pods) > 0:
			non_compliant_containers = list(self.CheckSecurityConfig('run_as_non_root', True))
		else:
			return "Manual"
		if len(non_compliant_containers) > 0:
			self.detailed_logs["type"] = "non_compliant_containers"
			self.detailed_logs["desc"] = self.desc + "\nFor following container(s), runAsNonRoot is either set to 'False' or 'None':"
			self.detailed_logs["logs"] = non_compliant_containers
			return ("Failed")
		else:
			return ("Passed")


@fail_with_manual
class CheckContainerPrivilegeEscalation(AKSBaseControlTest):
	name = "Restrict_Container_Privilege_Escalation"

	def __init__(self):
		super().__init__()
		self.desc = ("Container should not allow privilege escalation")

	@fail_with_manual
	def test(self):
		non_compliant_containers = []
		if len(self.pods) > 0:
			non_compliant_containers = list(self.CheckSecurityConfig('allow_privilege_escalation', False))
		else:
			return ("Manual")
		if len(non_compliant_containers) > 0:
			self.detailed_logs["type"] = "non_compliant_containers"
			self.detailed_logs["desc"] = self.desc + "\nFor Following container(s), allowPrivilegeEscalation is either set to 'True' or 'None':"
			self.detailed_logs["logs"] = non_compliant_containers
			return ("Failed")
		else:
			return ("Passed")


@fail_with_manual
class CheckContainerReadOnlyRootFilesystem(AKSBaseControlTest):
	name = "Set_Read_Only_Root_File_System"

	def __init__(self):
		super().__init__()
		self.desc = ("Container should not be allowed to write to the root/host filesystem")

	@fail_with_manual
	def test(self):
		non_compliant_containers = []
		if len(self.pods) > 0:
			non_compliant_containers = list(self.CheckSecurityConfig('read_only_root_filesystem', True))
		else:
			return ("Manual")
		if len(non_compliant_containers) > 0:
			self.detailed_logs["type"] = "non_compliant_containers"
			self.detailed_logs["desc"] = self.desc + "\nFor Following container(s), readOnlyRootFilesystem is either set to 'False' or 'None':"
			self.detailed_logs["logs"] = non_compliant_containers
			return ("Failed")
		else:
			return ("Passed")


@fail_with_manual
class CheckInactiveServiceAccounts(AKSBaseControlTest):
	name = "Remove_Inactive_Service_Accounts"

	def __init__(self):
		super().__init__()
		self.desc = ("Cluster should not have any inactive service account")

	@fail_with_manual
	def test(self):
		if len(self.service_accounts) > 0:
			self.service_accounts = list(filter(lambda x: x.metadata.name != 'default', self.service_accounts))
		else:
			return ("Manual")
		all_svc_accounts = set()
		pod_svc_accounts = set()
		for item in self.service_accounts:
			all_svc_accounts.add((item.metadata.name, item.metadata.namespace))
		for item in self.pods:
			pod_svc_accounts.add((item.spec.service_account, item.metadata.namespace))
		inactive_svc_accounts = all_svc_accounts - pod_svc_accounts
		if len(inactive_svc_accounts) > 0:
			self.detailed_logs["type"] = "service_accounts"
			self.detailed_logs["desc"] = self.desc + "\nFollowing service account(s) are not referenced by any pod/container:"
			self.detailed_logs["logs"] = inactive_svc_accounts
			return ("Failed")
		else:
			return ("Passed")


@fail_with_manual
class CheckClusterPodIdentity(AKSBaseControlTest):
	name = "Use_AAD_Pod_Identity"

	def __init__(self):
		super().__init__()
		self.desc = ("AAD Pod Identity should be used to access Azure resources from cluster")

	@fail_with_manual
	def test(self):
		if len(self.pods) > 0:
			result = "Failed"
		else:
			return "Manual"

		component_mic = False
		component_nmi = False

		for pod in self.pods:
			if pod.metadata.name.find("mic-") != -1 and pod.spec.containers[0].image.find("mcr.microsoft.com/k8s/aad-pod-identity/mic") != -1:
				component_mic = True
			if pod.metadata.name.find("nmi-") != -1 and pod.spec.containers[0].image.find("mcr.microsoft.com/k8s/aad-pod-identity/nmi") != -1:
				component_nmi = True

		if component_mic and component_nmi:
			result = "Verify"

		return result


@fail_with_manual
class CheckDefaultSvcRoleBinding(AKSBaseControlTest):
	name = "Dont_Bind_Role_To_Default_Svc_Acc"

	def __init__(self):
		super().__init__()
		self.desc = ("Default service account should not be assigned any cluster role")

	@fail_with_manual
	def test(self):
		is_failed = False
		v1beta1 = client.RbacAuthorizationV1beta1Api()
		clusterRoles = v1beta1.list_cluster_role_binding(watch=False)
		for item in clusterRoles.items:
			try:
				subjects = item.subjects
				for subject in subjects:
					if subject.namespace == "default" and subject.name == "default":
						is_failed = True
			except:
				pass
		if is_failed:
			return "Failed"
		else:
			return "Passed"


@fail_with_manual
class CheckContainerPrivilegeMode(AKSBaseControlTest):
	name = "Dont_Run_Privileged_Container"

	def __init__(self):
		super().__init__()
		self.desc = ("Container should not run in the privileged mode")

	@fail_with_manual
	def test(self):
		if len(self.pods) > 0:
			result = []
			for pod in self.pods:
				security_context = pod.spec.security_context
				info = {
					"namespace":  pod.metadata.namespace,
					"pod_name":   pod.metadata.name,
					"container":  None,
					"privileged": None
				}
				if security_context != None:
					pod_privileged = getattr(security_context, 'privileged', None)
				for container in pod.spec.containers:
					security_context = container.security_context
					privileged = getattr(security_context, 'privileged', pod_privileged)
					info = copy.deepcopy(info)
					info['container'] = container.name
					info['privileged'] = privileged
					result.append(info)
			non_compliant_containers = list(filter(lambda x: x["privileged"] == True, result))
		else:
			return ("Manual")
		if len(non_compliant_containers) > 0:
			self.detailed_logs["type"] = "non_compliant_containers"
			self.detailed_logs["desc"] = self.desc + \
			    "\nFollowing container(s) will run in the privileged mode:"
			self.detailed_logs["logs"] = non_compliant_containers
			return ("Failed")
		else:
			return ("Passed")


@fail_with_manual
class CheckDefaultNamespaceResources(AKSBaseControlTest):
	name = "Dont_Use_Default_Namespace"

	def __init__(self):
		super().__init__()
		self.desc = ("Applications should not be deployed in default namespace")

	@fail_with_manual
	def test(self):
		pods_in_default_namespace = []
		if len(self.pods) > 0:
			pods_in_default_namespace = list(filter(lambda x: x.metadata.namespace == 'default', self.pods))
		else:
			return ("Manual")
		if len(pods_in_default_namespace) > 0:
			non_compliant_pods = []
			self.detailed_logs["type"] = "non_compliant_pods"
			self.detailed_logs["desc"] = self.desc + \
			    "\nFollowing pods(s) are present in default namespace:"
			for pod in pods_in_default_namespace:
				non_compliant_pods.append({ "pod_name": pod.metadata.name, "namespace": pod.metadata.namespace })
			self.detailed_logs["logs"] = non_compliant_pods
			return ("Failed")
		else:
			return ("Passed")


@fail_with_manual
class CheckResourcesWithSecrets(AKSBaseControlTest):
	name = "Use_KeyVault_To_Store_Secret"

	def __init__(self):
		super().__init__()
		self.desc = ("Credentials/Keys should be stored using Azure KeyVault")

	@fail_with_manual
	def test(self):
		pods_with_secrets = []
		if len(self.pods) > 0:
			svc_accounts = []

			if len(self.service_accounts) > 0:
				all_service_accounts = {svc.metadata.name for svc in self.service_accounts}
				svc_accounts = dict.fromkeys(all_service_accounts, 0)

			for pod in self.pods:
				info = {
					"namespace": pod.metadata.namespace,
					"pod_name":  pod.metadata.name
				}
				is_secret_mounted = False
				for volume in pod.spec.volumes:
					if (volume.secret != None):
						tokenIndex = volume.secret.secret_name.rfind('-token-')
						if tokenIndex == -1 or not (volume.secret.secret_name[:tokenIndex] in svc_accounts):
							is_secret_mounted = True

				if not is_secret_mounted:
					for container in pod.spec.containers:
						if container.env != None and len(container.env) > 0:
							secret_key_refs = list(filter(lambda x: x.value_from != None and x.value_from.secret_key_ref != None, container.env))
							if len(secret_key_refs) > 0:
								is_secret_mounted = True

				if is_secret_mounted:
					pods_with_secrets.append(info)
		else:
			return ("Manual")
		if len(pods_with_secrets) > 0:
			self.detailed_logs["type"] = "pods_with_secrets"
			self.detailed_logs["desc"] = self.desc + "\nFollowing pod(s) are using Kubernetes secret objects to store secrets:"
			self.detailed_logs["logs"] = pods_with_secrets
			return ("Failed")
		else:
			return ("Passed")


@fail_with_manual
class CheckKubernetesVersion(AKSBaseControlTest):
	name = "Use_Latest_Kubernetes_Version"

	def __init__(self):
		super().__init__()
		self.desc = ("The latest version of Kubernetes should be used")

	@fail_with_manual
	def test(self):
		v1 = client.CoreV1Api()
		res = v1.list_node(watch=False)
		nodes = list(res.items)
		if len(nodes) > 0:
			try:
				node = nodes[0]
				cur_version = node.status.node_info.kubelet_version
				cur_version = cur_version.replace("v", "")
				req_version = self.LATEST_KUBERNETES_VERSION
				if StrictVersion(req_version) > StrictVersion(cur_version):
					return ("Failed")
				else:
					return ("Passed")

			except:
				return ("Manual")

		else:
			return ("Manual")


@fail_with_manual
class CheckForKured(AKSBaseControlTest):
	name = "Use_Reboot_Daemon"

	def __init__(self):
		super().__init__()
		self.desc = ("Kured must be installed to check if reboots are required for OS updates")

	@fail_with_manual
	def test(self):
		try:
			v1beta2Api = client.AppsV1beta2Api()
			daemonset_response = v1beta2Api.list_daemon_set_for_all_namespaces()
			if "kured" in list(x.metadata.name for x in daemonset_response.items):
				return ("Passed")
			else:
				return ("Failed")
		except:
			return ("Manual")


@fail_with_manual
class CheckResourcesLimitsAndRequests(AKSBaseControlTest):
	name = "Set_Resource_Limits_And_Requests"

	def __init__(self):
		super().__init__()
		self.desc = ("Pod resource limits and requests must be set")

	@fail_with_manual
	def test(self):
		try:
			v1coreApi = client.CoreV1Api()
			checks_lacking = []
			for pod in self.pods:
				pod_status_response = v1coreApi.read_namespaced_pod_status(
				    pod.metadata.name, pod.metadata.namespace)
				for container in pod_status_response.spec.containers:
					check_data = {"pod_name": pod.metadata.name,
					    "namespace": pod.metadata.namespace, "container": container.name, "checks": []}

					if container.resources.limits is not None:
						if 'cpu' not in container.resources.limits:
							check_data["checks"].append("CPU Resource Limits Missing")
						if 'memory' not in container.resources.limits:
							check_data["checks"].append("Memory Resource Limits Missing")
					else:
						check_data["checks"].append("CPU Resource Limits Missing")
						check_data["checks"].append("Memory Resource Limits Missing")

					if container.resources.requests is not None:
						if 'cpu' not in container.resources.requests:
							check_data["checks"].append("CPU Request Limits Missing")
						if 'memory' not in container.resources.requests:
							check_data["checks"].append("Memory Request Limits Missing")
					else:
						check_data["checks"].append("CPU Request Limits Missing")
						check_data["checks"].append("Memory Request Limits Missing")

					if len( check_data["checks"] ) > 0:
						checks_lacking.append(check_data)

			if len(checks_lacking) > 0:
				self.detailed_logs["type"] = "missing_resource_limits_requests_pods"
				self.detailed_logs["desc"] = self.desc + "\nFollowing pod(s) have no resource limits and requests:"
				self.detailed_logs["logs"] = checks_lacking
				return ("Failed")
			else:
				return ("Passed")

		except:
			return ("Manual")


@fail_with_manual
class CheckStorageClassReclaimPolicy(AKSBaseControlTest):
	name = "Storage_Class_Reclaim_Policy"

	def __init__(self):
		super().__init__()
		self.desc = ("Storage class reclaim policy should typically not default to delete")

	@fail_with_manual
	def test(self):
		try:
			storage_class_data = []
			v1storageApi = client.StorageV1Api()
			storage_class_response = v1storageApi.list_storage_class()
			for storage_class in storage_class_response.items:
				if storage_class.reclaim_policy == 'Delete':
					storage_class_data.append({ 'name': storage_class.metadata.name, 'kubectl.kubernetes.io/last-applied-configuration': storage_class.metadata.annotations['kubectl.kubernetes.io/last-applied-configuration'] })
			if len(storage_class_data) > 0:
				self.detailed_logs["type"] = "storage_class_delete_reclaim_policy"
				self.detailed_logs["desc"] = self.desc + "\nFollowing storage classes have reclaim policy set as delete:"
				self.detailed_logs["logs"] = storage_class_data
				return ("Verify")
			else:
				return ("Passed")
		except:
			return ("Manual")


@fail_with_manual
class CheckPodSecurityPolicies(AKSBaseControlTest):
	name = "Use_Pod_Security_Policy"

	def __init__(self):
		super().__init__()
		self.desc = "Pod Security Policies should be used to secure individual pods"

	@fail_with_manual
	def test(self):
		try:
			v1beta1PolicyApi = client.PolicyV1beta1Api()
			pod_security_policy_response = v1beta1PolicyApi.list_pod_security_policy()
			if len(pod_security_policy_response.items) > 0:
				return ("Passed")
			else:
				return ("Failed")
		except:
			return ("Manual")


@fail_with_manual
class CheckNetworkPolicies(AKSBaseControlTest):
	name = "Use_Network_Policy"

	def __init__(self):
		super().__init__()
		self.desc = "Network policies should be used to perform network segmentation within cluster"

	@fail_with_manual
	def test(self):
		try:
			v1networkPolicyApi = client.NetworkingV1Api()
			network_policy_response = v1networkPolicyApi.list_network_policy_for_all_namespaces()
			if len(network_policy_response.items) > 0:
				return ("Passed")
			else:
				return("Failed")

		except:
			return ("Manual")


@fail_with_manual
class CheckLimitRanges(AKSBaseControlTest):
	name = "Use_Limit_Range"

	def __init__(self):
		super().__init__()
		self.desc = ("LimitRanges should be used to constrain resource allocations")

	@fail_with_manual
	def test(self):
		try:
			v1coreApi = client.CoreV1Api()

			namespace_response = v1coreApi.list_namespace()
			all_namespaces = set()
			for namespace in namespace_response.items:
				all_namespaces.add(namespace.metadata.name)
			all_namespaces = all_namespaces - self.pods_allowed_namespaces

			limit_range_response = v1coreApi.list_limit_range_for_all_namespaces()
			for limit_range in limit_range_response.items:
				all_namespaces.remove(limit_range.metadata.namespace)

			if len(all_namespaces) > 0:
				self.detailed_logs["type"] = "non_compliant_namespaces"
				self.detailed_logs["desc"] = self.desc + "\nFollowing namespace(s) do not have a limit range associated with them:"
				self.detailed_logs["logs"] = list(all_namespaces)
				return ("Failed")
			else:
				return ("Passed")
		except:
			return ("Manual")


@fail_with_manual
class CheckResourceQuotas(AKSBaseControlTest):
	name = "Use_Resource_Quotas"

	def __init__(self):
		super().__init__()
		self.desc = ("ResourceQuotas should be used to constrain aggregate resource consumption")

	@fail_with_manual
	def test(self):
		try:
			v1coreApi = client.CoreV1Api()

			namespace_response = v1coreApi.list_namespace()
			all_namespaces = set()
			for namespace in namespace_response.items:
				all_namespaces.add(namespace.metadata.name)
			all_namespaces = all_namespaces - self.pods_allowed_namespaces

			resource_quotas_response = v1coreApi.list_resource_quota_for_all_namespaces()
			for resource_quota in resource_quotas_response.items:
				all_namespaces.remove(resource_quota.metadata.namespace)

			if len(all_namespaces) > 0:
				self.detailed_logs["type"] = "non_compliant_namespaces"
				self.detailed_logs["desc"] = self.desc + "\nFollowing namespace(s) do not have a resource quota associated with them:"
				self.detailed_logs["logs"] = list(all_namespaces)
				return ("Failed")
			else:
				return ("Passed")
		except:
			return ("Manual")


@fail_with_manual
class CheckRoleBindings(AKSBaseControlTest):
	name = "Use_Roles_And_Role_Bindings"

	def __init__(self):
		super().__init__()
		self.desc = ("Role/RoleBinding objects must be used to impose access restrictions")

	@fail_with_manual
	def test(self):
		try:
			v1coreApi = client.CoreV1Api()

			namespace_response = v1coreApi.list_namespace()
			all_namespaces = set()
			for namespace in namespace_response.items:
				all_namespaces.add(namespace.metadata.name)
			all_namespaces = all_namespaces - self.pods_allowed_namespaces

			v1rbacApi = client.RbacAuthorizationV1Api()
			role_bindings_response = v1rbacApi.list_role_binding_for_all_namespaces()
			for role_binding in role_bindings_response.items:
				if role_binding.metadata.namespace in all_namespaces:
					all_namespaces.remove(role_binding.metadata.namespace)

			if len(all_namespaces) > 0:
				self.detailed_logs["type"] = "non_compliant_namespaces"
				self.detailed_logs["desc"] = self.desc + "\nFollowing namespace(s) do not have any role bindings associated with them:"
				self.detailed_logs["logs"] = list(all_namespaces)
				return ("Failed")
			else:
				return ("Passed")
		except:
			return ("Manual")


@fail_with_manual
class CheckMountedImages(AKSBaseControlTest):
	name = "Review_Mounted_Images_Source"

	def __init__(self):
		super().__init__()
		self.desc = ("Container images deployed in cluster must be from a trustworthy source")

	@fail_with_manual
	def test(self):
		v1 = client.CoreV1Api()
		node_response = v1.list_node(watch=False)
		nodes = list(node_response.items)
		image_list = []
		for node in nodes:
			images = node.status.images
			for image in images:
				image_list.append(image.names)
		
		images = [image for sublist in image_list for image in sublist if '@sha' not in image]
        # Filter trustworthy image sources
		images = [image for image in images if image.split('/')[0] not in self.trustworthy_image_sources]

		if len(images) > 0:
			self.detailed_logs["type"] = "container_images"
			self.detailed_logs["desc"] = self.desc + "\nFollowing container image(s) are mounted in cluster:"
			self.detailed_logs["logs"] = images

		return ("Verify")


@fail_with_manual
class CheckExternalServices(AKSBaseControlTest):
	name = "Review_Publicly_Exposed_Services"

	def __init__(self):
		super().__init__()
		self.desc = ("Services with external IP must be reviewed")

	@fail_with_manual
	def test(self):
		try:
			v1 = client.CoreV1Api()
			service_response = v1.list_service_for_all_namespaces(watch=False)
			services_with_external_ip = list(filter(lambda x: x.spec.type.lower() == "loadbalancer", service_response.items))
			if len(services_with_external_ip) == 0:
				return("Passed")
			else:
				non_compliant_services = [(service.metadata.namespace, service.metadata.name) for service in services_with_external_ip]
				self.detailed_logs["type"] = "non_compliant_services"
				self.detailed_logs["desc"] = self.desc + "\nFollowing service(s) have external IP configured:"
				self.detailed_logs["logs"] = non_compliant_services
				return("Verify")
		except:
			return("Manual")


@fail_with_manual
class CheckCertificateRotation(AKSBaseControlTest):
	name = "Rotate_AuthN_Certificates"

	def __init__(self):
		super().__init__()
		self.desc = ("Certificates used for authentication should be rotated periodically")

	@fail_with_manual
	def test(self):
		self.detailed_logs["type"] = "recommendations"
		self.detailed_logs["desc"] = self.desc + "\nThis has to be done for security and policy reasons. This is consequential in cases of role assignment changes and can be used as a means to invalidate existing certificates.\nFor more information, please refer : https://docs.microsoft.com/en-us/azure/aks/certificate-rotation"
		return ("Verify")


@fail_with_manual
class CheckAppArmorSeccomp(AKSBaseControlTest):
	name = "Restrict_Capabilities_And_Permissions"

	def __init__(self):
		super().__init__()
		self.desc = ("Security modules should be used to limit actions containers can perform")

	@fail_with_manual
	def test(self):
		self.detailed_logs["type"] = "recommendations"
		self.detailed_logs["desc"] = self.desc + "\nSecurity modules like apparmor or seccomp provide a more granular control of container actions. You create AppArmor profiles that restrict actions such as read, write, or execute, or system functions such as mounting filesystems. Seccomp is also a Linux kernel security module, and is natively supported by the Docker runtime used by AKS nodes. With seccomp, the process calls that containers can perform are limited.\nFor more information, please refer : https://docs.microsoft.com/en-us/azure/aks/operator-best-practices-cluster-security#secure-container-access-to-resources"
		return ("Verify")


@fail_with_manual
class CheckFirewallForEgressTraffic(AKSBaseControlTest):
	name = "Restrict_Egress_Traffic"

	def __init__(self):
		super().__init__()
		self.desc = ("Firewall should be configured to restrict egress traffic")

	@fail_with_manual
	def test(self):
		self.detailed_logs["type"] = "recommendations"
		self.detailed_logs["desc"] = self.desc + "\nBy default, AKS clusters have unrestricted outbound (egress) internet access. To increase the security of your AKS cluster, it is recommended to use Azure Firewall.\nFor more information, please refer : https://docs.microsoft.com/en-us/azure/aks/limit-egress-traffic"
		return ("Verify")


@fail_with_manual
class CheckClusterEvents(AKSBaseControlTest):
	name = "Review_Cluster_Events"

	def __init__(self):
		super().__init__()
		self.desc = ("Cluster events must be reviewed periodically")

	@fail_with_manual
	def test(self):
		try:
			v1coreApi = client.CoreV1Api()
			event_response = v1coreApi.list_event_for_all_namespaces()
			self.detailed_logs["type"] = "event_logs"
			self.detailed_logs["desc"] = "\nFollowing event(s) have occured inside the cluster:"
			self.detailed_logs["logs"] = [{ "involved_object": event.involved_object.kind + "/" + event.involved_object.name, "message": event.message, "reason": event.reason, "type": event.type } for event in event_response.items]
			return ("Verify")
		except:
			return ("Manual")