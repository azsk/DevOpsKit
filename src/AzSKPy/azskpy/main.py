# ------------------------------------------------------------------------------
# Copyright (c) Microsoft Corporation. All rights reserved.
# Licensed under the MIT License. See License in the project root for
# license information.
# ------------------------------------------------------------------------------
from applicationinsights import TelemetryClient
from datetime import datetime
from .constants import __version__
from .kubernetescontrols import *
from .sparkcontrols import *
from .loganalytics import LogAnalyticsClient

sct = None


class DBSparkControlTester:
	def __init__(self, **kwargs):
		self.context = None
		self.kwargs = kwargs
		self.context = "databricks"
		self.controls = [DiskEncryptionEnabled, StorageEncryptionKeySize, CheckNumberOfAdminsDB,
						 CheckGuestAdmin, SameKeyvaultReference, AccessTokenExpiry, NonKeyvaultBackend,
						 ExternalLibsInstalled, InitScriptPresent, MountPointPresent, TokenNearExpiry]
		self.detailed_logs = []

	def line(self):
		print("-" * 123)

	def run_single_cluster(self, spark_context: dict, cluster_name):
		df = pd.DataFrame(columns=["ControlName",
								   "ControlDescription",
								   "Result"])
		for Control in self.controls:
			control = Control(spark_context, **self.kwargs)
			result = control.test()
			self.detailed_logs.append(result)
			df = df.append({
				"ControlName":        Control.name,
				"ControlDescription": control.desc,
				"Result":             result.result
			}, ignore_index=True)
		self.print_report(df)
		self.save_report(df)
		self.print_detailed_logs()
		self.send_telemetry_app_insights(df, cluster_name)
		self.send_events_log_analytics(df, cluster_name)
		return df

	def print_detailed_logs(self):
		print("\n\nDetailed Logs")
		self.line()
		for result in self.detailed_logs:
			print(result)
			self.line()

	def run(self):
		spark_contexts = self.get_db_clusters_config()
		print("DevOps Kit (AzSK) for Cluster Security v", __version__)
		scan_result_dfs = []
		for (spark_context, cluster_name) in spark_contexts:
			self.line()
			print("Running cluster scan for cluster: {}".format(cluster_name))
			df = self.run_single_cluster(spark_context, cluster_name)
			scan_result_dfs.append(df)
		print("AzSK Scan Completed")
		self.update_post_scan_meta()
		return scan_result_dfs

	def invoke_rest_api(self, end_point, body=None):
		databricks_base_url = self.get_secret("DatabricksHostDomain")
		pat = self.get_secret("AzSK_CA_Scan_Key")
		url = databricks_base_url + "/api/2.0/" + end_point
		header = {
			"Authorization": "Bearer " + pat,
			"Content-type":  "application/json"
		}
		try:
			if body:
				res = requests.get(url=url, headers=header, json=body)
			else:
				res = requests.get(url=url, headers=header)
			response = res.json()
		except Exception as e:
			print("Error making GET request")
			print(e)
			response = {}
		return response

	def get_db_clusters_config(self):
		config = self.invoke_rest_api("clusters/list")
		configs = []
		for x in config["clusters"]:
			if x["cluster_source"] != "JOB":
				configs.append((x["spark_conf"], x["cluster_name"]))
		return configs

	def get_secret(self, key):
		dbutils = self.kwargs["dbutils"]
		return dbutils.secrets.get(scope="AzSK_CA_Secret_Scope",
								   key=key)

	def get_ik(self):
		try:
			ik = self.get_secret("AzSK_AppInsight_Key")
		except Exception as e:
			ik = None
		return ik

	def print_report(self, df):
		print("{0: <45}{1: <70}{2: <8}".format("Control ID",
											   "Control Description",
											   "Status"))
		self.line()
		for indx, x in df.iterrows():
			print("{0: <45}{1: <70}{2: <8}".format(x["ControlName"],
												   x["ControlDescription"],
												   x["Result"]))
		self.line()

	def get_base_telemetry(self):
		return {
			"ResourceType":       "Databricks",
			"EventName":          "Control Scanned",
			"ResourceName":       self.get_secret("res_name"),
			"SubscriptionId":     self.get_secret("sid"),
			"ResourceGroupName":  self.get_secret("rg_name"),
			"ControlID":          None,
			"VerificationResult": None
		}

	def send_telemetry_app_insights(self, df, cluster_name):
		ik = self.get_ik()
		df = df[["ControlName", "Result"]]
		if ik is None:
			print("Skipping Telemetry")
		else:
			df_dict = df.to_dict("list")
			df_dict = {x: y for x, y in
					   zip(df_dict["ControlName"], df_dict["Result"])}
			tc = TelemetryClient(ik)
			for control_name in df_dict:
				tm_dict = self.get_base_telemetry()
				tm_dict["ControlID"] = control_name
				tm_dict["VerificationResult"] = df_dict[control_name]
				tm_dict["ClusterName"] = cluster_name
				tc.track_event("Scan Results", tm_dict)
			tc.flush()
			print("Telemetry Sent")

	def save_report(self, df):
		self.dbutils = self.kwargs["dbutils"]
		self.dbutils.fs.mkdirs("/AzSK_Logs/")
		timestamp = str(datetime.now()).replace(" ", "_").replace("-", "").replace(":", "")[:-7]
		df.to_csv("/dbfs/AzSK_Logs/AzSK_Scan_Results_{}.csv"
				  .format(timestamp))

	def update_post_scan_meta(self):
		dbutils = self.kwargs["dbutils"]
		dbutils.fs.mkdirs("/AzSK_Meta/")
		data = {
			"Last Scan": str(datetime.now()),
			"Log Analytics Workspace ID": self.get_secret("LAWorkspaceId"),
			"Databricks Cluster": self.get_secret("res_name"),
			"Databricks Resource Group": self.get_secret("rg_name"),
			"Subscription ID": self.get_secret("sid")
		}
		dbutils.fs.put("/AzSK_Meta/meta.json", str(data), overwrite=True)

	def send_events_log_analytics(self, df, cluster_name):
		oms_workspace_id = self.get_secret("LAWorkspaceId")
		shared_key = self.get_secret("LASharedSecret")
		la_client = LogAnalyticsClient(oms_workspace_id, shared_key)
		df_dict = df.to_dict("list")
		df_dict = {x: y for x, y in
				   zip(df_dict["ControlName"], df_dict["Result"])}
		tm_list = []
		for control_name in df_dict:
			tm_dict = self.get_base_telemetry()
			tm_dict["ControlID"] = control_name
			tm_dict["VerificationResult"] = df_dict[control_name]
			tm_dict["ClusterName"] = cluster_name
			tm_list.append(tm_dict)
		la_client.post_data(tm_list, "AzSKInCluster")

	def get_recommendations(self):
		for control in self.controls:
			print("Control Name:", control.name)
			print("Control Description:", control.desc)
			print("Recommendation:", control.recommendation)
			self.line()
		print("Note: Controls marked as (+) will need spark.authenticate.password to be set. You can choose the "
			  "password of your choice.")


class HDISparkControlTester:
	def __init__(self, spark_context, **kwargs):
		self.spark_context = spark_context
		self.context = None
		self.kwargs = kwargs
		self.context = "hdinsight"
		self.controls = [DiskEncryptionEnabled,
						 AuthenticationEnabled, RPCEnabled,
						 EnableSASLEncryption,
						 SASLAlwaysEncrypt, StorageEncryptionKeySize]
		self.detailed_logs = []

	def line(self):
		print("-" * 123)

	def run(self):
		print("DevOps Kit (AzSK) for Cluster Security v", __version__)
		self.line()
		df = pd.DataFrame(columns=["ControlName",
								   "ControlDescription",
								   "Result"])

		for Control in self.controls:
			control = Control(self.spark_context, **self.kwargs)
			result = control.test()
			self.detailed_logs.append(result)
			df = df.append({
				"ControlName":        Control.name,
				"ControlDescription": control.desc,
				"Result":             result.result
			}, ignore_index=True)
		self.print_report(df)
		self.print_detailed_logs()
		self.save_report(df)
		self.send_telemetry(df)
		return df

	def print_detailed_logs(self):
		print("\n\nDetailed Logs")
		self.line()
		for result in self.detailed_logs:
			print(result)
			self.line()

	def get_ik(self):
		ik = self.kwargs["app_insight_key"]
		if ik != "":
			return ik
		else:
			return ""

	def print_report(self, df):
		print("{0: <45}{1: <70}{2: <8}".format("Control ID", "Control Description", "Status"))
		self.line()
		for indx, x in df.iterrows():
			print("{0: <45}{1: <70}{2: <8}".format(x["ControlName"], x["ControlDescription"], x["Result"]))
		self.line()

	def send_telemetry(self, df):
		ik = self.get_ik()
		df = df[["ControlName", "Result"]]
		if ik == "":
			print("Skipping Telemetry")
		else:
			df_dict = df.to_dict("list")
			df_dict = {x: y for x, y in zip(df_dict["ControlName"], df_dict["Result"])}
			tc = TelemetryClient(ik)
			tc.track_event("Scan Results", df_dict)
			tc.flush()
			print("Telemetry Sent to Application Insights")

	def save_report(self, df):
		current_scan_time = str(datetime.now())
		gca_metadata = {
			"CA Version": [__version__],
			"Last Scan": [current_scan_time],
			"App Insight Key": [self.get_ik()],
			"Subscription Id": [self.kwargs.get("sid")],
			"Resource Group Name": [self.kwargs.get("rg_name")],
			"Resource Name": [self.kwargs.get("res_name")],
			"CA Notebook Path": ["/PySpark/AzSK_CA_Note"],
			"Metadata Store Path": ["/AzSK_Metadata/"],
			"Scan Logs Sore Path": ["/AzSK_Logs/"]
		}
		current_scan_time = current_scan_time.replace(" ", "-").replace(":", "-")
		gca_metadata_df = pd.DataFrame.from_dict(gca_metadata)
		scanlog_df = pd.DataFrame(df)
		spark_metadata_rdd = self.spark_context.createDataFrame(gca_metadata_df)
		spark_metadata_rdd.write.json(HDI_METADATA_WRITE_PATH.format(current_scan_time))
		scanlog_rdd = self.spark_context.createDataFrame(scanlog_df)
		scanlog_rdd.write.json(HDI_SCANLOG_WRITE_PATH.format(current_scan_time))

	def get_recommendations(self):
		for control in self.controls:
			print("Control Name:", control.name)
			print("Control Description:", control.desc)
			print("Recommendation:", control.recommendation)
			self.line()
		print("Note: Controls marked as (+) will need spark.authenticate.password to be set. You can choose the "
			  "password of your choice.")


def get_databricks_security_scan_status(**kwargs):
	global sct
	sct = DBSparkControlTester(**kwargs)
	sct.run()


def get_hdinsight_security_scan_status(spark_context, **kwargs):
	global sct
	sct = HDISparkControlTester(spark_context, **kwargs)
	sct.run()
	return sct


def get_spark_recommendations():
	global sct
	if sct is None:
		print("No context found, please run `get_cluster_security_scan_status` first to instantiate the tester")
	else:
		sct.get_recommendations()


class AKSControlTester:
	def __init__(self):
		self.context = "kubernetes"
		self.controls = [CheckContainerRunAsNonRoot,
						 CheckContainerPrivilegeEscalation,
						 CheckContainerPrivilegeMode,
						 CheckInactiveServiceAccounts,
						 CheckClusterPodIdentity,
						 CheckContainerReadOnlyRootFilesystem,
						 CheckDefaultSvcRoleBinding,
						 CheckDefaultNamespaceResources,
						 CheckResourcesWithSecrets,
						 CheckKubernetesVersion,
						 CheckExternalServices,
						 CheckMountedImages,
						 CheckForKured,
						 CheckResourcesLimitsAndRequests,
						 CheckStorageClassReclaimPolicy,
						 CheckPodSecurityPolicies,
						 CheckNetworkPolicies,
						 CheckLimitRanges,
						 CheckResourceQuotas,
						 CheckRoleBindings,
						 CheckClusterEvents,
						 CheckAppArmorSeccomp,
						 CheckFirewallForEgressTraffic,
						 CheckCertificateRotation]

	def run(self):
		print("DevOps Kit (AzSK) for Cluster Security v", __version__)
		self.line()
		df = pd.DataFrame(columns=["ControlName",
								   "ControlDescription",
								   "Result"])
		detailed_logs_list = []
		for Control in self.controls:
			control = Control()
			result = control.test()
			control.detailed_logs['control_id'] = Control.name
			detailed_logs_list.append(control.detailed_logs)
			result_item = {
				"ControlName":        Control.name,
				"ControlDescription": control.desc,
				"Result":             result
			}
			df = df.append(result_item, ignore_index=True)
			control.send_telemetry("AzSK AKS Control Scanned", result_item)

		self.print_report(df)
		self.print_detailed_logs(detailed_logs_list)
		self.save_report(df)

	def line(self):
		print("-" * 138)

	def send_events_log_analytics(self, df, cluster_name):
		oms_workspace_id = self.get_secret("LAWorkspaceId")
		shared_key = self.get_secret("LASharedSecret")
		la_client = LogAnalyticsClient(oms_workspace_id, shared_key)
		df_dict = df.to_dict("list")
		df_dict = {x: y for x, y in
				   zip(df_dict["ControlName"], df_dict["Result"])}
		tm_list = []
		for control_name in df_dict:
			tm_dict = self.get_base_telemetry()
			tm_dict["ControlID"] = control_name
			tm_dict["VerificationResult"] = df_dict[control_name]
			tm_dict["ClusterName"] = cluster_name
			tm_list.append(tm_dict)
		la_client.post_data(tm_list, "AzSKInCluster")

	def save_report(self, df):
		# TODO: Needs to be implemented? Check
		pass

	def print_report(self, df):
		print("   {0: <40}{1: <85}{2: <10}".format("Control ID", "Control Description", "Status"))
		self.line()
		for indx, x in df.iterrows():
			print("{0: <3}{1: <40}{2: <85}{3: <10}".format(indx + 1, x["ControlName"], x["ControlDescription"],
														   x["Result"]))
		self.line()

	def print_detailed_logs(self, detailed_logs_ls):
		print("\n")
		self.line()
		print("Detailed Logs:")
		self.line()
		detailed_log_printed = False
		for detailed_logs_item in detailed_logs_ls:
			if detailed_logs_item["type"] == "non_compliant_containers":
				detailed_log_printed = True
				df = pd.DataFrame(detailed_logs_item["logs"])
				print("{0} : {1}".format(detailed_logs_item['control_id'], detailed_logs_item['desc']))
				print("   {0: <25}{1: <50}{2: <25}".format("Namespace", "Pod", "Container"))
				for indx, x in df.iterrows():
					print("{0: <3}{1: <25}{2: <50}{3: <25}".format(indx + 1, x["namespace"], x["pod_name"], x["container"]))
				self.line()
			elif detailed_logs_item["type"] == "service_accounts":
				detailed_log_printed = True
				print("{0} : {1}".format(detailed_logs_item['control_id'], detailed_logs_item['desc']))
				df = pd.DataFrame(list(detailed_logs_item["logs"]),
								  columns=['ServiceAccountName', 'NameSpace'])
				print("   {0: <25}{1: <50}".format("Namespace", "ServiceAccount"))
				for indx, x in df.iterrows():
					print("{0: <3}{1: <25}{2: <50}".format(indx + 1, x[1], x[0]))
				self.line()
			elif detailed_logs_item["type"] == "non_compliant_pods":
				detailed_log_printed = True
				print("{0} : {1}".format(detailed_logs_item['control_id'], detailed_logs_item['desc']))
				for pod in detailed_logs_item["logs"]:
					print(pod["pod_name"])
				self.line()
			elif detailed_logs_item["type"] == "pods_with_secrets":
				detailed_log_printed = True
				print("{0} : {1}".format(detailed_logs_item['control_id'], detailed_logs_item['desc']))
				df = pd.DataFrame(list(detailed_logs_item["logs"]))
				print("   {0: <25}{1: <50}".format("Namespace", "Pod"))
				for indx, x in df.iterrows():
					print("{0: <3}{1: <25}{2: <50}".format(indx + 1, x[0], x[1]))
				self.line()
			elif detailed_logs_item["type"] == "non_compliant_namespaces":
				detailed_log_printed = True
				print("{0} : {1}".format(detailed_logs_item['control_id'], detailed_logs_item['desc']))
				for namespace in detailed_logs_item["logs"]:
					print(namespace)
				self.line()
			elif detailed_logs_item["type"] == "storage_class_delete_reclaim_policy":
				detailed_log_printed = True
				print("{0} : {1}".format(detailed_logs_item['control_id'], detailed_logs_item['desc']))
				for storage_class in detailed_logs_item["logs"]:
					print(storage_class["name"])
				self.line()
			elif detailed_logs_item["type"] == "missing_resource_limits_requests_pods":
				detailed_log_printed = True
				print("{0} : {1}".format(detailed_logs_item['control_id'], detailed_logs_item['desc']))
				print("   {0: <25}{1: <50}{2: <25}{3: <50}".format("Namespace", "Pod", "Container", "Issue"))
				indx = 1
				for check_data in detailed_logs_item["logs"]:
					for check in check_data["checks"]:
						print("{0: <3}{1: <25}{2: <50}{3: <25}{4: <50}".format(indx, check_data["namespace"], check_data["pod_name"], check_data["container"], check))
						indx += 1
				self.line()
			elif detailed_logs_item["type"] == "container_images":
				detailed_log_printed = True
				print("{0} : {1}".format(detailed_logs_item['control_id'], detailed_logs_item['desc']))
				df = pd.DataFrame(list(detailed_logs_item['logs']))
				for indx, x in df.iterrows():
					print("{0: <3}{1: <25}".format(indx + 1, x[0]))
				self.line()
			elif detailed_logs_item["type"] == "non_compliant_services":
				detailed_log_printed = True
				print("{0} : {1}".format(detailed_logs_item['control_id'], detailed_logs_item['desc']))
				df = pd.DataFrame(list(detailed_logs_item['logs']),
								  columns=['NameSpace','ServiceName'])
				print("   {0: <25}{1: <50}".format("Namespace", "Service Name"))
				for indx, x in df.iterrows():
					print("{0: <3}{1: <25}{2: <50}".format(indx + 1, x[0], x[1]))
				self.line()
			elif detailed_logs_item["type"] == "recommendations":
				detailed_log_printed = True
				print("{0} : {1}".format(detailed_logs_item['control_id'], detailed_logs_item['desc']))
				self.line()
			elif detailed_logs_item["type"] == "event_logs":
				detailed_log_printed = True
				print("{0} : {1}".format(detailed_logs_item['control_id'], detailed_logs_item['desc']))
				df = pd.DataFrame(list(detailed_logs_item["logs"]))
				print("   {0: <50}{1: <25}{2: <25}{3: <50}".format("Object", "Reason", "Type", "Message"))
				for indx, x in df.iterrows():
					print("{0: <3}{1: <50}{2: <25}{3: <25}{4: <50}".format(indx + 1, x["involved_object"], x["reason"], x["type"], x["message"]))
				self.line()

		if (not detailed_log_printed):
			print("No detailed logs to show.")
			self.line()

def run_aks_cluster_scan():
	AKSControlTester().run()
