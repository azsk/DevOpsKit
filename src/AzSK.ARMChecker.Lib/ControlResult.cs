using System.Collections.Generic;
using System.Linq;
using AzSK.ARMChecker.Lib.Extensions;
using Newtonsoft.Json;
using Newtonsoft.Json.Linq;

namespace AzSK.ARMChecker.Lib
{
    public class ControlResult : ResourceControlBase
    {
        public ControlResult()
        {
            ResultDataMarkers = new List<ControlResultDataMarker>();
        }

        public VerificationResult VerificationResult { get; set; }
        public bool IsTokenNotFound { get; set; }
        public bool IsTokenNotValid { get; set; }
        public ControlResultDataMarker ResourceDataMarker { get; set; }
        public IList<ControlResultDataMarker> ResultDataMarkers { get; set; }

        public static ControlResult NotSupported(JObject resourceObject)
        {
            const string notSupported = "NotSupported";
            var result = new ControlResult
            {
                Id = notSupported,
                ControlId = notSupported,
                Description = notSupported,
                Rationale = notSupported,
                Recommendation = notSupported,
                Severity = ControlSeverity.Low,
                VerificationResult = VerificationResult.NotSupported,
                ResourceType = resourceObject.GetValue("type").Value<string>(),
                ResourceDataMarker = BuildDataMarker(resourceObject, 250)
            };
            return result;
        }
        public static ControlResult ResourceNotFound(ResourceControl resourceControl)
        {
            var result = new ControlResult
            {
                Id = resourceControl.Id,
                ControlId = resourceControl.ControlId,
                Description = resourceControl.Description,
                Rationale = resourceControl.Rationale,
                Recommendation = resourceControl.Recommendation,
                Severity = resourceControl.Severity,
                VerificationResult = VerificationResult.Failed,
                ResourceType = resourceControl.ResourceType,
                ResourceDataMarker = BuildDataMarker(resourceControl.JsonPath[0], 250)
            };
            return result;
        }
        public static ControlResult Build(ResourceControl control, JObject resourceObject, JToken resultData,
            bool isTokenNotFound, VerificationResult verificationResult)
        {
            return Build(control, resourceObject, new List<JToken> { resultData }, isTokenNotFound, verificationResult);
        }

        public static ControlResult Build(ResourceControl control, JObject resourceObject, IEnumerable<JToken> resultTokens,
            bool isTokenNotFound, VerificationResult verificationResult)
        {
            var resourceDataMarker = BuildDataMarker(resourceObject, 150);
            var result = new ControlResult
            {
                Id = control.Id,
                ControlId = control.ControlId,
                Description = control.Description,
                Rationale = control.Rationale,
                Recommendation = control.Recommendation,
                Severity = control.Severity,
                VerificationResult = verificationResult,
                ResourceDataMarker = resourceDataMarker,
                IsTokenNotFound = isTokenNotFound,
                ResourceType = resourceObject.GetValue("type").Value<string>(),
                FeatureName = control.FeatureName,
                SupportedResources = control.SupportedResources,
                ResultDataMarkers = isTokenNotFound
                    ? new List<ControlResultDataMarker>()
                    : resultTokens.Select(x => BuildDataMarker(x)).ToList()
            };
            return result;
        }

        private static ControlResultDataMarker BuildDataMarker(JToken jToKen, int dataMarkerLength = int.MaxValue)
        {
            var dataMarker = new ControlResultDataMarker(0, jToKen.Path,
                jToKen.ToString(Formatting.Indented).TakeS(dataMarkerLength));
            var lineInfo = jToKen as IJsonLineInfo;
            dataMarker.LineNumber = lineInfo.LineNumber;
            return dataMarker;
        }

        private static ControlResultDataMarker BuildDataMarker(string JsonPath, int dataMarkerLength = int.MaxValue)
        {
            var dataMarker = new ControlResultDataMarker(-1, JsonPath, "");
            return dataMarker;
        }
    }
}
