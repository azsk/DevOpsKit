using System;
using System.Collections;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text.RegularExpressions;
using AzSK.ARMChecker.Lib.Extensions;
using Newtonsoft.Json.Linq;

namespace AzSK.ARMChecker.Lib
{

    public class ArmTemplateEvaluator
    {
        private readonly IList<ResourceControlSet> _resourceControlSets;

        public ArmTemplateEvaluator(IEnumerable<string> resourceControlSetJsonStrings)
        {

            if (resourceControlSetJsonStrings == null)
                throw new ArgumentNullException(nameof(resourceControlSetJsonStrings));

            var controlSetJsonStrings = resourceControlSetJsonStrings as List<string> ?? resourceControlSetJsonStrings.ToList();

            if (controlSetJsonStrings.All(x => x.IsNullOrWhiteSpace()))
                throw new ArgumentException(nameof(resourceControlSetJsonStrings));


            _resourceControlSets = controlSetJsonStrings
                .Where(x => x.IsNotNullOrWhiteSpace())
                .Select(x => x.FromJsonTo<ResourceControlSet>())
                .ToList();
            SetResourceTypes();
        }

        public ArmTemplateEvaluator(string resourceControlSetWrapJsonString)
        {

            if (resourceControlSetWrapJsonString == null)
                throw new ArgumentNullException(nameof(resourceControlSetWrapJsonString));

            var controlSetWrap = resourceControlSetWrapJsonString.FromJsonTo<ResourceControlSetWrap>();
            _resourceControlSets = controlSetWrap.ResourceControlSets;

            SetResourceTypes();
        }

        public IList<ControlResult> Evaluate(string armTemplateJsonString,
            string armTemplateExternalParametersJsonString = null,
            string templateFunctionConfigJsonString = null)
        {
            var armTemplate = ParseArmTemplateJsonString(armTemplateJsonString);
            var armTemplateExternalParameters =
                ParseArmTemplateExternalParametersJsonString(armTemplateExternalParametersJsonString);
            var templateFunctionConfig = templateFunctionConfigJsonString.IsNullOrWhiteSpace()
                ? TemplateFunctionConfig.Defaults
                : templateFunctionConfigJsonString.FromJsonTo<TemplateFunctionConfig>();
            return Evaluate(armTemplate, armTemplateExternalParameters, templateFunctionConfig);
        }

        public IList<ControlResult> Evaluate(JObject armTemplate, JObject armTemplateExternalParameters,
            TemplateFunctionConfig templateFunctionConfig)
        {
            var resourceEvaluator = new ResourceEvaluator(armTemplate, armTemplateExternalParameters);
            var results = new List<ControlResult>();
            // Get list of all primary resources
            var listOfAllPrimaryResource = _resourceControlSets.Select(x => new { SupportedResourceTypes = x.supportedResourceTypes, FeatureName = x.FeatureName }).ToList();//.ToDictionary(x=>x.ResourceType,x=>x.FeatureName);
            // Fetch all resources , variables , parameters
            var resources = armTemplate.GetValueCaseInsensitive("resources");
            var parameters = armTemplate.GetValueCaseInsensitive("parameters");
            var variables = armTemplate.GetValueCaseInsensitive("variables");
            // Create a hashtable for all parameters and variables 
            Hashtable ParamAndVarKeys = new Hashtable();
            if (parameters != null)
            {
                foreach (var parameter in parameters)
                {
                    var paramKey = parameter.Path.ToString().ToLower();
                    var paramValue = parameter.First().ToString().ToLower();
                    ParamAndVarKeys.Add(paramKey, paramValue);
                }
            }
            if (variables != null)
            {
                foreach (var variable in variables)
                {
                    var variableKey = variable.Path.ToString().ToLower();
                    var variableValue = variable.First().ToString().ToLower();
                    ParamAndVarKeys.Add(variableKey, variableValue);
                }
            }
            List<ResourceNode> ResourceList = new List<ResourceNode>();
            int index = 0;
            // Create initial list of all resource without linking
            foreach (JObject resource in resources)
            {
                var type = resource.GetValueCaseInsensitive<string>("type");
                var name = resource.GetValueCaseInsensitive<string>("name");
                var featureSet = listOfAllPrimaryResource?.FirstOrDefault(x => x.SupportedResourceTypes.Any(y => y.Equals(type, StringComparison.OrdinalIgnoreCase)));
                if (featureSet != null)
                {
                    ResourceNode resourceNode = new ResourceNode();
                    resourceNode.Token = "Token" + index++;
                    ResourceModel resourceModel = new ResourceModel();
                    resourceModel.FeatureName = featureSet.FeatureName;
                    resourceModel.ResourceType = type;
                    resourceModel.ResourceName = name;
                    resourceModel.Resource = resource;
                    resourceNode.Resource = resourceModel;
                    ResourceList.Add(resourceNode);
                }
            }
            var groupedResources = ResourceList?.GroupBy(x => x.Resource.FeatureName);


            foreach (var featureGroup in groupedResources)
            {
                // Use for intial relation tuples
                List<ResourceNode> relatedResources = new List<ResourceNode>();
                // use for merging relation
                List<ResourceNode> MergedResources = new List<ResourceNode>();
                // list of resources w/o dependency
                List<ResourceNode> isolatedResources = new List<ResourceNode>();
                foreach (var resourceNode in featureGroup.ToList())
                {
                    var resource = resourceNode.Resource;
                    string name = resource.ResourceName;
                    string type = resource.ResourceType;
                    var dependsOnList = resource.Resource.GetValueCaseInsensitive("dependsOn");
                    bool isAnyMatchedResourceFound = false;
                    if (dependsOnList != null && dependsOnList.Any())
                    {
                        foreach (var dependency in dependsOnList)
                        {
                            try
                            {
                                string dependencyAsString = dependency.ToString().ToLower();
                                dependencyAsString = ParseArmFunctionAndParam(dependencyAsString, ParamAndVarKeys);
                                var dependencyComponentArray = dependencyAsString.Split('/');
                                var resourceType = dependencyComponentArray[0];
                                var matchedResourceList = featureGroup.ToList().Where(x => x.Resource.ResourceType.StartsWith(resourceType, StringComparison.OrdinalIgnoreCase)).ToList();
                                foreach (var matchedResource in matchedResourceList)
                                {
                                    var resourceNameString = ParseArmFunctionAndParam(matchedResource.Resource.ResourceName, ParamAndVarKeys);
                                    var resourceNameComponent = resourceNameString.Split('/');
                                    if (resourceNameComponent.Last().Equals(dependencyComponentArray.Last(), StringComparison.OrdinalIgnoreCase))
                                    {
                                        ResourceNode resourceTuple = (ResourceNode)resourceNode.Clone();
                                        resourceTuple.LastChildResource = matchedResource;
                                        resourceTuple.ChildResource = matchedResource;
                                        relatedResources.Add(resourceTuple);
                                        MergedResources.Add(resourceTuple);
                                        isAnyMatchedResourceFound = true;

                                    }
                                }
                            }
                            catch (Exception)
                            {
                                // No need to break execution
                                // IF any exception occures, treat as independent resource
                            }
                        }
                    }
                    if (!isAnyMatchedResourceFound)
                    {
                        ResourceNode resourceTuple = (ResourceNode)resourceNode.Clone();
                        resourceTuple.LastChildResource = null;
                        resourceTuple.ChildResource = null;
                        MergedResources.Add(resourceTuple);
                        relatedResources.Add(resourceTuple);
                    }
                }
                List<ResourceNode> ToBeRemoved = new List<ResourceNode>();
                bool isChangeHappened = false;
                do
                {
                    isChangeHappened = false;
                    for (int i = 0; i < MergedResources.Count; i++)
                    {
                        for (int j = 0; j < relatedResources.Count; j++)
                        {
                            if (MergedResources[i].LastChildResource != null && MergedResources[i].LastChildResource.Token.Equals(relatedResources[j].Token))
                            {
                              
                                MergedResources[i].LastChildResource.ChildResource = relatedResources[j].ChildResource;
                                MergedResources[i].LastChildResource = relatedResources[j].LastChildResource;
                                ToBeRemoved.Add(relatedResources[j]);
                                isChangeHappened = true;
                            }
                        }
                    }

                    foreach (var item in ToBeRemoved)
                    {
                        MergedResources.Remove(item);
                    }

                } while (isChangeHappened);
                for (int i = 0; i < MergedResources.Count; i++)
                {
                    List<ResourceModel> currentResourceSet = new List<ResourceModel>();
                    var resourceset = (ResourceNode)MergedResources[i].Clone();
                    while (resourceset != null)
                    {
                        currentResourceSet.Add(resourceset.Resource);
                        isolatedResources.RemoveAll(x => x.Token.Equals(resourceset.Token));
                        resourceset = resourceset.ChildResource;

                    }
                    if (currentResourceSet.Count > 0)
                    {
                        var resourceResults = resourceEvaluator.Evaluate(_resourceControlSets, currentResourceSet);
                        results.AddRange(resourceResults);
                    }
                }
                
            }
  
            return results;
        }

        private void SetResourceTypes()
        {
            foreach (var resourceControlSet in _resourceControlSets)
            {
                foreach (var control in resourceControlSet.Controls)
                {
                    control.FeatureName = resourceControlSet.FeatureName;
                    control.SupportedResources = resourceControlSet.supportedResourceTypes.ToArray().ToSingleString(" , ");
                }
            }
        }

        private static JObject ParseArmTemplateExternalParametersJsonString(string armTemplateExternalParametersJsonString)
        {
            armTemplateExternalParametersJsonString = armTemplateExternalParametersJsonString.IsNullOrWhiteSpace()
                ? "{}"
                : armTemplateExternalParametersJsonString;

            var armTemplateExternalParameters = JObject.Parse(armTemplateExternalParametersJsonString, new JsonLoadSettings
            {
                CommentHandling = CommentHandling.Ignore,
                LineInfoHandling = LineInfoHandling.Load
            });
            return armTemplateExternalParameters;
        }

        private static JObject ParseArmTemplateJsonString(string armTemplateJsonString)
        {
            if (armTemplateJsonString.IsNullOrWhiteSpace())
                throw new ArgumentException(nameof(armTemplateJsonString));

            var armTemplate = JObject.Parse(armTemplateJsonString, new JsonLoadSettings
            {
                CommentHandling = CommentHandling.Ignore,
                LineInfoHandling = LineInfoHandling.Load
            });
            return armTemplate;
        }

        private static string ParseArmFunctionAndParam(string dependencyString, Hashtable ParamAndVarKeys)
        {
            if (dependencyString.IsNotNullOrWhiteSpace())
            {
                if (dependencyString.CheckIsFunction())
                {
                    dependencyString = dependencyString.Remove(0, 1).Trim();
                    dependencyString = dependencyString.Remove(dependencyString.Length - 1, 1).Trim();
                }

                if (dependencyString.StartsWith("variables(", StringComparison.OrdinalIgnoreCase))
                {
                    dependencyString = dependencyString.Replace("variables(", "variables.");
                    dependencyString = ParseArmFunctionAndParam(dependencyString, ParamAndVarKeys);
                    if (ParamAndVarKeys.ContainsKey(dependencyString))
                    {
                        dependencyString = ParamAndVarKeys[dependencyString].ToString();
                    }
                }
                if (dependencyString.CheckIsFunction())
                {
                    dependencyString = ParseArmFunctionAndParam(dependencyString, ParamAndVarKeys);
                }
                dependencyString = dependencyString.Replace("parameters(", "parameters.");
                dependencyString = dependencyString.Replace("variables(", "variables.");
                if (dependencyString.StartsWith("resourceid("))
                {
                    dependencyString = dependencyString.Replace("resourceid(", "");
                    dependencyString = dependencyString.Replace(",", "/");
                }
                else
                {
                    dependencyString = dependencyString.Replace("concat(", "");
                    dependencyString = dependencyString.Replace(",", "");
                }
                Regex regEx = new Regex("[\')(,]");
                dependencyString = regEx.Replace(dependencyString, "");
                return dependencyString.Replace(" ", "");
            }
            else
            {
                return dependencyString;
            }
        }


    }
}
