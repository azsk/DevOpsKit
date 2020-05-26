class AzHelper
{
static [void] UploadStorageBlobContent([string] $fileName, [string] $blobName, [string] $containerName, [object] $stgCtx)
	{
        Set-AzStorageBlobContent -Blob $blobName -Container $containerName -File $fileName -Context $stgCtx -Force | Out-Null
    }

    static [object] GetStorageBlobContent([string] $folderName, [string] $fileName, [string] $blobName, [string] $containerName, [object] $stgCtx)
	{
        $folderName = $folderName.TrimEnd("\")
        $folderName = $folderName.TrimEnd("/")
        $fileName = Join-Path $folderName $fileName
        return [AzHelper]::GetStorageBlobContent($fileName, $blobName, $containerName, $stgCtx)
    }

    static [object] GetStorageBlobContent([string] $fileName, [string] $blobName, [string] $containerName, [object] $stgCtx)
	{
        $result = Get-AzStorageBlobContent -Blob $blobName -Container $containerName -Destination $fileName -Context $stgCtx -Force 
        return $result
    }
}