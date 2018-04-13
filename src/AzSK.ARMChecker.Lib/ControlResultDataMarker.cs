namespace AzSK.ARMChecker.Lib
{

	public class ControlResultDataMarker
	{
		public int LineNumber { get; set; }
		public string JsonPath { get; set; }
		public string DataMarker { get; set; }

		public ControlResultDataMarker()
		{

		}

		public ControlResultDataMarker(int lineNumber, string jsonPath, string dataMarker)
		{
			LineNumber = lineNumber;
			JsonPath = jsonPath;
			DataMarker = dataMarker;
		}
	}
}