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
			var results = new List<ControlResult>();
            // Get list of all primary resources
            var listOfAllPrimaryResource = _resourceControlSets.Select(x => new { SupportedResourceTypes = x.supportedResourceTypes, FeatureName = x.FeatureName }).ToList();//.ToDictionary(x=>x.ResourceType,x=>x.FeatureName);
            // Fetch all resources , variables , parameters
            var resources = armTemplate.GetValueCaseInsensitive("resources");
            var parameters = armTemplate.GetValueCaseInsensitive("parameters");
            var variables = armTemplate.GetValueCaseInsensitive("variables");
            // Create a hashtable for all parameters and variables 
            // TODO : Check for case of var and params 
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
            List<ResourceModel> ResourceList = new List<ResourceModel>();
            // Create initial list of all resource without linking
            foreach (JObject resource in resources)
            {
                var type = resource.GetValueCaseInsensitive<string>("type");
                var name = resource.GetValueCaseInsensitive<string>("name");        
                var featureSet = listOfAllPrimaryResource?.FirstOrDefault(x => x.SupportedResourceTypes.Any(y => y.Equals(type, StringComparison.OrdinalIgnoreCase)));
                if (featureSet != null)
                {
                    ResourceModel resourceModel = new ResourceModel();
                    resourceModel.FeatureName = featureSet.FeatureName;
                    resourceModel.ResourceType = type;
                    resourceModel.ResourceName = name;
                    resourceModel.Resource = resource;
                    ResourceList.Add(resourceModel);
                }                             
            }
            var groupedResources = ResourceList.GroupBy(x => x.FeatureName);
            foreach(var group in groupedResources)
            {
                var tokenKey = group.Key;
                int tokenIndex = 0;
                foreach (var resource in group.ToList())
                {
                    // TODO: What if we have multiple resource depending on single resource 
                    if(resource.Token.IsNullOrWhiteSpace())
                    {
                        resource.Token = tokenKey + tokenIndex++;
                    }
                    string name = resource.ResourceName;
                    string type = resource.ResourceType;
                    var dependsOnList = resource.Resource.GetValueCaseInsensitive("dependsOn");
                    if (dependsOnList != null)
                    {
                        foreach (var dependency in dependsOnList)
                        {
                            string dependencyAsString = dependency.ToString().ToLower();

                            dependencyAsString = ParseDependencyString(dependencyAsString,ParamAndVarKeys);

                            //if (dependencyAsString.StartsWith("[") && dependencyAsString.EndsWith("]"))
                            //{
                            //    dependencyAsString = dependencyAsString.Remove(0, 1).Trim();
                            //    dependencyAsString = dependencyAsString.Remove(dependencyAsString.Length - 1, 1).Trim();
                            //    if (dependencyAsString.StartsWith("variables(", StringComparison.OrdinalIgnoreCase))
                            //    {
                            //        dependencyAsString = ParseDependencyString(dependencyAsString);
                            //        dependencyAsString = ParamAndVarKeys[dependencyAsString].ToString();
                            //    }
                            //}
                            //dependencyAsString = ParseDependencyString(dependencyAsString);
                            var dependencyArray = dependencyAsString.Split('/');
                            var resourceType = dependencyArray[0];
                            var resourceName = dependencyArray.Last();
                            var matchedResourceList = ResourceList.Where(x => x.ResourceType.StartsWith(resourceType, StringComparison.OrdinalIgnoreCase)).ToList();
                            foreach (var matchedResource in matchedResourceList)
                            {
                                var resourceNameString = ParseDependencyString(matchedResource.ResourceName,ParamAndVarKeys);
                                var splitResourceName = resourceNameString.Split('/');
                                if (splitResourceName.Last().Equals(dependencyArray.Last(), StringComparison.OrdinalIgnoreCase))
                                {
                                    if(matchedResource.Token.IsNullOrWhiteSpace())
                                    {
                                        matchedResource.Token = resource.Token;
                                    }
                                    else
                                    {
                                        resource.Token = matchedResource.Token;
                                    }
                                }
                            }
                        }
                    }
                }
            }
            // Grouping linked resources
            //foreach (var resource in ResourceList)
            //{
            //    string name = resource.ResourceName;
            //    string type = resource.ResourceType;
            //    var dependsOnList = resource.Resource.GetValueCaseInsensitive("dependsOn");
            //    if (dependsOnList != null)
            //    {
            //        foreach (var dependency in dependsOnList)
            //        {                    
            //            string dependencyAsString = dependency.ToString().ToLower();
            //            if(dependencyAsString.StartsWith("[") && dependencyAsString.EndsWith("]"))
            //            {
            //                dependencyAsString = dependencyAsString.Remove(0, 1).Trim();
            //                dependencyAsString = dependencyAsString.Remove(dependencyAsString.Length-1, 1).Trim();
            //                if(dependencyAsString.StartsWith("variables(",StringComparison.OrdinalIgnoreCase))
            //                {
            //                    dependencyAsString = ParseDependencyString(dependencyAsString);
            //                    dependencyAsString = ParamAndVarKeys[dependencyAsString].ToString();
            //                }
            //            }                 
            //            dependencyAsString = ParseDependencyString(dependencyAsString);
            //            var dependencyArray = dependencyAsString.Split('/');
            //            var resourceType = dependencyArray[0];
            //            var resourceName = dependencyArray.Last();
            //            var matchedResourceList = ResourceList.Where(x => x.ResourceType.StartsWith(resourceType, StringComparison.OrdinalIgnoreCase)).ToList();
            //            foreach (var matchedResource in matchedResourceList)
            //            {
            //                   var resourceNameString = ParseDependencyString(matchedResource.ResourceName);
            //                   var splitResourceName = resourceNameString.Split('/');
            //                   if (splitResourceName.Last().Equals(dependencyArray.Last(),StringComparison.OrdinalIgnoreCase))
            //                   {
            //                        matchedResource.LinkedResources.Add(resource);
            //                   }                         
            //            }

            //            //if (isFunction)
            //            //{
            //            //    Match match = Regex.Match(dependency.ToString(), "\'Microsoft.*\',");
            //            //    if (match.Success)
            //            //    {
            //            //        Regex regEx = new Regex("[\',]");
            //            //        string dependentResourceType = regEx.Replace(match.Value, "");
            //            //        var matchedResourceList = ResourceList.Where(x => x.ResourceType.Equals(dependentResourceType, StringComparison.OrdinalIgnoreCase)).ToList();
            //            //        List<string> matchedParams = new List<string>();
            //            //        foreach (DictionaryEntry item in ParamAndVarKeys)
            //            //        {
            //            //            int startIndex = dependency.ToString().IndexOf(item.Value.ToString().Replace("parameters.", ""));
            //            //            if (startIndex != -1)
            //            //            {
            //            //                matchedParams.Add(item.Value.ToString().Replace("parameters.", ""));
            //            //            }
            //            //        }
            //            //        foreach (var matchedResource in matchedResourceList)
            //            //        {
            //            //            foreach (var param in matchedParams)
            //            //            {
            //            //                if (matchedResource.ResourceName.IndexOf(param) != -1)
            //            //                {
            //            //                    matchedResource.LinkedResources.Add(resource);
            //            //                }
            //            //            }
            //            //        }
            //            //    }
            //            //}

            //        }
            //    }
            //}
            var linkedResourcesGroup = ResourceList.GroupBy(x => x.Token);
            var resourceEvaluator = new ResourceEvaluator(armTemplate, armTemplateExternalParameters);
            foreach(var group in linkedResourcesGroup)
            {
                var resourceResults = resourceEvaluator.EvaluateNew(_resourceControlSets, group);
                results.AddRange(resourceResults);
            }
       //     foreach(var res in ResourceList.Where(x => x.FeatureName.IsNotNullOrWhiteSpace()).ToList())
       //     {
       //         var resourceResults = resourceEvaluator.Evaluate(_resourceControlSets, res.Resource);
       //         results.AddRange(resourceResults);
       //         var type = res.Resource.GetValueCaseInsensitive<string>("type");
			    //var apiVersion = res.Resource.GetValueCaseInsensitive<string>("apiVersion");
       //         var controlSet = _resourceControlSets?.FirstOrDefault(
       //          x => x.ResourceType.Equals(type, StringComparison.OrdinalIgnoreCase) &&
       //            x.ApiVersions.Any(
       //                 y => y.Equals(apiVersion, StringComparison.OrdinalIgnoreCase)));
       //         if (controlSet?.LinkedResourcesControlSet.Count > 0)
       //         {
       //           resourceEvaluator.EvaluateLinkedResources(controlSet, res.LinkedResources, results);                                
       //         }
       //     }      
            return results;
		}

		private void SetResourceTypes()
		{
			foreach (var resourceControlSet in _resourceControlSets)
			foreach (var control in resourceControlSet.Controls)
				control.ResourceType = resourceControlSet.FeatureName;
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

        private static string ParseDependencyString(string dependencyString,Hashtable ParamAndVarKeys)
        {
            if (dependencyString.CheckIsFunction())
            {
                dependencyString = dependencyString.Remove(0, 1).Trim();
                dependencyString = dependencyString.Remove(dependencyString.Length - 1, 1).Trim();
            }
                  
            if (dependencyString.StartsWith("variables(", StringComparison.OrdinalIgnoreCase))
            {
                dependencyString = dependencyString.Replace("variables(", "variables.");
                dependencyString = ParseDependencyString(dependencyString, ParamAndVarKeys);
                dependencyString = ParamAndVarKeys[dependencyString].ToString();
            }
            if(dependencyString.CheckIsFunction())
            {
                dependencyString = ParseDependencyString(dependencyString, ParamAndVarKeys);
            }
            dependencyString = dependencyString.Replace("parameters(", "parameters.");
            dependencyString = dependencyString.Replace("variables(", "variables.");
            if (dependencyString.StartsWith("resourceId("))
            {
                dependencyString = dependencyString.Replace("resourceId(", "");
                dependencyString = dependencyString.Replace(",", "/");
            }
            else
            {
                dependencyString = dependencyString.Replace("concat(", "");
                dependencyString = dependencyString.Replace(",", "");
            }
            Regex regEx = new Regex("[\')(,]");
            dependencyString = regEx.Replace(dependencyString, "");
            return dependencyString.Replace(" ","");
        }


	}
}
