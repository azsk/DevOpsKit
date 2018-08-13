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
    }

    public class ResourceNode : ICloneable
    {
        public string Token { get; set; }

        public ResourceModel Resource { get; set; }

        public ResourceNode ChildResource { get; set; }

        public ResourceNode LastChildResource { get; set; }

        public object Clone()
        {
            ResourceNode nd = new ResourceNode();
            nd.Resource = this.Resource;
            nd.Token = this.Token;
            nd.ChildResource = this.ChildResource;
            nd.LastChildResource = this.LastChildResource;
            return nd;
        }
    }


}
