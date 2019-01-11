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
            //var apiVersion = resource.GetValueCaseInsensitive<string>("apiVersion");
            var controlSet = resourceControlSets?.FirstOrDefault(
                x => x.supportedResourceTypes.Any(y => y.Equals(type, StringComparison.OrdinalIgnoreCase)));
            if (controlSet == null)
            {
                return new List<ControlResult> { ControlResult.NotSupported(resource) };
            }
            var results = new List<ControlResult>();
            foreach (var control in controlSet.Controls)
            {
                control.FeatureName = controlSet.FeatureName;
                control.SupportedResources = controlSet.supportedResourceTypes.ToArray().ToSingleString(" , ");
                var controlResult = _controlEvaluator.Evaluate(control, resource);
                results.Add(controlResult);
            }
            EvaluateNestedResources(controlSet, resource, results);
            return results;
        }

        public IList<ControlResult> Evaluate(IList<ResourceControlSet> resourceControlSets, List<ResourceModel> resources)
        {
            var featureName = resources?.First().FeatureName;
            var controlSet = resourceControlSets?.FirstOrDefault(x => x.FeatureName.Equals(featureName, StringComparison.OrdinalIgnoreCase));
            var results = new List<ControlResult>();
            foreach (var control in controlSet.Controls)
            {
                List<string> resourcePathList = new List<string>();
                ControlResult controlResult = null;
                foreach (var resource in resources)
                {
                    controlResult = _controlEvaluator.Evaluate(control, resource.Resource);
                    resourcePathList.Add(controlResult.ResourceDataMarker.JsonPath);
                    if (!controlResult.IsTokenNotFound)
                    {
                        break;
                    }
                }
                if (controlResult != null)
                {
                    if (controlResult.IsTokenNotFound)
                    {
                        controlResult.ResourceDataMarker.JsonPath = resourcePathList.ToArray().ToSingleString(" , ");
                    }
                    results.Add(controlResult);
                }
            }
            foreach (var resource in resources)
            {
                EvaluateNestedResources(controlSet, resource.Resource, results);
            }

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
    }
}
