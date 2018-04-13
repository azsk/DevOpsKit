using System;
using System.Threading.Tasks;
using Newtonsoft.Json;
using Newtonsoft.Json.Converters;
using Newtonsoft.Json.Serialization;

namespace AzSK.ARMChecker.Lib.Extensions
{
	internal static class ObjectExtensions
	{
		private static readonly JsonSerializerSettings JsonSerializerSettings;

		static ObjectExtensions()
		{
			JsonSerializerSettings = new JsonSerializerSettings
			{
				ReferenceLoopHandling = ReferenceLoopHandling.Ignore,
				NullValueHandling = NullValueHandling.Include,
				Formatting = Formatting.None,
				ContractResolver = new CamelCasePropertyNamesContractResolver()
			};
			JsonSerializerSettings.Converters.Add(new StringEnumConverter());
		}

		public static bool IsNull(this object obj)
		{
			return obj == null;
		}

		public static bool IsNotNull(this object obj)
		{
			return obj != null;
		}

		public static Task<T> ToTask<T>(this T obj)
		{
			return Task.FromResult(obj);
		}

		public static string ToJson(this object obj, Formatting formatting = Formatting.None)
		{
			return JsonConvert.SerializeObject(obj, formatting, JsonSerializerSettings);
		}

		public static string ToPrettyJson(this object obj)
		{
			return obj.ToJson(Formatting.Indented);
		}

		public static T FromJsonTo<T>(this string value)
		{
			return JsonConvert.DeserializeObject<T>(value, JsonSerializerSettings);
		}

		public static TOut ConvertTo<TOut>(this IConvertible value) where TOut : IConvertible
		{
			if (value.IsNull())
				throw new ArgumentNullException(nameof(value));
			return (TOut) Convert.ChangeType(value, typeof(TOut));
		}
	}
}
