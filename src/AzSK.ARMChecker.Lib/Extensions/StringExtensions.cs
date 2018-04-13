using System;
using System.Security.Cryptography;
using System.Text;

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
	}
}