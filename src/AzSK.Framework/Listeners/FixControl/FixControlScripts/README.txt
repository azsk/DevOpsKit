*** This file describes how to interpret the different files created when AzSK cmdlets are executed with 'GenerateFixScript' parameter ***
To implement the recommendations for controls,
	1. The user can review the PowerShell files under 'Services' folder.
	2. The user can update a parameters file (FixControlConfig.json) to provide input values for the fix script. This is required for controls where the fix/remediation requires input params to be supplied by the user (e.g., IP addresses, user alias, etc.).
	3. The user runs the script (RunFixScript.ps1) to remediate the relevant controls.
	4. (Optionally) The user can rerun the scan to confirm that the target controls were indeed remediated.
	
The contents of the 'FixControlScripts' folder are organized as under:

	\RunFixScript.ps1				<-- The file which starts implementing the recommendations. The file typically contains repair command which uses the files from current folder.

	\FixControlConfig.json				<-- The file contains the configuration of controls along with mandatory/optional parameters which are required for implementing the fix for control.

	\Services					<-- The folder contains the PowerShell files which are used to implement the fix for control.
		\<resourceType>.ps1			<-- The file contains PowerShell code to implement the fix for control. The file can be referred for review.
	
	\FixControlConfig-<Timestamp>.json		<-- This file is generated when repair command is run. The file contains the input values provided by user while running the repair command. The file can be referred for review.