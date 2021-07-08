# ------------------------------------------------------------------------------
# Copyright (c) Microsoft Corporation. All rights reserved.
# Licensed under the MIT License. See License in the project root for
# license information.
# ------------------------------------------------------------------------------
from functools import wraps
from .constants import *


def fail_with_manual(func, *args, **kwargs):
	@wraps(func)
	def wrapper(*args, **kwargs):
		try:
			result = func(*args, **kwargs)
			return result
		except Exception as e:
			print("Exception in executing {} with"
				  " args: {} kwargs: {}".format(func.__name__,
												args, kwargs))
			print(e)
			return TestResponse("Manual")

	return wrapper


class TestResponse:
	def __init__(self, control_name=None, expected=None, actual=None, result="Unverified"):
		self.control_name = control_name
		self.expected = expected
		self.actual = actual
		self.result = result

	def __str__(self):
		if self.result == PASSED:
			return """[{}]: {}\nExpected {}\nFound configuration as expected.""".format(self.result,
																 self.control_name,
																 self.actual)
		elif self.result == FAILED or self.result == MANUAL:
			return """[{}]: {}\nExpected {}\nFound: {}""".format(self.result,
															  self.control_name,
															  self.expected,
															  self.actual)
