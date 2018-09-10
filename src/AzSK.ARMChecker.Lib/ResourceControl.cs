using System.Collections.Generic;
using Newtonsoft.Json.Linq;

namespace AzSK.ARMChecker.Lib
{
    public class ResourceControl : ResourceControlBase
    {
        public string[] JsonPath { get; set; }
        public ControlMatchType MatchType { get; set; }
        public JObject Data { get; set; }
        public string[] ApiVersions { get; set; }
    }
}