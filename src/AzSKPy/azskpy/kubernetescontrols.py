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
				config.load_incluster_config()
				v1 = client.CoreV1Api()
				pod_response = v1.list_pod_for_all_namespaces(watch=False)
				pods = list(filter(lambda x: x.metadata.namespace != 'kube-system', pod_response.items))
				self.resources['pods'] = pods
				serviceacc_response = v1.list_service_account_for_all_namespaces(watch=False)
				service_accounts = list(
					filter(lambda x: x.metadata.namespace != 'kube-system', serviceacc_response.items))
				self.resources['service_accounts'] = service_accounts
				self.resources['SUBSCRIPTION_ID'] = os.environ.get("SUBSCRIPTION_ID", None)
				self.resources['RG_NAME'] = os.environ.get("RG_NAME", None)
				self.resources['RESOURCE_NAME'] = os.environ.get("RESOURCE_NAME", None)
				self.resources['APP_INSIGHT_KEY'] = os.environ.get("APP_INSIGHT_KEY", None)
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
		self.detailed_logs = {'desc':               "", 'control_id': "", 'non_compliant_containers': [],
							  'service_accounts':   [], 'non_compliant_pods': [], 'pods_with_secrets': [],'container_images' : [], 'non_compliant_services':[]}

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
				if container.name != 'azsk-ca-job':
					security_context = container.security_context
					run_as_non_root = getattr(security_context, 'run_as_non_root', pod_run_as_non_root)
					if run_as_non_root == None:
						run_as_non_root = pod_run_as_non_root
					allow_privilege_escalation = getattr(security_context, 'allow_privilege_escalation',
														 pod_allow_privilege_escalation)
					read_only_root_filesystem = getattr(security_context, 'read_only_root_filesystem',
														pod_read_only_root_filesystem)
					info = copy.deepcopy(info)
					info['container'] = container.name
					info['run_as_non_root'] = run_as_non_root
					info['allow_privilege_escalation'] = allow_privilege_escalation
					info['read_only_root_filesystem'] = read_only_root_filesystem
					result.append(info)
		non_compliant_containers = filter(lambda x: x[property] != expected_value, result)
		return non_compliant_containers

	def set_credentials(self, uname, password):
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

	def test(self):
		non_compliant_containers = []
		if len(self.pods) > 0:
			non_compliant_containers = list(self.CheckSecurityConfig('run_as_non_root', True))
		else:
			return "Manual"
		if len(non_compliant_containers) > 0:
			self.detailed_logs[
				'desc'] = self.desc + "\nFor following container(s), runAsNonRoot is either set to 'False' or 'None':"
			self.detailed_logs['non_compliant_containers'] = non_compliant_containers
			return ("Failed")
		else:
			return ("Passed")


@fail_with_manual
class CheckContainerPrivilegeEscalation(AKSBaseControlTest):
	name = "Restrict_Container_Privilege_Escalation"

	def __init__(self):
		super().__init__()
		self.desc = ("Container should not allow privilege escalation")

	def test(self):
		non_compliant_containers = []
		if len(self.pods) > 0:
			non_compliant_containers = list(self.CheckSecurityConfig('allow_privilege_escalation', False))
		else:
			return ("Manual")
		if len(non_compliant_containers) > 0:
			self.detailed_logs[
				'desc'] = self.desc + "\nFor Following container(s), allowPrivilegeEscalation is either set to 'True' or 'None':"
			self.detailed_logs['non_compliant_containers'] = non_compliant_containers
			return ("Failed")
		else:
			return ("Passed")


@fail_with_manual
class CheckContainerReadOnlyRootFilesystem(AKSBaseControlTest):
	name = "Set_Read_Only_Root_File_System"

	def __init__(self):
		super().__init__()
		self.desc = ("Container should not be allowed to write to the root/host filesystem")

	def test(self):
		non_compliant_containers = []
		if len(self.pods) > 0:
			non_compliant_containers = list(self.CheckSecurityConfig('read_only_root_filesystem', True))
		else:
			return ("Manual")
		if len(non_compliant_containers) > 0:
			self.detailed_logs[
				'desc'] = self.desc + "\nFor Following container(s), readOnlyRootFilesystem is either set to 'False' or 'None':"
			self.detailed_logs['non_compliant_containers'] = non_compliant_containers
			return ("Failed")
		else:
			return ("Passed")


@fail_with_manual
class CheckInactiveServiceAccounts(AKSBaseControlTest):
	name = "Remove_Inactive_Service_Accounts"

	def __init__(self):
		super().__init__()
		self.desc = ("Cluster should not have any inactive service account")

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
			self.detailed_logs[
				'desc'] = self.desc + "\nFollowing service account(s) are not referenced by any pod/container:"
			self.detailed_logs['service_accounts'] = inactive_svc_accounts
			return ("Failed")
		else:
			return ("Passed")


@fail_with_manual
class CheckClusterManagedIdentity(AKSBaseControlTest):
	name = "Use_Managed_Service_Identity"

	def __init__(self):
		super().__init__()
		self.desc = ("Managed System Identity (MSI) should be used to access Azure resources from cluster")

	def test(self):
		if len(self.pods) > 0:
			result = "Failed"
		else:
			return "Manual"

		for item in self.pods:
			if item.metadata.name.find("mic-") != -1 and item.spec.containers[0].image.find(
					"mcr.microsoft.com/k8s/aad-pod-identity/mic") != -1:
				result = "Verify"
		return result


class CheckDefaultSvcRoleBinding(AKSBaseControlTest):
	name = "Dont_Bind_Role_To_Default_Svc_Acc"

	def __init__(self):
		super().__init__()
		self.desc = ("Default service account should not be assigned any cluster role")

	@fail_with_manual
	def test(self):
		is_failed = False
		config.load_incluster_config()
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
					if container.name != 'azsk-ca-job':
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
			self.detailed_logs['desc'] = self.desc + "\nFollowing container(s) will run in the privileged mode:"
			self.detailed_logs['non_compliant_containers'] = non_compliant_containers
			return ("Failed")
		else:
			return ("Passed")


class CheckDefaultNamespaceResources(AKSBaseControlTest):
	name = "Dont_Use_Default_Namespace"

	def __init__(self):
		super().__init__()
		self.desc = ("Do not use the default cluster namespace to deploy applications")

	@fail_with_manual
	def test(self):
		pods_in_default_namespace = []
		if len(self.pods) > 0:
			pods_in_default_namespace = list(filter(lambda x: x.metadata.namespace == 'default', self.pods))
		else:
			return ("Manual")
		if len(pods_in_default_namespace) > 0:
			non_compliant_pods = []
			self.detailed_logs['desc'] = self.desc + "\nFollowing pods(s) are present in default namespace:"
			for pod in pods_in_default_namespace:
				non_compliant_pods.append(pod.metadata.name)
			self.detailed_logs['non_compliant_pods'] = non_compliant_pods
			return ("Failed")
		else:
			return ("Passed")


class CheckResourcesWithSecrets(AKSBaseControlTest):
	name = "Use_KeyVault_To_Store_Secret"

	def __init__(self):
		super().__init__()
		self.desc = ("Use Azure Key Vault to store credentials/keys")

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
						secret_key_refs = []
						if container.env != None and len(container.env) > 0:
							secret_key_refs = list(
								filter(lambda x: x.value_from != None and x.value_from.secret_key_ref != None,
									   container.env))
						if len(secret_key_refs) > 0:
							is_secret_mounted = True

				if is_secret_mounted:
					pods_with_secrets.append(info)
		else:
			return ("Manual")
		if len(pods_with_secrets) > 0:
			self.detailed_logs[
				'desc'] = self.desc + "\nFollowing pod(s) are using Kubernetes secret objects to store secrets:"
			self.detailed_logs['pods_with_secrets'] = pods_with_secrets
			return ("Failed")
		else:
			return ("Passed")


class CheckKubernetesVersion(AKSBaseControlTest):
	name = "Use_Latest_Kubernetes_Version"

	def __init__(self):
		super().__init__()
		self.desc = ("The latest version of Kubernetes should be used")

	@fail_with_manual
	def test(self):
		config.load_incluster_config()
		v1 = client.CoreV1Api()
		res = v1.list_node(watch=False)
		nodes = list(res.items)
		if len(nodes) > 0:
			try:
				node = nodes[0]
				cur_version = node.status.node_info.kubelet_version
				cur_version = cur_version.replace("v", "")
				req_version = '1.14.6'
				if StrictVersion(req_version) > StrictVersion(cur_version):
					return ("Failed")
				else:
					return ("Passed")

			except:
				return ("Manual")

		else:
			return ("Manual")

class CheckMountedImages(AKSBaseControlTest):
	name = "Review_Mounted_Images_Source"

	def __init__(self):
		super().__init__()
		self.desc = ("Make sure container images deployed in cluster are trustworthy")

	@fail_with_manual
	def test(self):
		config.load_incluster_config()
		v1 = client.CoreV1Api()
		res = v1.list_node(watch=False)
		nodes = list(res.items)
		image_list = []
		whitelisted_sources = ['k8s.gcr.io','microsoft']
		for node in nodes:
			images = node.status.images
			for image in images:
				image_list.append(image.names)
		
		images = [image for sublist in image_list for image in sublist if '@sha' not in image]
        # Filter whitelisted images 
		images = [image for image in images if image.split('/')[0] not in whitelisted_sources]

		if len(images) > 0:
			self.detailed_logs[
			'desc'] = self.desc + "\nFollowing container images are mounted in Cluster:"
			self.detailed_logs['container_images'] = images

		return ("Verify")


class CheckExternalServices(AKSBaseControlTest):
	name = "Review_Publicly_Exposed_Services"

	def __init__(self):
		super().__init__()
		self.desc = ("Review services with external IP")

	@fail_with_manual
	def test(self):
		config.load_incluster_config()
		try:
			v1 = client.CoreV1Api()
			res = v1.list_service_for_all_namespaces(watch=False)
			services = list(res.items)
			services_with_external_ip = [service for service in services if service.spec.type.lower() == 'loadbalancer']
			if len(services_with_external_ip) == 0:
				return('Passed')
			else:
				non_compliant_services = [(service.metadata.namespace, service.metadata.name) for service in services_with_external_ip]
				self.detailed_logs['desc'] = self.desc + "\nFollowing service(s) have external IP configured:"
				self.detailed_logs['non_compliant_services'] = non_compliant_services
				return("Verify")
		except:
			return("Manual")

		