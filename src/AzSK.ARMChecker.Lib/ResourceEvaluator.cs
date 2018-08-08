using System;
using System.Collections.Generic;
using System.Linq;
using AzSK.ARMChecker.Lib.Extensions;
using Newtonsoft.Json;
using Newtonsoft.Json.Linq;

namespace AzSK.ARMChecker.Lib
{
	public class ResourceEvaluator
	{
		private readonly JObject _template;
		private readonly JObject _externalParameters;
		private readonly ControlEvaluator _controlEvaluator;

		public ResourceEvaluator(JObject template, JObject externalParameters)
		{
			_template = template;
			_externalParameters = externalParameters;
			_controlEvaluator = new ControlEvaluator(template, externalParameters);
		}

		public IList<ControlResult> Evaluate(IList<ResourceControlSet> resourceControlSets, JObject resource)
		{
            var type = resource.GetValueCaseInsensitive<string>("type");
			var apiVersion = resource.GetValueCaseInsensitive<string>("apiVersion");
            var controlSet = resourceControlSets?.FirstOrDefault(
                x => x.supportedResourceTypes.Any(y => y.Equals(type, StringComparison.OrdinalIgnoreCase)));
			if (controlSet == null)
			{
				return new List<ControlResult> {ControlResult.NotSupported(resource)};
			}        
			var results = new List<ControlResult>();
            foreach (var control in controlSet.Controls)
			{
				var controlResult = _controlEvaluator.Evaluate(control, resource);
				results.Add(controlResult);
			}
            EvaluateNestedResources(controlSet, resource, results);
			return results;
		}

        public IList<ControlResult> EvaluateNew(IList<ResourceControlSet> resourceControlSets, IGrouping<string,ResourceModel> group)
        {
            var featureName = group.First().FeatureName;
            var controlSet = resourceControlSets?.FirstOrDefault(x=>x.FeatureName.Equals(featureName, StringComparison.OrdinalIgnoreCase));
            var results = new List<ControlResult>();
            var resources = group.ToList();
            // Check for controlSet.Controls empty
            foreach (var control in controlSet.Controls)
            {
                // Check empty object should not be added
                ControlResult controlResult = new ControlResult();
                foreach (var resource in resources)
                {
                    controlResult = _controlEvaluator.Evaluate(control, resource.Resource);
                    if(!controlResult.IsTokenNotFound)
                    {
                        break;
                    }      
                }
                results.Add(controlResult);
            }
            foreach(var resource in resources)
            {
                EvaluateNestedResources(controlSet, resource.Resource, results);
            }
            //EvaluateNestedResources(controlSet, resource, results);
            return results;
        }
        private void EvaluateNestedResources(ResourceControlSet controlSet, JObject resource, List<ControlResult> results)
		{
			var nestedResources = resource.GetValueCaseInsensitive("resources");
			if (nestedResources != null && nestedResources.Any())
			{
				foreach (JObject nestedResource in nestedResources)
				{
					var nestedResourceResults = this.Evaluate(controlSet.NestedResourcesControlSet, nestedResource);
					results.AddRange(nestedResourceResults);
				}
			}
		}

     //public void EvaluateLinkedResources(ResourceControlSet controlSet, List<ResourceModel> resources, List<ControlResult> results)
     //   {
     //       foreach(var linkedControlSet in controlSet.LinkedResourcesControlSet)
     //       {
     //           var resourceType = linkedControlSet.ResourceType;
     //           var apiVersions = linkedControlSet.ApiVersions;
     //           var linkedResources = resources.Where(x => x.ResourceType.Equals(resourceType)).ToList();
     //           if (linkedResources?.Count > 0)
     //           {
     //               var controlList = new List<ResourceControlSet>();
     //               controlList.Add(linkedControlSet);
     //               foreach (var resource in linkedResources)
     //               {
     //                   var nestedResourceResults = this.Evaluate(controlList, resource.Resource);
     //                   results.AddRange(nestedResourceResults);
     //                   if (linkedControlSet.LinkedResourcesControlSet?.Count > 0)
     //                   {
     //                       EvaluateLinkedResources(linkedControlSet, resource.LinkedResources, results);
     //                   }
     //               }
     //           }
     //           else
     //           {
     //               // Create Not found control result
     //               foreach (var control in linkedControlSet.Controls)
     //               {
     //                   var controlResult = ControlResult.ResourceNotFound(control);
     //                   results.Add(controlResult);
     //               }
     //           }
     //       }
        
     //   }
    }
}
