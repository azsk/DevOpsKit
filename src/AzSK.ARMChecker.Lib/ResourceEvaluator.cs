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
				x => x.ResourceType.Equals(type, StringComparison.OrdinalIgnoreCase) &&
				     x.ApiVersions.Any(
						  y => y.Equals(apiVersion, StringComparison.OrdinalIgnoreCase)));
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
