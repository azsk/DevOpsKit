# -------------------------------------------------------------------------
# Copyright (c) Microsoft Corporation. All rights reserved.
# Licensed under the MIT License. See License.txt in the project root for
# license information.
# -------------------------------------------------------------------------
# list of features, every feature is assigned a
# prime number to calculate hash
# see <> for hash logic
feature_hash = {
	"SQLDatabase": 3940427,
	"AppService": 3940763,
	"StreamAnalytics": 1414297,
	"KeyVault": 3125831,
	"Storage": 5392313,
	"Automation": 6305339,
	"EventHub": 7368719,
	"LogicApps": 7368629,
	"TrafficManager": 7368787,
	"VirtualNetwork": 2523893,
	"DataLakeStore": 4284113,
	"CosmosDB": 5602973,
	"RedisCache": 5603713,
	"DataFactory": 192097,
	"DataLakeAnalytics": 192103,
	"NotificationHub": 192113,
	"ServiceFabric": 192121,
	"Search": 192133,
	"VirtualMachine": 192149,
	"AnalysisServices": 192161,
	"Batch": 192173,
	"ODG": 192187,
	"ERvNet": 192191,
	"CloudService": 192193,
	"LoadBalancer": 192229,
	"APIConnection": 192233,
	"BotService": 192239,
	"ContainerInstances": 192251,
	"DataFactoryV2": 192259,
}

category_hash = {
	"Storage": 1000003,
	"DataProcessing": 1000033,
	"Reporting": 1000037,
	"Web Front End": 1000039,
	"APIs": 1000081,
	"Security Infra": 1000099,
	"SubscriptionCore": 1000117,
	"Commuincation Hub": 1000121,
	"Hybrid": 1000133,
	"Network Isolation": 1000151,
	"Cache": 1000159,
	"Backend Processing": 123123593,
}

get_categories = {
	"AppService": ["Web Front End", "APIs"],
	"SQLDatabase": ["Storage", "DataProcessing", "Reporting"],
	"Storage": ["Storage", "Reporting", "DataProcessing"],
	"LogicApps": ["DataProcessing"],
	"DataFactory": ["DataProcessing"],
	"DataLakeAnalytics": ["DataProcessing", "Reporting"],
	"DataLakeStore": ["Storage", "Reporting", "DataProcessing"],
	"NotificationHub": ["Commuincation Hub"],
	"ServiceFabric": ["Web Front End", "APIs", "Backend Processing"],
	"Search": ["APIs", "Backend Processing"],
	"VirtualMachine": ["Web Front End", "APIs", "Backend Processing",
					   "DataProcessing"],
	"VirtualNetwork": ["Network Isolation", "Hybrid"],
	"AnalysisServices": ["DataProcessing", "Reporting"],
	"Batch": ["Backend Processing"],
	"RedisCache": ["Cache"],
	"EventHub": ["Commuincation Hub", "Hybrid"],
	"ODG": ["Hybrid"],
	"TrafficManager": ["Network Isolation"],
	"ERvNet": ["Hybrid", "Network Isolation"],
	"Automation": ["Backend Processing"],
	"CosmosDB": ["Storage", "DataProcessing", "Reporting"],
	"StreamAnalytics": ["DataProcessing", "Reporting"],
	"CloudService": ["Web Front End", "APIs", "Backend Processing"],
	"LoadBalancer": ["Network Isolation"],
	"APIConnection": ["DataProcessing"],
	"BotService": ["APIs", "Commuincation Hub", "Web Front End"],
	"ContainerInstances": ["Web Front End", "APIs", "DataProcessing",
						   "Backend Processing"],
	"DataFactoryV2": ["DataProcessing", "Backend Processing"],
	"KeyVault": ["Security Infra"]
}

BIG_PRIME = 824633720831
