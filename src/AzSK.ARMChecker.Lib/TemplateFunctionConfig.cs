using System;

namespace AzSK.ARMChecker.Lib
{
	public class TemplateFunctionConfig
	{
		public string SubscriptionId { get; set; }
		public string ResourceGroupName { get; set; }
		public string ResourceGroupLocation { get; set; }

		static TemplateFunctionConfig()
		{
			Defaults = new TemplateFunctionConfig
			{
				SubscriptionId = Guid.Empty.ToString(),
				ResourceGroupName = "DefaultRG",
				ResourceGroupLocation = "US East"
			};
		}

		public static TemplateFunctionConfig Defaults;
	}
}