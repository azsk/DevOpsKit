using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
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
			var resources = armTemplate.GetValueCaseInsensitive("resources");
			var resourceEvaluator = new ResourceEvaluator(armTemplate, armTemplateExternalParameters);
			foreach (JObject resource in resources)
			{
				var resourceResults = resourceEvaluator.Evaluate(_resourceControlSets, resource);
				results.AddRange(resourceResults);
			}        
            return results;
		}

		private void SetResourceTypes()
		{
			foreach (var resourceControlSet in _resourceControlSets)
			foreach (var control in resourceControlSet.Controls)
				control.ResourceType = resourceControlSet.ResourceType;
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
	}
}
