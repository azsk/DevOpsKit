using System;
using Newtonsoft.Json.Linq;

namespace AzSK.ARMChecker.Lib.Extensions
{
	internal static class JExtensions
	{
		public static JToken GetValueCaseInsensitive(this JObject obj, string propertyName)
		{
			return obj.GetValue(propertyName, StringComparison.OrdinalIgnoreCase);
		}

		public static T GetValueCaseInsensitive<T>(this JObject obj, string propertyName)
		{
			return obj.GetValueCaseInsensitive(propertyName).Value<T>();
		}
	}
}
