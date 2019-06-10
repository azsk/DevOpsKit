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
        private static int index = 0;
        private readonly IList<ResourceControlSet> _resourceControlSets;
        private List<ResourceNode> ResourceList = new List<ResourceNode>();
        private List<Features> listOfAllPrimaryResource=new List<Features>();
        
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
            ResourceList.Clear();
            // Get list of all primary resources
            foreach (ResourceControlSet i in _resourceControlSets)
            {
                Features c = new Features();
                c.FeatureName = i.FeatureName;
                c.supportedResourceTypes = i.supportedResourceTypes;
                c.count = i.supportedResourceTypes.Count();
                listOfAllPrimaryResource.Add(c);
            }
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
            ConvertToFlatResourceList(resources);
            var groupedResources = ResourceList?.GroupBy(x => x.Resource.FeatureName);
            // Use for intial relation tuples
            List<ResourceNode> relatedResources = new List<ResourceNode>();
            // use for merging relation
            List<ResourceNode> MergedResources = new List<ResourceNode>();
            // list of resources w/o dependency
            List<ResourceNode> isolatedResources = new List<ResourceNode>();
            foreach (var featureGroup in groupedResources)
            {
                
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
                                foreach (var matchedResource in featureGroup.ToList())
                                {
                                    var resourceNameString = ParseArmFunctionAndParam(matchedResource.Resource.ResourceName, ParamAndVarKeys);
                                    var resourceNameComponent = resourceNameString.Split('/');
                                    if (resourceNameComponent.Last().Equals(dependencyComponentArray.Last(), StringComparison.OrdinalIgnoreCase) && resourceNode.Token != matchedResource.Token)
                                    {
                                        ResourceNode resourceTuple = (ResourceNode)resourceNode.Clone();
                                        resourceTuple.LastChildResource = matchedResource;
                                        resourceTuple.ChildResource = matchedResource;
                                        resourceTuple.count = resourceNode.count + 1;
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
                        resourceTuple.count = 1;
                        MergedResources.Add(resourceTuple);
                        relatedResources.Add(resourceTuple);
                    }
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
                            if (i != j && MergedResources[i].LastChildResource != null && MergedResources[i].LastChildResource.Token.Equals(relatedResources[j].Token))
                            {
                                MergedResources[i].LastChildResource.ChildResource = relatedResources[j].ChildResource;
                                MergedResources[i].LastChildResource = relatedResources[j].LastChildResource;
                                MergedResources[i].count = MergedResources[i].count + relatedResources[j].count - 1;
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
                    for (int j = i+1; j < MergedResources.Count; j++)
                    {
                    if (MergedResources[i].Resource.Resource == MergedResources[j].Resource.Resource)
                    {
                        var merged_i = MergedResources[i];
                        var merged_j = MergedResources[j];
                        while (merged_i.ChildResource != null)
                            merged_i = merged_i.ChildResource;
                        while (merged_j.ChildResource != null)
                            merged_j = merged_j.ChildResource;
                        if(merged_i.Resource.Resource==merged_j.Resource.Resource)
                        {
                            if (MergedResources[i].count < MergedResources[j].count)
                            {
                                MergedResources.Remove(MergedResources[i]);
                            }
                            else
                            {
                                MergedResources.Remove(MergedResources[j]);
                            }
                        }
                        
                    }
                    }
                }
                for (int i = 0; i < MergedResources.Count; i++)
                {
                    var fname = MergedResources[i].Resource.FeatureName;
                    var temp = (ResourceNode)MergedResources[i].Clone();
                    int count=0;
                    IList<string> supported=new List<string>();
                    IList<string> missed = new List<string>();
                    foreach (Features x in listOfAllPrimaryResource)
                    {
                    if (x.FeatureName == fname)
                    {
                        count = x.count;
                        supported = x.supportedResourceTypes;
                    }

                    }
                    for(int k=0;k<supported.Count;k++)
                    {
                        var resourceset = (ResourceNode)MergedResources[i].Clone();
                        int flag = 0;
                        while (resourceset!=null)
                        {
                            if (resourceset.Resource.ResourceType==supported[k])
                            {
                                flag = 1;
                            }
                            resourceset = resourceset.ChildResource;
                        }
                        if(flag==0)
                        {
                            missed.Add(supported[k]);
                        }
                    }
                    for (int j = i+1; j < MergedResources.Count; j++)
                    {
                        if(MergedResources[j].Resource.FeatureName==fname)
                        {
                            var resourceset = (ResourceNode)MergedResources[j].Clone();
                            var resourceset1 = resourceset;
                            while (resourceset != null)
                            {
                                if (missed.Contains(resourceset.Resource.ResourceType))
                                {
                                    var dependsOnList = resourceset.Resource.Resource.GetValueCaseInsensitive("dependsOn");
                                    if (dependsOnList != null && dependsOnList.Any())
                                    {
                                        foreach (var dependency in dependsOnList)
                                        {
                                            string dependencyAsString = dependency.ToString().ToLower();
                                            dependencyAsString = ParseArmFunctionAndParam(dependencyAsString, ParamAndVarKeys);
                                            var dependencyComponentArray = dependencyAsString.Split('/');
                                            var t_resourceset = (ResourceNode)MergedResources[i].Clone();
                                            while (t_resourceset!=null)
                                            {
                                                var resourceNameString = ParseArmFunctionAndParam(t_resourceset.Resource.ResourceName, ParamAndVarKeys);
                                                var resourceNameComponent = resourceNameString.Split('/');
                                                if (resourceNameComponent.Last().Equals(dependencyComponentArray.Last(), StringComparison.OrdinalIgnoreCase))
                                                {
                                                        var temp1 = temp;
                                                        resourceset.ChildResource = temp1;
                                                        temp = resourceset1;
                                                        MergedResources.Remove(MergedResources[j]);
                                                        j--;
                                                        MergedResources[i]=temp;
                                                        goto Gt;
                                                }
                                                t_resourceset = t_resourceset.ChildResource;
                                            }
                                        }
                                    }
                                    var remove = MergedResources[i];
                                    while(remove!=null)
                                    {
                                        missed.Remove(remove.Resource.ResourceType);
                                        remove = remove.ChildResource;
                                    }
                                }
                                resourceset = resourceset.ChildResource;
                            }
                        }
                    Gt:;
                    }
                }
                 for (int i = 0; i < MergedResources.Count; i++)
                 {
                   var resourceset = (ResourceNode)MergedResources[i].Clone();
                  IList<string> i_supported = new List<string>();
                    while (resourceset != null)
                    {
                    i_supported.Add(resourceset.Resource.ResourceType);
                    resourceset = resourceset.ChildResource;
                    }
                    resourceset = (ResourceNode)MergedResources[i].Clone();
                    for (int j=0;j<MergedResources.Count;j++)
                    {
                        if (i != j)
                        {
                            var resourceset1 = (ResourceNode)MergedResources[j].Clone();
                            while (resourceset1 != null)
                            {
                                if (i_supported.Contains(resourceset1.Resource.ResourceType) == false)
                                {
                                var dependsOnList = resourceset1.Resource.Resource.GetValueCaseInsensitive("dependsOn");
                                var Source_resourcetype = resourceset1.Resource.Resource.GetValueCaseInsensitive("type").ToString();
                                Source_resourcetype = Source_resourcetype.Split('/')[0];
                                if (dependsOnList != null && dependsOnList.Any())
                                {
                                    foreach (var dependency in dependsOnList)
                                    {
                                        string dependencyAsString = dependency.ToString().ToLower();
                                        dependencyAsString = ParseArmFunctionAndParam(dependencyAsString, ParamAndVarKeys);
                                        var dependencyComponentArray = dependencyAsString.Split('/');
                                        var t_resourceset = (ResourceNode)MergedResources[i].Clone();
                                        while (t_resourceset != null)
                                        {
                                            var resourceNameString = ParseArmFunctionAndParam(t_resourceset.Resource.ResourceName, ParamAndVarKeys);
                                            var resourceNameComponent = resourceNameString.Split('/');
                                            var Target_resourcetype = t_resourceset.Resource.Resource.GetValueCaseInsensitive("type").ToString();
                                            Target_resourcetype = Target_resourcetype.Split('/')[0];
                                            if (resourceNameComponent.Last().Equals(dependencyComponentArray.Last(), StringComparison.OrdinalIgnoreCase) && Source_resourcetype.Equals(Target_resourcetype))
                                            {
                                                ResourceNode rn = new ResourceNode();
                                                rn.Resource = resourceset1.Resource;
                                                rn.ChildResource = resourceset;
                                                resourceset=rn;
                                            }
                                            t_resourceset = t_resourceset.ChildResource;
                                        }
                                    }
                                }
                            }
                            resourceset1 = resourceset1.ChildResource;
                            }
                        }
                      
                    }
                MergedResources[i] = resourceset;
                 }
                
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

        public void ConvertToFlatResourceList(JToken resources, string parentResourceType =null)
        {
           
            foreach (JObject resource in resources)
            {
                if(parentResourceType != null)
                {
                    var type = resource.GetValueCaseInsensitive<string>("type");
                    type = parentResourceType + "/"+ type;
                    resource["type"] = type;
                }

                if (resource.GetValueCaseInsensitive("resources") != null)
                {
                    var childResources = resource.GetValueCaseInsensitive("resources");
                    resource.Remove("resources");
                    CreateInitialResourceList(resource);
                    string parentType = resource.GetValueCaseInsensitive<string>("type");
                    ConvertToFlatResourceList(childResources, parentType);
                }
                else
                {
                    CreateInitialResourceList(resource);
                }
            }
        }
        public void CreateInitialResourceList(JObject resource)
        {

                // Create initial list of all resource without linking
                var type = resource.GetValueCaseInsensitive<string>("type");
                var name = resource.GetValueCaseInsensitive<string>("name");
                var featureSet = listOfAllPrimaryResource?.FirstOrDefault(x => x.supportedResourceTypes.Any(y => y.Equals(type, StringComparison.OrdinalIgnoreCase)));
                // Console.WriteLine(featureSet);
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
                    resourceNode.count = 1;
                    ResourceList.Add(resourceNode);
                }
            

        }
    }
}
