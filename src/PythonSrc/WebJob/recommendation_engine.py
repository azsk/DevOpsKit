# -------------------------------------------------------------------------
# Copyright (c) Microsoft Corporation. All rights reserved.
# Licensed under the MIT License. See LICENSE in the project root for
# license information.
# -------------------------------------------------------------------------
import json
import pandas as pd

from collections import defaultdict
from constants import *


def get_hash(resource_list: list or set, resource_hash: dict) -> int:
	"""Calculates hash by multiplying hashes of individual resources.
	Multiplying prime numbers ensures [A, B, C] and [B, A, C] are the same
	thing.
	:param resource_list: list, features or categories
	:param resource_hash: dict, mapping resource to its hash. See
		feature_hash and category_hash in .constants
	:return: int, calculated hash
	"""
	hash_val = 1
	for feature in resource_list:
		hash_val *= resource_hash[feature]
		hash_val %= BIG_PRIME
	return hash_val


def single_parents(features):
	"""
	Returns a list of one of the parents of a feature combinations.
	Required later for finding category score.
	:param features: list of features
	:return: one of the possible parents
	"""
	parents = []
	for feature in features:
		parents.append(get_categories[feature][0])
	return parents


def create_feature_groups():
	"""
	Creates feature groups by reading from CSV by grouping them with
	resource ID. Everything inside a resource ID is considered as a single
	combination of features.
	:return: dict, feature groups
	"""
	df = pd.read_csv(DATA_FILE_PATH)
	req = ["ResourceGroupId", "Feature", "VerificationResult",
		   "ControlStringId"]
	df = df[req]
	# Create combination dict
	feature_combinations = defaultdict(set)
	for idx, row in df.iterrows():
		if row["Feature"] not in IGNORE_LIST:
			feature_combinations[row["ResourceGroupId"]].add(row["Feature"])
	# count failures
	failures = defaultdict(dict)
	for idx, row in df.iterrows():
		totals = failures[row["ResourceGroupId"]].setdefault("Totals", 0)
		fails = failures[row["ResourceGroupId"]].setdefault("Fails", 0)
		success = failures[row["ResourceGroupId"]].setdefault("Success", 0)
		failures[row["ResourceGroupId"]]["Totals"] = totals + 1
		if row["VerificationResult"] == "Passed":
			failures[row["ResourceGroupId"]]["Success"] = success + 1
		else:
			failures[row["ResourceGroupId"]]["Fails"] = fails + 1
	# generate feature groups
	feature_groups = dict()
	# Counts this specific feature combination has occured
	# how many times in the dataset
	for res_id in feature_combinations:
		features = feature_combinations[res_id]
		hash_value = get_hash(features, feature_hash)
		int_list = feature_groups.setdefault(hash_value,
												{"features": features,
												 "counts": 0,
												 "info": failures[res_id]})
		int_list["counts"] += 1
	return feature_groups


def recurse(features_list, running_hash, rates, running_parents_cache,
			feature_info, category_rates, parent_feature_combo_table,
			updated_hashes):
	"""
	Recursively calculate the success/failure rates of categories and store it
	in category_rates dict. The recommendation will be made for the features
	with lowest overall failure rate. This is will also additionally create a
	map of category -> features. Using this we will know the possible
	combination of features under one category. Later we will sort the features
	by score to get the safest one.
	:param features_list: present feature list, will reduce every iteration
		while recursing.
	:param running_hash: cache of the running hash. We will use the logic from
		get_hash to step every time.
	:param rates: failure, success, total counts of feature.
	:param running_parents_cache: contains the list of parents. Will keep on
		increasing every iteration (as we travel the recursion tree)
	:param feature_info: contains dictionary of feature information with two
		keys: list of features, and their rates
	:param category_rates: failure, success, total counts of category
	:param parent_feature_combo_table: category -> list of features mapping.
	:param updated_hashes: set of hashes for which the table is already updated.
		This will prevent the table from updating more than once for the same
		hash.
	"""
	if features_list:
		for parent in get_categories[features_list[0]]:
			recurse(features_list[1:],
					(running_hash * category_hash[parent]) % BIG_PRIME, rates,
					parent + " -> " + running_parents_cache, feature_info,
					category_rates, parent_feature_combo_table,
					updated_hashes)
	else:
		if running_hash not in updated_hashes:
			updated_hashes.add(running_hash)
			to_insert = dict()
			if running_hash in category_rates:
				# ADD VALUES
				previous_info = category_rates[running_hash]
				to_insert["Totals"] = previous_info["Totals"] + rates["Totals"]
				to_insert["Fails"] = previous_info["Fails"] + rates["Fails"]
				to_insert["Success"] = previous_info["Success"] \
									   + rates["Success"]
			else:
				# FIRST TIME
				to_insert["Totals"] = rates["Totals"]
				to_insert["Fails"] = rates["Fails"]
				to_insert["Success"] = rates["Success"]
			category_rates[running_hash] = to_insert
			parents = running_parents_cache.split(" -> ")[:-1]
			parents_hash = get_hash(parents, category_hash)
			parent_feature_combo_table[parents_hash].append(feature_info)
			print("Category combination: {}".format(running_parents_cache))
			print("*" * 50)
		else:
			print("Duplicate hash: {}".format(running_parents_cache))
	print("#" * 70)


def create_master_category_and_combo():
	"""Helper function to execute recursion and returning the result
	:return: feature_groups: groups of features,
			 parent_feature_table: mapping of parents and the occurrences of
			 	features under them.
			 category_rates: failure, success, total rates of category
	"""
	feature_groups = create_feature_groups()
	print("Feature groups created")
	category_rates = dict()
	parent_feature_table = defaultdict(list)
	for x in feature_groups:
		feature_info = {
			"features": list(feature_groups[x]["features"]),
			"info": feature_groups[x]["info"]
		}
		recurse(list(feature_groups[x]["features"]), 1,
				feature_groups[x]["info"], "", feature_info,
				category_rates, parent_feature_table, set())
	return feature_groups, parent_feature_table, category_rates


def get_feature_safety(features: list or set, category_groups: dict,
					   category_rates: dict) -> float:
	"""Calculates feature safety depending on the failure rate of controls
	:param features: list of features
	:param category_groups: category groups
	:param category_rates: dict containing failure rates of categories
	:return: float, score of the input feature list
	"""
	print("Features: {}".format(features))
	feature_info = category_groups[get_hash(features, feature_hash)]
	print("Possible Parents: {}".format(single_parents(features)))
	category_info = category_rates[
		get_hash(single_parents(features), category_hash)]
	print("Feature info: {}".format(feature_info["info"]))
	print("Category info: {}".format(category_info))
	fails = feature_info["info"]["Fails"]
	totals = feature_info["info"]["Totals"]
	final_score = (fails / totals) * 100
	print("Fail percentage: {0:.2f}%".format(final_score))
	return final_score


def score(value) -> float:
	num = value["info"]["Fails"]
	den = value["info"]["Totals"]
	return num / den


def get_safest_features(categories, parent_feature_table):
	"""Returns the safest feature in form of string for the given category
	combination. 
	:param categories: list of categories under which the recommendation is 
		wanted.
	:param parent_feature_table:mapping of parents and the occurrences of
		features under them.
	:return: string of recommendations
	"""
	parent_hash = get_hash(categories, category_hash)
	value = parent_feature_table[parent_hash]
	print("Combos: {}".format(value))
	string = "["
	for x in sorted(value, key=lambda x: score(x)):
		string += str(x["features"]) + ","
	string = string[:-1]
	string += "]"
	return string


def save_recommendation_json():
	"""Save the recommendation JSON i.e. parent_feature_table offline.
	:return:
	"""
	category_groups, parent_feature_combo_table, master_category_table = \
		create_master_category_and_combo()
	json_str = json.dumps(parent_feature_combo_table)
	with open("recommendation.json", "w") as f:
		f.write(json_str)
	print("Completed writing JSON")


if __name__ == '__main__':
	save_recommendation_json()
