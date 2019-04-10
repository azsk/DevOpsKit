﻿namespace AzSK.ARMChecker.Lib
{
	public enum ControlMatchType
	{
		Null, // Single Token
		Boolean, // Single Token
		IntegerValue, // Single Token
		ItemCount, // Multi Tokens
        ItemProperties, //Multi Tokens
		StringLength, // Single Token
		StringWhitespace, // Single Token
		StringSingleToken, // Single Token
		StringMultiToken, // Multi Tokens
		RegExpressionSingleToken, // Single Token
		RegExpressionMultiToken, // Multi Tokens
		VerifiableSingleToken, // Single Tokens
		VerifiableMultiToken, // Multi Tokens
		Custom, // Multi Tokens
        NullableSingleToken, //Single Tokens


    }
}