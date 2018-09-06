# -------------------------------------------------------------------------
# Copyright (c) Microsoft Corporation. All rights reserved.
# Licensed under the MIT License. See LICENSE in the project root for
# license information.
# -------------------------------------------------------------------------
from collections import defaultdict

import pandas as pd

from .constants import *


def get_feature_hash(features):
	hash_val = 1
	for feature in features:
		hash_val *= feature_hash[feature]
		hash_val %= BIG_PRIME
	return hash_val


def get_category_hash(categories):
	hash_val = 1
	for category in categories:
		hash_val *= category_hash[category]
		hash_val %= BIG_PRIME
	return hash_val


def get_parents_list(features):
	parents = []
	for feature in features:
		parents.append(get_categories[feature][0])
	return parents


def create_master_hash_table():
	df = pd.read_csv("big_data.csv")
	req = ["ResourceGroupId", "Feature", "CategoryName", "VerificationResult",
		   "ControlStringId"]
	df = df[req]
	# Create combination dict
	feature_combinations = defaultdict(set)
	for idx, row in df.iterrows():
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
	# generate master hash table
	master_hash_table = dict()
	for res_id in feature_combinations:
		features = feature_combinations[res_id]
		feature_hash = get_feature_hash(features)
		int_list = master_hash_table.setdefault(feature_hash,
												{"features": features,
												 "counts": 0,
												 "info": failures[res_id]})
		int_list["counts"] += 1
	return master_hash_table


updated = False


def recurse(my_list, hash_cache, info, string_cache, feature_info,
			master_category_table, parent_feature_combo_table):
	global updated
	if my_list:
		for parent in get_categories[my_list[0]]:
			recurse(my_list[1:],
					(hash_cache * category_hash[parent]) % BIG_PRIME, info,
					parent + " -> " + string_cache,
					feature_info, master_category_table,
					parent_feature_combo_table)
	else:
		to_insert = dict()
		if hash_cache in master_category_table and not updated:
			# ADD VALUES
			previous_info = master_category_table[hash_cache]
			to_insert["Totals"] = previous_info["Totals"] + info["Totals"]
			to_insert["Fails"] = previous_info["Fails"] + info["Fails"]
			to_insert["Success"] = previous_info["Success"] + info["Success"]
		else:
			# FIRST TIME
			to_insert["Totals"] = info["Totals"]
			to_insert["Fails"] = info["Fails"]
			to_insert["Success"] = info["Success"]
		master_category_table[hash_cache] = to_insert
		updated = True
		parents = string_cache.split(" -> ")[:-1]
		parents_hash = get_category_hash(parents)
		parent_feature_combo_table[parents_hash].append(feature_info)
		print("Category combination: {}".format(string_cache))
		print("*" * 50)
	print("#" * 70)


def create_master_category_and_combo():
	global updated
	master_hash_table = create_master_hash_table()
	master_category_table = dict()
	parent_feature_combo_table = defaultdict(list)
	for x in master_hash_table:
		updated = False
		feature_info = {
			"features": list(master_hash_table[x]["features"]),
			"info": master_hash_table[x]["info"]
		}
		recurse(list(master_hash_table[x]["features"]), 1,
				master_hash_table[x]["info"], "", feature_info,
				master_category_table, parent_feature_combo_table)
	return master_hash_table, parent_feature_combo_table, master_category_table


master_hash_table, parent_feature_combo_table, master_category_table = \
	create_master_category_and_combo()


def get_feature_safety(features):
	print("Features: {}".format(features))
	feature_info = master_hash_table[get_feature_hash(features)]
	print("Possible Parents: {}".format(get_parents_list(features)))
	category_info = master_category_table[
		get_category_hash(get_parents_list(features))]
	print("Feature info: {}".format(feature_info["info"]))
	print("Category info: {}".format(category_info))
	final_score = feature_info["info"]["Fails"] / feature_info["info"]["Totals"] * 100
	print("Fail percentage: {0:.2f}%".format(final_score))
	return final_score


def score(value):
	num = value["info"]["Fails"]
	den = value["info"]["Totals"]
	return num / den


def get_safest_feature(categories):
	parent_hash = get_category_hash(categories)
	value = parent_feature_combo_table[parent_hash]
	print("Combos: {}".format(value))
	string = "["
	for x in sorted(value, key=lambda x: score(x)):
		string += str(x["features"]) + ","
	string = string[:-1]
	string += "]"
	return string


def construct_output(output_string):
	return output_string.replace("#[", "{").replace("#]", "}").replace("\'", "\"")


def get_safest_features_from_features(features):
	parents_list = get_parents_list(features)
	safe_features = get_safest_feature(parents_list)
	# output_json = "[ RecommendedFeatureGroups: {} ]".format(safe_features)
	print("SAFE FEATURES: {}".format(safe_features))
	feature_info = master_hash_table[get_feature_hash(features)]
	print("FI: {}".format(feature_info))
	output_json = \
		"""
#[
		"RecommendedFeatureGroups": {0},
		"CurrentFeatureGroup": {1},
		"Ranking": {2},
		"TotalSuccessCount":  {3},
		"TotalFailCount":  {4},
		"SecurityRating":  {5},
		"TotalOccurrences":  {6},
		"CurrentCategoryGroup": {7}
#]""".format(safe_features, features, -1, feature_info["info"]["Success"], feature_info["info"]["Fails"],
			 score(feature_info), feature_info["counts"], parents_list)
	return construct_output(output_json)


if __name__ == '__main__':
	pass