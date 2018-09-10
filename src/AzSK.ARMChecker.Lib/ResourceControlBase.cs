using System.Collections.Generic;

namespace AzSK.ARMChecker.Lib
{
	public class ResourceControlBase
	{
		public string Id { get; set; }
		public string ControlId { get; set; }
		public bool IsEnabled { get; set; } = true;
		public string Description { get; set; }
		public string Rationale { get; set; }
		public string Recommendation { get; set; }
        public string ExpectedProperty { get; set; }
        public string ExpectedValue { get; set; }
        public ControlSeverity Severity { get; set; }
		public string ResourceType { get; set; }
	}
}