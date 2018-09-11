# -------------------------------------------------------------------------
# Copyright (c) Microsoft Corporation. All rights reserved.
# Licensed under the MIT License. See License.txt in the project root for
# license information.
# -------------------------------------------------------------------------
import pyodbc
import pandas as pd

from azure.keyvault import KeyVaultClient
from azure.storage.file import FileService
from msrestazure.azure_active_directory import MSIAuthentication
from recommendation_engine import save_recommendation_json


def validate(caller):
	"""Decorator to validate the calling function"""

	def executor(*args, **kwargs):
		result = None
		try:
			result = caller(*args, **kwargs)
		except Exception as e:
			print("Error at {} Exception: {}".format(caller.__name__, e))
		return result

	return executor


@validate
def get_from_keyvault(key_name):
	"""Gets a certain secret from Keyvault"""
	credentials = MSIAuthentication(resource='https://vault.azure.net')
	key_vault_client = KeyVaultClient(credentials)

	key_vault_uri = "https://sqltostoragekeyvault.vault.azure.net/"

	secret = key_vault_client.get_secret(
		key_vault_uri,
		key_name,
		""
	)
	print("Secret received is: {}".format(secret))
	return secret.value


@validate
def get_csv_from_mysql():
	cnxn = pyodbc.connect(get_from_keyvault("sql-server-credentials"))
	# todo: remove TOP(1000)
	query = "SELECT TOP(1000) * FROM DBO.LASTKNOWNSERVICESCANRESULTJOINED"
	df = pd.read_sql_query(query, cnxn)
	df.set_index("Id", inplace=True)
	df.to_csv("data.csv")
	print("Saved data.csv to disk")


@validate
def save_file_to_storage(file):
	fs = FileService(account_name="recoenginestorage",
					 account_key=get_from_keyvault("storage-account-key"))
	res = fs.create_file_from_path("myshare", None, "data.csv",
								   file)
	print(res)


@validate
def upload_recommendations():
	save_recommendation_json()
	save_file_to_storage("recommendation.json")


if __name__ == '__main__':
	get_csv_from_mysql()
	upload_recommendations()
