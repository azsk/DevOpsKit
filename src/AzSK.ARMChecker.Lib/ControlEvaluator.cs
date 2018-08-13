using System;
using System.Collections.Generic;
using System.Linq;
using Newtonsoft.Json.Linq;
using AzSK.ARMChecker.Lib.Extensions;

namespace AzSK.ARMChecker.Lib
{
    public class ControlEvaluator
    {
        private readonly JObject _template;
        private readonly JObject _externalParameters;

        public ControlEvaluator(JObject template, JObject externalParameters)
        {
            _template = template;
            _externalParameters = externalParameters;
        }

        public ControlResult Evaluate(ResourceControl control, JObject resource)
        {
            switch (control.MatchType)
            {
                case ControlMatchType.Null:
                    return ControlResult.NotSupported(resource);
                case ControlMatchType.Boolean:
                    return EvaluateBoolean(control, resource);
                case ControlMatchType.IntegerValue:
                    return EvaluateIntegerValue(control, resource);
                case ControlMatchType.ItemCount:
                    return EvaluateItemCount(control, resource);
                case ControlMatchType.StringLength:
                    return ControlResult.NotSupported(resource);
                case ControlMatchType.StringWhitespace:
                    return EvaluateStringWhitespace(control, resource);
                case ControlMatchType.StringSingleToken:
                    return EvaluateStringSingleToken(control, resource);
                case ControlMatchType.StringMultiToken:
                    return ControlResult.NotSupported(resource);
                case ControlMatchType.RegExpressionSingleToken:
                    return ControlResult.NotSupported(resource);
                case ControlMatchType.RegExpressionMultiToken:
                    return ControlResult.NotSupported(resource);
                case ControlMatchType.VerifiableSingleToken:
                    return EvaluateVerifiableSingleToken(control, resource);
                case ControlMatchType.VerifiableMultiToken:
                    return ControlResult.NotSupported(resource);
                case ControlMatchType.Custom:
                    return ControlResult.NotSupported(resource);
                default:
                    throw new ArgumentOutOfRangeException();
            }
        }

        private static ControlResult EvaluateBoolean(ResourceControl control, JObject resource)
        {
            var result = ExtractSingleToken(control, resource, out bool actual, out BooleanControlData match);
            result.ExpectedValue = "'" + match.Value.ToString() + "'";
            result.ExpectedProperty = control.JsonPath.ToSingleString(" | ");
            if (result.IsTokenNotFound || result.IsTokenNotValid) return result;
            if (actual == match.Value)
            {
                result.VerificationResult = VerificationResult.Passed;
            }
            return result;
        }

        private static ControlResult EvaluateIntegerValue(ResourceControl control, JObject resource)
        {
            var result = ExtractSingleToken(control, resource, out int actual, out IntegerValueControlData match);
            result.ExpectedValue = match.Type.ToString() + " " + match.Value.ToString();
            result.ExpectedProperty = control.JsonPath.ToSingleString(" | ");
            if (result.IsTokenNotFound || result.IsTokenNotValid) return result;
            switch (match.Type)
            {
                case ControlDataMatchType.GreaterThan:
                    if (actual > match.Value) result.VerificationResult = VerificationResult.Passed;
                    break;
                case ControlDataMatchType.LesserThan:
                    if (actual < match.Value) result.VerificationResult = VerificationResult.Passed;
                    break;
                case ControlDataMatchType.Equals:
                    if (actual == match.Value) result.VerificationResult = VerificationResult.Passed;
                    break;
                default:
                    throw new ArgumentOutOfRangeException();
            }
            return result;
        }

        private static ControlResult EvaluateItemCount(ResourceControl control, JObject resource)
        {
            var result = ExtractMultiToken(control, resource, out IEnumerable<object> actual, out IntegerValueControlData match);
            result.ExpectedValue = "Count " + match.Type.ToString() + " " + match.Value.ToString();
            result.ExpectedProperty = control.JsonPath.ToSingleString(" | ");
            if (result.IsTokenNotFound || result.IsTokenNotValid) return result;
            var count = actual.Count();
            switch (match.Type)
            {
                case ControlDataMatchType.GreaterThan:
                    if (count > match.Value) result.VerificationResult = VerificationResult.Passed;
                    break;
                case ControlDataMatchType.LesserThan:
                    if (count < match.Value) result.VerificationResult = VerificationResult.Passed;
                    break;
                case ControlDataMatchType.Equals:
                    if (count == match.Value) result.VerificationResult = VerificationResult.Passed;
                    break;
                default:
                    throw new ArgumentOutOfRangeException();
            }
            return result;
        }

        private static ControlResult EvaluateStringWhitespace(ResourceControl control, JObject resource)
        {
            var result = ExtractSingleToken(control, resource, out string actual, out BooleanControlData match);
            result.ExpectedValue = (match.Value) ? "Null string" : "Non-null string";
            result.ExpectedProperty = control.JsonPath.ToSingleString(" | ");
            if (result.IsTokenNotFound || result.IsTokenNotValid) return result;
            if (string.IsNullOrWhiteSpace(actual) == match.Value)
            {
                result.VerificationResult = VerificationResult.Passed;
            }
            return result;
        }

        private static ControlResult EvaluateStringSingleToken(ResourceControl control, JObject resource)
        {
            var result = ExtractSingleToken(control, resource, out string actual, out StringSingleTokenControlData match);
            result.ExpectedValue = match.Type + " '" + match.Value + "'";
            result.ExpectedProperty = control.JsonPath.ToSingleString(" | ");
            if (result.IsTokenNotFound || result.IsTokenNotValid) return result;
            if (match.Value.Equals(actual,
                match.IsCaseSensitive ? StringComparison.Ordinal : StringComparison.OrdinalIgnoreCase))
            {
                if (match.Type == ControlDataMatchType.Allow)
                {
                    result.VerificationResult = VerificationResult.Passed;
                }
            }
            else
            {
                if (match.Type == ControlDataMatchType.NotAllow)
                {
                    result.VerificationResult = VerificationResult.Passed;
                }
            }
            return result;
        }

        private static ControlResult EvaluateVerifiableSingleToken(ResourceControl control, JObject resource)
        {
            var result = ExtractSingleToken(control, resource, out object actual, out BooleanControlData match);
            result.ExpectedValue = "Verify current value";
            result.ExpectedProperty = control.JsonPath.ToSingleString(" | ");
            if (result.IsTokenNotFound || result.IsTokenNotValid) return result;
            result.VerificationResult = VerificationResult.Passed;
            return result;
        }

        private static ControlResult ExtractSingleToken<TV, TM>(ResourceControl control, JObject resource, out TV actual,
            out TM match)
        {
            JToken token = null;
            foreach (var jsonPath in control.JsonPath)
            {
                token = resource.SelectToken(jsonPath);
                if (token != null)
                {
                    break;
                }
            }
            var tokenNotFound = token == null;
            var result = ControlResult.Build(control, resource, token, tokenNotFound, VerificationResult.Failed);
            if (tokenNotFound) result.IsTokenNotValid = true;
            try
            {
                actual = tokenNotFound ? default(TV) : token.Value<TV>();
            }
            catch (Exception)
            {
                actual = default(TV);
                result.IsTokenNotValid = true;
            }
            match = control.Data.ToObject<TM>();
            return result;
        }

        private static ControlResult ExtractMultiToken<TV, TM>(ResourceControl control, JObject resource,
            out IEnumerable<TV> actual,
            out TM match)
        {
            IEnumerable<JToken> tokens = null;
            foreach (var jsonPath in control.JsonPath)
            {
                tokens = resource.SelectTokens(jsonPath);
                if (tokens != null)
                {
                    break;
                }
            }
            var tokenNotFound = tokens == null;
            var result = ControlResult.Build(control, resource, tokens, tokenNotFound, VerificationResult.Failed);
            if (tokenNotFound) result.IsTokenNotValid = true;
            try
            {
                actual = tokenNotFound ? default(IEnumerable<TV>) : tokens.Values<TV>();
            }
            catch (Exception)
            {
                actual = default(IEnumerable<TV>);
                result.IsTokenNotValid = true;
            }
            match = control.Data.ToObject<TM>();
            return result;
        }

    }
}
