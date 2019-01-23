Set-StrictMode -Version Latest

enum SuppressedExceptionType
{
	InvalidArgument
	NullArgument
	Generic
	InvalidOperation
}

class SuppressedException : System.Exception
{
	[SuppressedExceptionType] $ExceptionType = [SuppressedExceptionType]::InvalidArgument
    SuppressedException($message):
		Base($message)
	{ }

	SuppressedException($message, [SuppressedExceptionType] $exceptionType):
		Base($message)
	{
        $this.ExceptionType = $exceptionType;
    }

	[string] ConvertToString()
	{
		$result = "";
		if($this.ExceptionType -ne [SuppressedExceptionType]::Generic)
		{
			$result = $this.ExceptionType.ToString() + ": " ;
		}
		$result = $result + $this.Message;

		return $result;
	}
}
