namespace AzSK.ARMChecker.Lib
{
	public enum ControlDataMatchType
	{
		Allow,
		NotAllow,
		GreaterThan,
		LesserThan,
		Equals,
        GreaterThanOrEqual,
        LesserThanOrEqual,
        Contains,
        NotContains,
        All,
        StringNotMatched,
        Limit,
        PassIfPropertyNotFound,
        FailIfPropertyNotFound,
        VerifyIfPropertyNotFound,
        
    }
}