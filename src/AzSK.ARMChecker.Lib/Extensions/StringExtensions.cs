using System;
using System.Reflection;
using System.Security.Cryptography;
using System.Text;
using System.Text.RegularExpressions;

namespace AzSK.ARMChecker.Lib.Extensions
{
    internal static class StringExtensions
    {
        public static TEnum ToEnumSelection<TEnum>(this string value) where TEnum : struct
        {
            TEnum result;
            if (!Enum.TryParse(value, true, out result))
                throw new ArgumentException($"Input value is invalid. Enum conversion failed.", nameof(value));
            return result;
        }

        public static string Format(this string input, params object[] args)
        {
            return string.Format(input, args);
        }

        public static bool IsNullOrWhiteSpace(this string input)
        {
            return string.IsNullOrWhiteSpace(input);
        }

        public static bool IsNotNullOrWhiteSpace(this string input)
        {
            return !string.IsNullOrWhiteSpace(input);
        }

        public static bool NotEndsWith(this string input, string value)
        {
            return !input.EndsWith(value);
        }

        public static byte[] ToMD5Bytes(this string input)
        {
            using (var md5 = MD5.Create())
            {
                return md5.ComputeHash(Encoding.UTF8.GetBytes(input));
            }
        }

        public static string ToMD5(this string input)
        {
            if (input.IsNullOrWhiteSpace()) throw new ArgumentNullException(nameof(input));
            var hashBytes = input.ToMD5Bytes();
            return ToHexString(hashBytes);
        }

        public static byte[] ToSHA1Bytes(this string input)
        {
            using (var sha1 = SHA1.Create())
            {
                return sha1.ComputeHash(Encoding.UTF8.GetBytes(input));
            }
        }

        public static string ToSHA1(this string input)
        {
            if (input.IsNullOrWhiteSpace()) throw new ArgumentNullException(nameof(input));
            var hashBytes = input.ToSHA1Bytes();
            return ToHexString(hashBytes);
        }

        public static string TakeS(this string input, int length)
        {
            if (input.Length < 0) throw new ArgumentException("Invalid length", nameof(length));
            if (input.IsNull()) return input;
            if (input.Length <= length) return input;
            return input.Substring(0, length);
        }

        public static string Anonymize(this string input, int length = 8)
        {
            if (input.IsNullOrWhiteSpace()) throw new ArgumentNullException(nameof(input));
            if (input.Length < 0) throw new ArgumentException("Invalid length", nameof(length));
            var sha1 = input.ToSHA1().ToSHA1();
            return sha1.TakeS(length);
        }

        private static string ToHexString(byte[] hashBytes)
        {
            var sb = new StringBuilder();
            for (var i = 0; i < hashBytes.Length; i++)
                sb.Append(hashBytes[i].ToString("x2"));
            return sb.ToString();
        }

        public static string ToSingleString(this string[] stringArray, string sep)
        {
            string result = string.Join(sep, stringArray);
            return result; ;
        }

        // This will check value is function or not. 
        public static bool CheckIsFunction(this string inputFunction)
        {
            if (inputFunction.StartsWith("[") && inputFunction.EndsWith("]"))
            {
                return true;
            }
            else
            {
                return false;
            }
        }

        // This will check parameter function type or not.
        public static bool CheckIsParameter(this string inputParameters)
        {
            if (inputParameters.CheckIsFunction())
            {
                inputParameters = inputParameters.Remove(0, 1).Trim();
                inputParameters = inputParameters.Remove(inputParameters.Length - 1, 1).Trim();
                if (inputParameters.StartsWith("parameters(", StringComparison.OrdinalIgnoreCase))
                {
                    return true;
                }
                else
                {
                    return false;
                }

            }
            else
            {
                return false;
            }
        }

        // This will check variables function type or not.
        public static bool CheckIsVariable(this string inputVariables)
        {
            if (inputVariables.CheckIsFunction())
            {
                inputVariables = inputVariables.Remove(0, 1).Trim();
                inputVariables = inputVariables.Remove(inputVariables.Length - 1, 1).Trim();
                if (inputVariables.StartsWith("variables(", StringComparison.OrdinalIgnoreCase))
                {
                    return true;
                }
                else
                {
                    return false;
                }

            }
            else
            {
                return false;
            }
        }

        // This will check concat function type or not.
        public static bool CheckIsConcat(this string inputConcat)
        {
            if (inputConcat.CheckIsFunction())
            {
                inputConcat = inputConcat.Remove(0, 1).Trim();
                inputConcat = inputConcat.Remove(inputConcat.Length - 1, 1).Trim();
                if (inputConcat.StartsWith("concat(", StringComparison.OrdinalIgnoreCase))
                {
                    return true;
                }
                else
                {
                    return false;
                }

            }
            else
            {
                return false;
            }
        }

        // This will check substring function type or not.
        public static bool CheckIsSubString(this string inputSubstring)
        {
            if (inputSubstring.CheckIsFunction())
            {
                inputSubstring = inputSubstring.Remove(0, 1).Trim();
                inputSubstring = inputSubstring.Remove(inputSubstring.Length - 1, 1).Trim();
                if (inputSubstring.StartsWith("substring(", StringComparison.OrdinalIgnoreCase))
                {
                    return true;
                }
                else
                {
                    return false;
                }

            }
            else
            {
                return false;
            }
        }

        // This will check and return type of the function, its function type may be is parameters(), variables(), concat() or substring().
        public static string GetFunctionType(this string checkInputFunctionType)
        {
            if (checkInputFunctionType.CheckIsFunction())
            {
                checkInputFunctionType = checkInputFunctionType.Remove(0, 1).Trim();
                checkInputFunctionType = checkInputFunctionType.Remove(checkInputFunctionType.Length - 1, 1).Trim();
                if (checkInputFunctionType.StartsWith("parameters(", StringComparison.OrdinalIgnoreCase))
                {
                    return "parameters";
                }
                else if (checkInputFunctionType.StartsWith("variables(", StringComparison.OrdinalIgnoreCase))
                {
                    return "variables";
                }
                else if (checkInputFunctionType.StartsWith("concat(", StringComparison.OrdinalIgnoreCase))
                {
                    return "concat";
                }
                else if (checkInputFunctionType.StartsWith("substring(", StringComparison.OrdinalIgnoreCase))
                {
                    return "substring";
                }
                else
                {
                    return null;
                }
            }
            else
            {
                return null;
            }
        }

        // This will return key value present inside parameters(). 
        public static string GetParameterKey(this string inputParameters)
        {
            var match = Regex.Match(inputParameters, @"parameters\(\'(.*)\'\)");
            if (match.Success)
            {
                return match.Groups[1].Value;
            }
            else
            {
                return null;
            }

        }

        // This will return Key value present inside variables().
        public static string GetVariableKey(this string inputVariables)
        {
            var match = Regex.Match(inputVariables, @"variables\(\'(.*)\'\)");
            if (match.Success)
            {
                return match.Groups[1].Value;
            }
            else
            {
                return null;
            }

        }

        // This will return key value present inside Concat() function.
        public static string GetConcatKey(this string inputConcat)
        {
            var match = Regex.Match(inputConcat, @"(?<=(?<open>\()).*(?=(?<close-open>\)))");
            if (match.Success)
            {
                return match.Groups[0].Value;
            }
            else
            {
                return null;
            }

        }

        // This will return key value present inside substring() function.
        public static string GetSubStringKey(this string inputSubstring)
        {
            var match = Regex.Match(inputSubstring, @"(?<=(?<open>\()).*(?=(?<close-open>\)))");
            if (match.Success)
            {
                return match.Groups[0].Value;
            }
            else
            {
                return null;
            }

        }
        // Get variables() key from parameters() function E.g. parameters(variables("some value")).
        public static string GetVariablesKeyFromInsideFunction(this string input)
        {
            var match = Regex.Match(input, @"(?<=(?<open>\()).*(?=(?<close-open>\)))");
            if (match.Success)
            {
                return match.Groups[0].Value;
            }
            else
            {
                return null;
            }

        }
        // Get parameters() key from variables() function E.g. variables(parameters("some value")).

        public static string GetParameterKeyFromInsideFunction(this string input)
        {
            var match = Regex.Match(input, @"(?<=(?<open>\()).*(?=(?<close-open>\)))");
            if (match.Success)
            {
                return match.Groups[0].Value;
            }
            else
            {
                return null;
            }

        }


    }
}