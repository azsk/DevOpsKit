using System.Collections.Generic;

namespace AzSK.ARMChecker.Lib
{
    public class Features
    {
        public string FeatureName { get; set; }
        public IList<string> supportedResourceTypes { get; set; }
        public int count { get; set; }

    }
}
