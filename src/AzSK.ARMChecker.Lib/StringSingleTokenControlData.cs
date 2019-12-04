namespace AzSK.ARMChecker.Lib
{
	public class StringSingleTokenControlData
	{
		public ControlDataMatchType Type { get; set; }
		public string Value { get; set; }
		public bool IsCaseSensitive { get; set; }
		public string IfNoPropertyFound { get; set; }
		public string startIP { get; set; }
        public string endIP { get; set; }
	}
}