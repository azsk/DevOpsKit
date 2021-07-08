import requests
import datetime
import hashlib
import hmac
import base64
import json
from .constants import LOG_ANALYTICS_API_VERSION


class LogAnalyticsClient:
	def __init__(self, workspace_id, shared_key):
		self.workspace_id = workspace_id
		self.shared_key = shared_key

	def __get_header(self, date, content_length):
		sigs = "POST\n{}\napplication/json\nx-ms-date:{}\n/api/logs".format(
				str(content_length), date)
		utf8_sigs = sigs.encode('utf-8')
		decoded_shared_key = base64.b64decode(self.shared_key)
		hmac_sha256_sigs = hmac.new(
				decoded_shared_key, utf8_sigs, digestmod=hashlib.sha256).digest()
		b64bash = base64.b64encode(hmac_sha256_sigs).decode('utf-8')
		authorization = "SharedKey {}:{}".format(self.workspace_id, b64bash)
		return authorization

	def __rfcdate(self):
		return datetime.datetime.utcnow().strftime('%a, %d %b %Y %H:%M:%S GMT')

	def __post_data(self, log_type, json_records):
		if not log_type.isalpha():
			raise Exception(
					"ERROR: log_type supports only alpha characters: {}".format(log_type))

		body = json.dumps(json_records)
		rfcdate = self.__rfcdate()
		content_length = len(body)
		signature = self.__get_header(rfcdate, content_length)
		uri = "https://{}.ods.opinsights.azure.com/api/logs?api-version={}".format(
				self.workspace_id, LOG_ANALYTICS_API_VERSION)
		headers = {
			'content-type':         'application/json',
			'Authorization':        signature,
			'Log-Type':             log_type,
			'x-ms-date':            rfcdate
		}
		return requests.post(uri, data=body, headers=headers)

	def post_data(self, json_log, log_name):
		response = self.__post_data(log_name, json_log)
		if response.status_code == 200:
			print('Telemetry sent to Log Analytics')
		else:
			print("Failure in posting to Log Analytics: Error code:{}".format(response.status_code))
