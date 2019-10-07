# ------------------------------------------------------------------------------
# Copyright (c) Microsoft Corporation. All rights reserved.
# Licensed under the MIT License. See License in the project root for
# license information.
# ------------------------------------------------------------------------------
import json

import requests
import pandas as pd
import numpy as np
from datetime import datetime
from .constants import *
from .utils import fail_with_manual, TestResponse


class BaseControlTest:
	def __init__(self, spark_context, **runtime_params):
		self.spark = spark_context
		self.runtime_params = runtime_params
		# spark_context will be dictionary, if the environment is
		# Databricks. Else it will be an instance of spark
		if isinstance(spark_context, dict):
			self.__dictconfig = spark_context
		else:
			self.__config = self.spark.sparkContext.getConf().getAll()
			self.__dictconfig = {}
			for setting in self.__config:
				self.__dictconfig[setting[0]] = setting[1]

	@property
	def config(self):
		return self.__dictconfig

	def fail_by_default_check(self, spark_setting, desired_value="true"):
		if spark_setting not in self.config:
			# name will be set in the inherited class
			return TestResponse(self.name, spark_setting + " in spark settings",
								spark_setting + " was not set", FAILED)
		if self.config[spark_setting] != desired_value:
			return TestResponse(self.name, spark_setting + " in spark settings",
								spark_setting + " was not set", FAILED)
		else:
			return TestResponse(self.name, spark_setting + " in spark settings",
								spark_setting + " was set as expected", PASSED)

	def pass_by_default_check(self, spark_setting, desired_value="true"):
		if spark_setting not in self.config:
			return TestResponse(self.name, spark_setting + " in spark settings",
								spark_setting + " was set as expected", PASSED)
		if self.config[spark_setting] != desired_value:
			return TestResponse(self.name, spark_setting + " in spark settings",
								spark_setting + " was not set", FAILED)
		else:
			return TestResponse(self.name, spark_setting + " in spark settings",
								spark_setting + " was set as expected", PASSED)

	def set_credentials(self, uname, password):
		pass

	def get_secret(self, key):
		dbutils = self.runtime_params["dbutils"]
		return dbutils.secrets.get(scope="AzSK_CA_Secret_Scope",
								   key=key)

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


class CheckNumberOfAdminsHDI(BaseControlTest):
	# TODO
	name = ""

	def __init__(self, spark_context, **runtime_params):
		super().__init__(spark_context, **runtime_params)
		self.__dictconfig = None
		self.desc = "Number of admins should not be over 2"

	@fail_with_manual
	def test(self):
		adminCount = 0
		for item in self.__dictconfig["items"]:
			for priv in item["privileges"]:
				if priv["PrivilegeInfo"][
					"permission_name"] == "AMBARI.ADMINISTRATOR":
					adminCount += 1
				if adminCount > 2:
					return FAILED
		return PASSED


class DiskEncryptionEnabled(BaseControlTest):
	name = "Enable_Disk_Encryption"
	recommendation = "Set `spark.io.encryption.enabled` to `true` in the Spark configuration"
	desc = "Local disk storage encryption should be enabled"

	def __init__(self, spark_context, **runtime_params):
		super().__init__(spark_context, **runtime_params)
		self.name = "Enable_Disk_Encryption"

	@fail_with_manual
	def test(self):
		return self.fail_by_default_check("spark.io.encryption.enabled")


class AuthenticationEnabled(BaseControlTest):
	name = "Enable_Internal_Authentication"
	recommendation = "Set `spark.authenticate` to `true` in the Spark configuration (+)"
	desc = "Checks Spark internal connection authentication"

	def __init__(self, spark_context, **runtime_params):
		super().__init__(spark_context, **runtime_params)
		self.name = "Enable_Internal_Authentication"

	@fail_with_manual
	def test(self):
		return self.fail_by_default_check("spark.authenticate")


class RPCEnabled(BaseControlTest):
	name = "Enable_RPC"
	recommendation = "Set `spark.network.crypto.enabled` to `true` in the Spark configuration"
	desc = "Enable AES-based RPC encryption"

	def __init__(self, spark_context, **runtime_params):
		super().__init__(spark_context, **runtime_params)
		self.name = "Enable_RPC"

	def test(self):
		return self.fail_by_default_check("spark.network.crypto.enabled")


class EnableSASLEncryption(BaseControlTest):
	name = "Enable_SASL_Encryption"
	recommendation = "Set `spark.authenticate.enableSaslEncryption` to `true` in the Spark configuration (+)"
	desc = "Enable SASL-based encrypted communication."

	def __init__(self, spark_context, **runtime_params):
		super().__init__(spark_context, **runtime_params)

	@fail_with_manual
	def test(self):
		return self.fail_by_default_check(
				"spark.authenticate.enableSaslEncryption")


class SASLAlwaysEncrypt(BaseControlTest):
	name = "Enable_Always_Encrypt_In_SASL"
	recommendation = "Set `spark.network.sasl.serverAlwaysEncrypt` to `true` in the Spark configuration"
	desc = ("Disable unencrypted connections for ports using SASL"
			" authentication")

	def __init__(self, spark_context, **runtime_params):
		super().__init__(spark_context, **runtime_params)

	@fail_with_manual
	def test(self):
		return self.fail_by_default_check(
				"spark.network.sasl.serverAlwaysEncrypt")


class StorageEncryptionKeySize(BaseControlTest):
	name = "Use_Strong_Encryption_Keysize"
	recommendation = "Set `spark.io.encryption.keySizeBits` to `256` in the Spark configuration"
	desc = "256 bit encryption is recommended"

	def __init__(self, spark_context, **runtime_params):
		super().__init__(spark_context, **runtime_params)

	@fail_with_manual
	def test(self):
		return self.fail_by_default_check("spark.io.encryption.keySizeBits",
										  "256")


class WASBSProtocol(BaseControlTest):
	name = "Enable_WASBS"

	def __init__(self, spark_context, **runtime_params):
		super().__init__(spark_context, **runtime_params)
		self.desc = ("SSL supported for WASB")

	@property
	def config(self):
		return "tomato"

	def get_notebooks_from_cluster(self):
		return "tomato"

	@fail_with_manual
	def test(self):
		for notebook_content in self.get_notebooks_from_cluster():
			if "wasb://" in notebook_content:
				return FAILED
		return PASSED


class SSLEnabled(BaseControlTest):
	name = "Enable_SSL"
	recommendation = "Set `spark.ssl.enabled` to `true` in the Spark configuration"
	desc = "SSL should be enabled"

	def __init__(self, spark_context, **runtime_params):
		super().__init__(spark_context, **runtime_params)

	@fail_with_manual
	def test(self):
		return self.fail_by_default_check("spark.ssl.enabled")


class SSLKeyPassword(BaseControlTest):
	name = "Dont_Use_Plaintext_Key_Pwd"
	recommendation = "Do not set `spark.ssl.keyPassword` in the Spark configuration"
	desc = ("Password to private key in keystore shouldn't be"
			" stored in plaintext")

	def __init__(self, spark_context, **runtime_params):
		super().__init__(spark_context, **runtime_params)

	@fail_with_manual
	def test(self):
		if "spark.ssl.keyPassword" in self.config:
			return FAILED
		else:
			return PASSED


class SSLKeyStorePassword(BaseControlTest):
	name = "Dont_Use_Plaintext_KeyStore_Pwd"
	recommendation = "Do not set `spark.ssl.keyStorePassword` in the Spark configuration"
	desc = ("Password to key store should not be"
			" stored in plaintext")

	def __init__(self, spark_context, **runtime_params):
		super().__init__(spark_context, **runtime_params)

	@fail_with_manual
	def test(self):
		if "spark.ssl.keyStorePassword" in self.config:
			return FAILED
		else:
			return PASSED


class SSLTrustedStorePassword(BaseControlTest):
	name = "Dont_Use_Plaintext_TrustedStore_Pwd"
	recommendation = " Do not set `spark.ssl.trustStorePassword` in the Spark configuration"
	desc = ("Password to the trusted store should not be"
			" stored in plaintext")

	def __init__(self, spark_context, **runtime_params):
		super().__init__(spark_context, **runtime_params)

	@fail_with_manual
	def test(self):
		if "spark.ssl.trustStorePassword" in self.config:
			return FAILED
		else:
			return PASSED


class XSSProtectionEnabled(BaseControlTest):
	name = "Enable_HTTP_XSS_Protection_Header"
	recommendation = "Set `spark.ui.xXssProtection` to `1; mode=block` in the Spark configuration"
	desc = ("HTTP X-XSS-Protection response header"
			" should be set")

	def __init__(self, spark_context, **runtime_params):
		super().__init__(spark_context, **runtime_params)

	@fail_with_manual
	def test(self):
		return self.pass_by_default_check("spark.ui.xXssProtection",
										  "1; mode=block")


class CheckNumberOfAdminsDB(BaseControlTest):
	name = "Limit_Workspace_Admin_Count"
	recommendation = "Limit the number of admins to less than 5 in the Databricks Admin Settings"
	desc = ("Number of admins should be less than"
			" or equal to 5")

	def __init__(self, spark_context, **runtime_params):
		super().__init__(spark_context, **runtime_params)
		body = {"group_name": "admins"}
		self.data = self.invoke_rest_api("groups/list-members", body)

	@fail_with_manual
	def test(self):
		admins = self.data["members"]
		expected_response = "Number of admins less than 5"
		pass_response = "Number of admins are less than 5"
		fail_response = "Number of admins are over 5. List:\n"
		for i, admin in enumerate(admins):
			fail_response += "\n\t{}. {}".format(i + 1, admin["user_name"])
		if len(admins) <= 5:
			return TestResponse(self.name, expected_response, pass_response, PASSED)
		else:
			return TestResponse(self.name, expected_response, fail_response, FAILED)


class CheckGuestAdmin(BaseControlTest):
	name = "Prohibit_Guest_Account_Admin_Access"
	recommendation = "Disable administrator access to non microsoft email users"
	desc = "Disable admin access to guests"

	def __init__(self, spark_context, **runtime_params):
		super().__init__(spark_context, **runtime_params)
		body = {"group_name": "admins"}
		self.data = self.invoke_rest_api("groups/list-members", body)

	@fail_with_manual
	def test(self):
		admins = self.data['members']
		non_ms_accounts = []
		expected_response = "No non-MS accounts should have administrator privileges"
		for admin in admins:
			user_name = admin['user_name']
			domain = user_name.split("@")[1]
			if domain != "microsoft.com":
				non_ms_accounts.append(user_name)
		if non_ms_accounts:
			fail_response = "Following non-MS accounts have administrator privileges:"
			for i, non_ms_account in enumerate(non_ms_accounts):
				fail_response += "\n\t{}. {}".format(i + 1, non_ms_account)
			return TestResponse(self.name, expected_response, fail_response, FAILED)
		else:
			pass_response = "No non-MS accounts have administrator privileges"
			return TestResponse(self.name, expected_response, pass_response, PASSED)


class SameKeyvaultReference(BaseControlTest):
	name = "Use_Independent_Keyvault_Per_Scope"
	recommendation = "Independent Keyvaults should be used for secrets"
	desc = ("Same Keyvault should not be referenced by multiple"
			" secret scopes")

	def __init__(self, spark_context, **runtime_params):
		super().__init__(spark_context, **runtime_params)
		self.data = self.invoke_rest_api("secrets/scopes/list")

	@fail_with_manual
	def test(self):
		expected_response = self.desc
		pass_response = "Same Keyvault not referenced by multiple scopes"
		fail_response = "Found Keyvault with multiple references:"
		secretScopeLists = self.data['scopes']
		# todo: optimize this. There's no need of pandas to filter things
		keyVaultBackedSecretScope = list(
				filter(lambda x: x['backend_type'] == 'AZURE_KEYVAULT',
					   secretScopeLists))
		if len(keyVaultBackedSecretScope) == 0:
			return TestResponse(self.name, expected_response, pass_response, PASSED)
		SummarizedList = pd.DataFrame([{'KeyVault_ResourceId':
													 item['keyvault_metadata']['resource_id'],
										'ScopeName': item['name']} for item in
									   keyVaultBackedSecretScope]).groupby(
				'KeyVault_ResourceId').agg(np.size)
		KeyVaultWithManyReference = SummarizedList[SummarizedList['ScopeName'] > 1]
		if KeyVaultWithManyReference.empty:
			return TestResponse(self.name, expected_response, pass_response, PASSED)
		else:
			for idx, (row, _) in enumerate(KeyVaultWithManyReference.iterrows()):
				fail_response += "\n\t{}. {}".format(idx + 1, row.split("/")[-1])
			return TestResponse(self.name, expected_response, fail_response, FAILED)


class AccessTokenExpiry(BaseControlTest):
	name = "Keep_Minimal_Token_Validity"
	recommendation = "Personal Access Token (PAT) should have minimum validity"
	desc = "Use minimum validity token for PAT"

	def __init__(self, spark_context, **runtime_params):
		super().__init__(spark_context, **runtime_params)
		self.data = self.invoke_rest_api("token/list")

	def test(self):
		expected_response = "PAT token should be have minimum validity (<90 days)"
		pass_response = "PAT tokens have minimum validity"
		token_lists = self.data['token_infos']
		failed = False
		infinite_pat = list(
				filter(lambda x: x['expiry_time'] == -1, token_lists))
		finite_pat = list(
				filter(lambda x: x['expiry_time'] != -1, token_lists))
		long_pat = list(filter(lambda x:
										   (datetime.utcfromtimestamp(x['expiry_time'] / 1000)
											- datetime.utcfromtimestamp(x['creation_time'] / 1000)).days > 90,
										   finite_pat))
		if infinite_pat:
			fail_response = "PAT token with indefinite validity:"
			failed = True
			for i, x in enumerate(infinite_pat):
				fail_response += "\n\t{}. {}".format(i + 1, x["comment"])
		if long_pat:
			fail_response = "PAT token with > 90 day validity"
			failed = True
			for i, x in enumerate(long_pat):
				fail_response += "\n\t{}. {}".format(i + 1, x["comment"])
		if failed:
			return TestResponse(self.name, expected_response, fail_response, FAILED)
		else:
			return TestResponse(self.name, expected_response, pass_response, PASSED)


class NonKeyvaultBackend(BaseControlTest):
	name = "Use_KeyVault_Backed_Secret_Scope"
	recommendation = "Use only Keyvault backed secrets"
	desc = "Use Azure Keyvault backed secret scope to hold secrets"

	def __init__(self, spark_context, **runtime_params):
		super().__init__(spark_context, **runtime_params)
		self.data = self.invoke_rest_api("secrets/scopes/list")

	@fail_with_manual
	def test(self):
		secretScopeLists = self.data['scopes']
		expected_response = "All secrets should be backed by Azure KeyVault"
		pass_response = "All secrets are backed by Azure KeyVault"
		fail_response = "Found following scopes in non-Azure KeyVault backend\n"
		DataBricksBackedSecretScope = list(
				filter(lambda x: x['backend_type'] != 'AZURE_KEYVAULT',
					   secretScopeLists))
		if DataBricksBackedSecretScope:
			for i, x in enumerate(DataBricksBackedSecretScope):
				fail_response += "\n\t{}. {}".format(i + 1, x["name"])
			return TestResponse(self.name, expected_response, fail_response, FAILED)
		else:
			return TestResponse(self.name, expected_response, pass_response, PASSED)


class ExternalLibsInstalled(BaseControlTest):
	name = "External_Libs_Installed"
	recommendation = "Avoid using external libraries from the internet"
	desc = recommendation

	def __init__(self, spark_context, **runtime_params):
		super().__init__(spark_context, **runtime_params)
		self.data = self.invoke_rest_api("libraries/all-cluster-statuses")

	def test(self):
		expected_response = "External libraries should be absent or verified"
		pass_response = "No external libraries are installed"
		fail_response = "Following external libraries on cluster:\n"
		data = self.data
		fails = False
		if "statuses" in data and len(data["statuses"]) > 0:
			try:
				for i, x in enumerate(data["statuses"][0]["library_statuses"]):
					# todo: this currently only considers packages installed from PyPi should be extended
					fail_response += "\n\t{}. {}".format(i + 1, x["library"]["pypi"]["package"])
				fails = True
			except:
				pass

		if fails:
			return TestResponse(self.name, expected_response, fail_response, "Verify")
		else:
			return TestResponse(self.name, expected_response, pass_response, PASSED)


class InitScriptPresent(BaseControlTest):
	name = "Init_Scripts_Present"
	recommendation = "Where present, init scripts should be verified"
	desc = recommendation

	def __init__(self, spark_context, **runtime_params):
		super().__init__(spark_context, **runtime_params)
		self.data = self.invoke_rest_api("clusters/list")

	def test(self):
		expected_response = "Init scripts should be absent or verified"
		pass_response = "Init scripts absent"
		fail_response = "Init scripts at the following location:\n"
		for x in self.data["clusters"]:
			if x["cluster_source"] != "JOB":
				if "init_scripts" in x:
					for i, filepath in enumerate(x["init_scripts"]):
						fail_response += "\n\t{}. {}".format(i + 1, filepath["dbfs"]["destination"])
					return TestResponse(self.name, expected_response, fail_response, MANUAL)
		return TestResponse(self.name, expected_response, pass_response, PASSED)


class MountPointPresent(BaseControlTest):
	name = "Mount_Points_Present"
	recommendation = "Where present, mount points should be verified"
	desc = recommendation

	def __init__(self, spark_context, **runtime_params):
		super().__init__(spark_context, **runtime_params)
		dbutils = self.runtime_params["dbutils"]
		self.data = dbutils.fs.mounts()

	def test(self):
		expected_response = "Mount points should be absent or verified"
		pass_response = "Mount points absent"
		fail_response = "Unsafe mount points:\n"
		safe_mounts = {"DatabricksRoot", "databricks-datasets", "databricks-results"}
		ctr = 1
		verify = False
		for mount_point in self.data:
			if mount_point.source not in safe_mounts:
				fail_response += "\n\t{}. Location: {} Source: {}".format(ctr, mount_point.mountPoint, mount_point.source)
				verify = True
				ctr += 1
		if verify:
			return TestResponse(self.name, expected_response, fail_response, MANUAL)
		else:
			return TestResponse(self.name, expected_response, pass_response, PASSED)


class TokenNearExpiry(BaseControlTest):
	name = "Token_Near_Expiry"
	recommendation = "Expiry for PAT tokens should be greater than 30 days"
	desc = recommendation

	def __init__(self, spark_context, **runtime_params):
		super().__init__(spark_context, **runtime_params)
		self.data = self.invoke_rest_api("token/list")

	def test(self):
		expected_response = "PAT tokens expiry should be >30 days"
		pass_response = "PAT tokens are far from expiry"
		fail_response = "Following PAT tokens near expiry (<30 days):\n"
		assert "token_infos" in self.data
		now = datetime.now()
		ctr = 1
		fail = False
		for tokens in self.data["token_infos"]:
			expiry = datetime.fromtimestamp(tokens["expiry_time"] // 1000)
			howfar = (expiry - now)
			if howfar.days <= 30:
				fail_response += "\n\t{}. {}".format(ctr, tokens["comment"])
				fail = True
		if fail:
			return TestResponse(self.name, expected_response, fail_response, FAILED)
		else:
			return TestResponse(self.name, expected_response, pass_response, PASSED)