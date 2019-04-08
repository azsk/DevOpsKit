using System;
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

        public static bool CheckIsFunction(this string input)
        {
            if (input.StartsWith("[") && input.EndsWith("]"))
            {
                return true;
            }
            else
            {
                return false;
            }
        }

        public static bool CheckIsParameter(this string input)
        {
            if (input.CheckIsFunction())
            {
                input = input.Remove(0, 1).Trim();
                input = input.Remove(input.Length - 1, 1).Trim();
                if(input.StartsWith("parameters(", StringComparison.OrdinalIgnoreCase))
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

        public static string GetParameterKey(this string input)
        {
            var match = Regex.Match(input, @"parameters\(\'(.*)\'\)");
            if(match.Success)
            {
                return match.Groups[1].Value;
            }
            else
            {
                return null;
            }
            
        }
    }
}