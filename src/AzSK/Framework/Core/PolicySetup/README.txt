*** This file describes about organization policy folder created after installing organization policies using Install-AzSKOrganizationPolicy (IOP) command ***
--------------------------------------------------------------

All the files residing under following folders will be uploaded to organization policy storage account on next run of organization policy command.

	\Config				<-- Contains the configuration JSON files customized by organization.
	\CA-Runbook			<-- This contains the PowerShell script used by Continuous Assurance (CA) feature of AzSK. Modify with extreme caution.
--------------------------------------------------------------

Following folder/file will always get overridden every time organization policy command is run.

	\Config\ServerConfigMetadata.json		<-- Metadata file containing details about modified config JSON files.
	\Installer								<-- Contains organization specific installer file.
--------------------------------------------------------------
