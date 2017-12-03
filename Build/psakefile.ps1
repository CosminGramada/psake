Include ".\helpers.ps1"

Properties {
	#Solution and output directories
	$solutionDirectory = (Get-Item $solutionFile).DirectoryName
	$outputDirectory = "$solutionDirectory\.build"
	$tempOutputDirectory = "$solutionDirectory\temp"

	#Test results
	$testResultsDirectory = "$outputDirectory\TestResults"

	$packagesPath = "$solutionDirectory\packages"
	$NUnitExe = ((Get-ChildItem ($packagesPath + "\Nunit.ConsoleRunner*")).FullName | Sort-Object $_ | select -Last 1) + "\Tools\nunit3-console.exe"

	$openCoverExe = ((Get-ChildItem ($packagesPath + "\OpenCover*")).FullName | Sort-Object $_ | select -Last 1) + "\Tools\opencover.console.exe"
	$reportGeneratorExe = ((Get-ChildItem ($packagesPath + "\ReportGenerator*")).FullName | Sort-Object $_ | select -Last 1) + "\Tools\reportgenerator.exe"

	#MSBuild parameters
	$buildConfiguration = "Release"
	$buildPlatform = "Any CPU"
}

FormatTaskName "`r`n`r`n`r`n========== Executing {0} Task =========="

task default -depends CodeCoverage

task Init `
			-description "Initializes the build by removing previous artifacts and creating output directories" `
			-requiredVariables outputDirectory, tempOutputDirectory	`
{
	Assert -conditionToCheck ("Debug", "Release" -contains $buildConfiguration) `
			-failureMessage "Invalid build configuration '$buildConfiguration'. Valid values are 'Debug' or 'Release'."
	Assert -conditionToCheck ("x86", "x64", "Any CPU" -contains $buildPlatform) `
			-failureMessage "Invalid build platform '$buildPlatform'. Valid values are 'x86', 'x64', or 'Any CPU'"

	#remove previous build results
	if(Test-Path $outputDirectory)
	{
		Write-Host "Removing output directory located at $outputDirectory"
		Remove-Item $outputDirectory -Force -Recurse
	}
	if(Test-Path $tempOutputDirectory)
	{
		Write-Host "Removing temporary output directory located at $tempOutputDirectory"
		Remove-Item $tempOutputDirectory -Force -Recurse
	}

	Write-Host "Creating output directory located at $outputDirectory"
	New-Item $outputDirectory -ItemType Directory | Out-Null

	Write-Host "Creating temporary output directory located at $tempOutputDirectory"
	New-Item $tempOutputDirectory -ItemType Directory | Out-Null
}

#Restore and Build solution
task Compile `
			-depends Init `
			-description "Compile the code" `
			-requiredVariables solutionFile, buildConfiguration, buildPlatform, tempOutputDirectory `
{
	Write-Host "Performing dotnet restore"
	Exec {
		dotnet restore $solutionFile
	}

	Write-Host "Performing nuget restore"
	Exec {
		nuget restore $solutionDirectory
	}

	Write-Host "Building the solution"
	Exec {
		& "C:\BuildTools\MSBuild\15.0\Bin\msbuild.exe" $solutionFile `
		#& msbuild $solutionFile `
			"/p:Configuration=$buildConfiguration;Platform=$buildPlatform;OutDir=$tempOutputDirectory"
	}
	
}

#Run tests
task Test `
			-depends Compile `
			-description "Run unit tests" `
			-continueOnError
{
	#Create the test results directory if needed
	if (!(Test-Path $testResultsDirectory))
	{
		Write-Host "Creating test results directory located at $testResultsDirectory"
		mkdir $testResultsDirectory | Out-Null
	}

	Write-Host $testResultsDirectory

	$dll = "$solutionDirectory\WebApp.Tests\bin\Debug\WebApp.Tests.dll"

	$testCoverageReportPath = "$testResultsDirectory\OpenCover.xml"

	Exec {
		&$openCoverExe -target:$NUnitExe `
						-output:"$testCoverageReportPath" `
						-register:user `
						-filter:"+[*]* -[*.Tests]*" `
						-excludebyattribute:"System.Diagnostics.CodeAnalysis.ExcludeFromCodeCoverageAttribute" `
						-excludebyfile:"*\*Designer.cs;*\*.g.cs;*\*.g.i.cs" `
						-skipautoprops `
						-mergebyhash `
						-mergeoutput `
						-hideskipped:All `
						-returntargetcode `
						-targetargs:"$dll --work=$testResultsDirectory" `
	} -ErrorAction SilentlyContinue
}

task CodeCoverage `
				-depends Test, Compile `
				-description "Collect code coverage" `
				-requiredVariables testResultsDirectory `
{
	$htmlReport = "$testResultsDirectory\Html"

	if (!(Test-Path $htmlReport))
	{
		Write-Host "Creating test results directory located at $htmlReport"
		mkdir $htmlReport | Out-Null
	}

	$coverage = [xml](Get-Content -Path $testCoverageReportPath)

	$coverageSummary = $coverage.CoverageSession.Summary

	# Write class coverage
	Write-Host "##teamcity[buildStatisticValue key='CodeCoverageAbsCCovered' value='$($coverageSummary.visitedClasses)']"
	Write-Host "##teamcity[buildStatisticValue key='CodeCoverageAbsCTotal' value='$($coverageSummary.numClasses)']"
	Write-Host ("##teamcity[buildStatisticValue key='CodeCoverageC' value='{0:N2}']" -f (($coverageSummary.visitedClasses / $coverageSummary.numClasses)*100))

	# Report method coverage
	Write-Host "##teamcity[buildStatisticValue key='CodeCoverageAbsMCovered' value='$($coverageSummary.visitedMethods)']"
	Write-Host "##teamcity[buildStatisticValue key='CodeCoverageAbsMTotal' value='$($coverageSummary.numMethods)']"
	Write-Host ("##teamcity[buildStatisticValue key='CodeCoverageM' value='{0:N2}']" -f (($coverageSummary.visitedMethods / $coverageSummary.numMethods)*100))

	# Report branch coverage
	Write-Host "##teamcity[buildStatisticValue key='CodeCoverageAbsBCovered' value='$($coverageSummary.visitedBranchPoints)']"
	Write-Host "##teamcity[buildStatisticValue key='CodeCoverageAbsBTotal' value='$($coverageSummary.numBranchPoints)']"
	Write-Host ("##teamcity[buildStatisticValue key='CodeCoverageB' value='{0:N2}']" -f (($coverageSummary.visitedBranchPoints / $coverageSummary.numBranchPoints)*100))

	# Report Statement coverage
	Write-Host "##teamcity[buildStatisticValue key='CodeCoverageAbsSCovered' value='$($coverageSummary.visitedSequencePoints)']"
	Write-Host "##teamcity[buildStatisticValue key='CodeCoverageAbsSTotal' value='$($coverageSummary.numSequencePoints)']"
	Write-Host ("##teamcity[buildStatisticValue key='CodeCoverageS' value='{0:N2}']" -f (($coverageSummary.visitedSequencePoints / $coverageSummary.numSequencePoints)*100))

	Exec {
		&$reportGeneratorExe -reports:"$testResultsDirectory\OpenCover.xml" -targetdir:"$htmlReport" 
	} 
}