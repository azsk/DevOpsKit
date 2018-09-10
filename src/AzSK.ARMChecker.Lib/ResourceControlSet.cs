using System;
using System.Collections.Generic;

namespace AzSK.ARMChecker.Lib
{
	public class ResourceControlSet
	{
		public string ResourceType { get; set; }
		public IList<string> ApiVersions { get; set; }
		public IList<ResourceControl> Controls { get; set; }
		public IList<ResourceControlSet> NestedResourcesControlSet { get; set; }
	}

	public class ResourceControlSetWrap
	{
		public IList<ResourceControlSet> ResourceControlSets { get; set; }
	}
}