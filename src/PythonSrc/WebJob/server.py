# -------------------------------------------------------------------------
# Copyright (c) Microsoft Corporation. All rights reserved.
# Licensed under the MIT License. See LICENSE in the project root for
# license information.
# -------------------------------------------------------------------------
import ast
import json

from flask import Flask, request

app = Flask(__name__)


@app.route("/recommend", methods=["POST"])
def get_safest_feature_endpoint():
	data = json.loads(request.json)
	categories = data["Categories"]
	features = data["Features"]
	print("Categories: {}".format(categories))
	print("Features: {}".format(features))
	best_feature = get_safest_features_from_features(features)
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
