﻿using System;
using System.Collections.Generic;
using System.Linq;
using Newtonsoft.Json.Linq;
using AzSK.ARMChecker.Lib.Extensions;
using System.Collections;

namespace AzSK.ARMChecker.Lib
{
    public class ControlEvaluator
    {
        private readonly JObject _template;
        private  readonly JObject _externalParameters;
        private  static JObject _externalParametersDict;
        private static JObject _armTemplate;

        public ControlEvaluator(JObject template, JObject externalParameters)
        {
            _template = template;
            _externalParameters = externalParameters;
            SetParametersList();
        }
        public void SetParametersList()
        {
            _externalParametersDict = _externalParameters;
            _armTemplate = _template;
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
                case ControlMatchType.ItemProperties:
                    return EvaluateItemProperties(control, resource);
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
                case ControlMatchType.NullableSingleToken:
                    return EvaluateNullableSingleToken(control, resource);
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

        private static ControlResult EvaluateItemProperties(ResourceControl control, JObject resource)
        {
            var result = ExtractMultiToken(control, resource, out IEnumerable<object> actual, out CustomTokenControlData match);
            result.ExpectedValue = " '"+match.Key+" ':" + " '" + match.Value + "'";
            result.ExpectedProperty = control.JsonPath.ToSingleString(" | ");
            if (result.IsTokenNotFound || result.IsTokenNotValid) return result;
            bool keyValueFound = false;
            foreach (JObject obj in actual)
            {
                var dictObject = obj.ToObject<Dictionary<string, string>>();
                if(dictObject.ContainsKey(match.Key) && dictObject[match.Key] == match.Value)
                {
                    keyValueFound = true;
                    break;
                }
            } 
            if(keyValueFound)
            {
                result.VerificationResult = VerificationResult.Passed;
            }
            else
            {
                result.VerificationResult = VerificationResult.Failed;
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
            result.VerificationResult = VerificationResult.Verify;
            return result;
        }
    
        private static ControlResult EvaluateNullableSingleToken(ResourceControl control, JObject resource)
        {
            var result = ExtractSingleToken(control, resource, out object actual, out BooleanControlData match);
            result.ExpectedValue = "";
            result.ExpectedProperty = control.JsonPath.ToSingleString(" | ");
            if (result.IsTokenNotFound || result.IsTokenNotValid)
            {
                result.VerificationResult = VerificationResult.Passed;
            }
            else
            {
                result.VerificationResult = VerificationResult.Verify;
            }
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
                if(tokenNotFound)
                {
                    actual = default(TV);
                }
                else
                {
                    var tokenValue = default(TV);
                    bool paramterValueFound = false;
                    // Check if current token is parameter 
                    if (token.Value<String>().CheckIsParameter())
                    {
                        var parameterKey = token.Value<String>().GetParameterKey();
                        if (parameterKey != null)
                        {
                            // Check if parameter value is present in external parameter file
                            if (_externalParametersDict.ContainsKey("parameters"))
                            {
                                JObject externalParameters = _externalParametersDict["parameters"].Value<JObject>();
                                var externalParamValue = externalParameters.Properties().Where(p => p.Name == parameterKey).Select(p => p.Value["value"].Value<TV>());
                                if (externalParamValue != null && externalParamValue.Count() > 0)
                                {
                                    paramterValueFound = true;
                                    tokenValue = externalParamValue.First();
                                }

                            }
                            // If parameter value is not present in external parameter file, check for default value
                            if (!paramterValueFound)
                            {
                                JObject innerParameters = _armTemplate["parameters"].Value<JObject>();
                                tokenValue = innerParameters.Properties().Where(p => p.Name == parameterKey).Select(p => p.Value["defaultValue"].Value<TV>()).FirstOrDefault();
                            }
                        }
                    }
                    else
                    {
                        tokenValue = token.Value<TV>();
              
                    }
                    actual = tokenValue;
                }
                
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
                if (tokenNotFound)
                {
                    actual = default(IEnumerable<TV>);
                }
                else
                {
                    var tokenValues = default(IEnumerable<TV>);
                    bool paramterValueFound = false;
                    // Check if current token is parameter 
                    if (tokens.Values<TV>().First().ToString().CheckIsParameter())
                    {
                        var parameterKey = tokens.Values<String>().First().GetParameterKey();
                        if (parameterKey != null)
                        {
                            // Check if parameter value is present in external parameter file
                            if (_externalParametersDict.ContainsKey("parameters"))
                            {
                                JObject externalParameters = _externalParametersDict["parameters"].Value<JObject>();
                                var externalParamValue = externalParameters.Properties().Where(p => p.Name == parameterKey).Select(p => p.Value["value"].Values<TV>());
                                if (externalParamValue != null && externalParamValue.Count() > 0)
                                {
                                    paramterValueFound = true;
                                    tokenValues = externalParamValue.First();
                                }

                            }
                            // If parameter value is not present in external parameter file, check for default value
                            if (!paramterValueFound)
                            {
                                JObject innerParameters = _armTemplate["parameters"].Value<JObject>();
                                tokenValues = innerParameters.Properties().Where(p => p.Name == parameterKey).Select(p => p.Value["defaultValue"].Values<TV>()).FirstOrDefault();
                            }
                        }
                    }
                    else
                    {
                        tokenValues = tokens.Values<TV>();

                    }
                    actual = tokenValues;
                }
                //actual = tokenNotFound ? default(IEnumerable<TV>) : tokens.Values<TV>();
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
