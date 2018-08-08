using Newtonsoft.Json.Linq;
using System;
using System.Collections.Generic;
using System.Text;

namespace AzSK.ARMChecker.Lib
{
    public class ResourceModel
    {
        public string FeatureName { get; set; }
        public string ResourceName { get; set; }
        public string ResourceType { get; set; }
        public JObject Resource { get; set; }

        public string Token { get; set; }
        // delete this
        public List<ResourceModel> LinkedResources = new List<ResourceModel>();
    }
}
