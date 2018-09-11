# -------------------------------------------------------------------------
# Copyright (c) Microsoft Corporation. All rights reserved.
# Licensed under the MIT License. See LICENSE in the project root for
# license information.
# -------------------------------------------------------------------------
import ast
import json

from recommendation_engine import (single_parents, get_safest_features, get_hash,
								   score, get_feature_safety)
from constants import *
from flask import Flask, request

app = Flask(__name__)


def construct_output(output_string):
	return output_string.replace("#[", "{")\
						.replace("#]", "}")\
						.replace("\'", "\"")


def recommend_features(features, category_groups,
					   parent_feature_combo_table):
	parents_list = single_parents(features)
	safe_features = get_safest_features(parents_list, parent_feature_combo_table)
	# output_json = "[ RecommendedFeatureGroups: {} ]".format(safe_features)
	print("SAFE FEATURES: {}".format(safe_features))
	feature_info = category_groups[get_hash(features, feature_hash)]
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
#]""".format(safe_features, features, -1, feature_info["info"]["Success"],
			 feature_info["info"]["Fails"],
			 score(feature_info), feature_info["counts"], parents_list)
	return construct_output(output_json)


@app.route("/recommend", methods=["POST"])
def get_safest_feature_endpoint():
	data = json.loads(request.json)
	categories = data["Categories"]
	features = data["Features"]
	print("Categories: {}".format(categories))
	print("Features: {}".format(features))
	best_feature = recommend_features(features)
	print("BF: {}".format(best_feature))
	return best_feature


@app.route('/score', methods=["POST"])
def hello_world():
	data = request.values
	categories = ast.literal_eval(data["Categories"])
	features = ast.literal_eval(data["Features"])
	score = get_feature_safety(features)
	return str(score)


@app.route("/")
def works():
	return "Website Works!"
