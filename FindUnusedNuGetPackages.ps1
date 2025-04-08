param (
    # Path to the project directory to analyze
    [string]$projectPath = (Get-Location).Path,
    
    # Packages to exclude from the analysis (e.g. test packages, build tools)
    [string[]]$excludePackages = @(),
    
    # Show details of where packages are used
    [switch]$showUsageDetails
)

Write-Host "Analyzing NuGet package usage in $projectPath" -ForegroundColor Cyan

# Find all project files
$projectFiles = Get-ChildItem -Path $projectPath -Recurse -Include "*.csproj", "*.vbproj", "*.fsproj"

$allPackages = @{}
$projectPackageMap = @{}
$packageTypes = @{}

# Extract package references from project files
foreach ($projectFile in $projectFiles) {
    Write-Host "Processing project: $($projectFile.Name)" -ForegroundColor Yellow
    
    $projectContent = [xml](Get-Content $projectFile.FullName)
    $packageReferences = $projectContent.SelectNodes("//PackageReference") + 
                         $projectContent.SelectNodes("//*[local-name()='PackageReference']")
    
    $projectPackages = @{}
    
    foreach ($package in $packageReferences) {
        $packageId = $package.Include ?? $package.GetAttribute("Include")
        $packageVersion = $package.Version ?? $package.GetAttribute("Version")
        
        # Check if package has specific attributes indicating its purpose
        $isAnalyzer = $false
        $isDevelopmentDependency = $false
        $privateAssets = $package.PrivateAssets ?? $package.GetAttribute("PrivateAssets")
        
        if ($privateAssets -eq "all") {
            $packageTypes[$packageId] = "Development Dependency"
        }
        
        if (-not [string]::IsNullOrEmpty($packageId) -and -not $excludePackages.Contains($packageId)) {
            $projectPackages[$packageId] = $packageVersion
            $allPackages[$packageId] = $packageVersion
        }
    }
    
    $projectPackageMap[$projectFile.Name] = $projectPackages
    Write-Host "  Found $($projectPackages.Count) package references" -ForegroundColor Gray
}

# Get all code files (expanded list of file types)
$codeFiles = Get-ChildItem -Path $projectPath -Recurse -Include "*.cs", "*.vb", "*.fs", "*.xaml", "*.razor", 
                                                      "*.cshtml", "*.props", "*.targets", "*.json", "*.xml", 
                                                      "*.config", "*.resx", "*.settings" |
             Where-Object { -not $_.FullName.Contains('\obj\') -and -not $_.FullName.Contains('\bin\') }

Write-Host "Scanning $($codeFiles.Count) code files for package usage..." -ForegroundColor Yellow

$usedPackages = @{}
$usageEvidence = @{}

# List of common build/test packages that don't need direct references
$commonToolPackages = @(
    "Microsoft.NET.Test.Sdk", "xunit", "NUnit", "MSTest", "Moq", "Microsoft.CodeAnalysis",
    "StyleCop", "Microsoft.CodeCoverage", "Swashbuckle", "Microsoft.AspNetCore.TestHost",
    "Microsoft.AspNetCore.Mvc.Testing", "coverlet", "FxCop", "Microsoft.Extensions.Configuration",
    "Microsoft.SourceLink", "GitVersion", "ReportGenerator"
)

# Auto-exclude common packages that don't require direct code references
foreach ($package in $allPackages.Keys) {
    foreach ($toolPackage in $commonToolPackages) {
        if ($package -like "$toolPackage*") {
            $packageTypes[$package] = "Tool/Framework Package"
            break
        }
    }
}

# Find NuGet package references in using statements and code
foreach ($codeFile in $codeFiles) {
    $content = Get-Content $codeFile.FullName -Raw
    
    foreach ($package in $allPackages.Keys) {
        # Skip if we've already found this package in use
        if ($usedPackages.ContainsKey($package)) { continue }
        
        # Skip checking tool packages in code
        if ($packageTypes[$package] -eq "Tool/Framework Package") { 
            $usedPackages[$package] = $true
            $usageEvidence[$package] = @("Detected as tool/framework package")
            continue 
        }
        
        # Create more variations of the package name to search for
        $packageNameVariations = @()
        
        # Add the full package name
        $packageNameVariations += $package
        
        # Add the package name with dots escaped for regex
        $packageNameVariations += ($package -replace '\.','\.')
        
        # Extract potential namespace parts (more intelligently)
        $namespaceParts = $package -split '\.'
        
        # Main company/product namespace (usually first 1-2 parts)
        if ($namespaceParts.Count -ge 2) {
            $mainNamespace = $namespaceParts[0..1] -join '.'
            $packageNameVariations += $mainNamespace
        }
        
        # Add individual significant parts that might be used in the code
        foreach ($part in $namespaceParts) {
            if ($part.Length -gt 2 -and -not @("Core", "Common", "Extensions", "Utils", "Abstractions").Contains($part)) {
                $packageNameVariations += $part
            }
        }
        
        # Detect common package naming patterns
        if ($package -like "*Client") {
            $packageNameVariations += $package -replace "Client$", ""
        }
        
        if ($package -like "*Extensions*") {
            $packageNameVariations += "Extend", "Extension"
        }
        
        # Check for attribute usages (many packages provide attributes)
        if ($content -match "(?:\[|\<)(?:\w+\.)*($($packageNameVariations -join '|'))(?:Attribute)?\]") {
            $usedPackages[$package] = $true
            $usageEvidence[$package] = @("Found attribute usage in $($codeFile.Name)")
            continue
        }
        
        # Check for using statements with this package
        if ($content -match "using\s+(?:static\s+)?(?:\w+\.)*($($packageNameVariations -join '|'))[\.;]") {
            $usedPackages[$package] = $true
            $usageEvidence[$package] = @("Found using statement in $($codeFile.Name)")
            continue
        }
        
        # Check for standard usages
        foreach ($variation in $packageNameVariations) {
            if ($content -match $variation) {
                $usedPackages[$package] = $true
                $usageEvidence[$package] = @("Found reference in $($codeFile.Name)")
                break
            }
        }
    }
}

# Check .deps.json files for actual runtime dependencies
$depsFiles = Get-ChildItem -Path $projectPath -Recurse -Include "*.deps.json" -ErrorAction SilentlyContinue |
             Where-Object { -not $_.FullName.Contains('\obj\') }

foreach ($depsFile in $depsFiles) {
    try {
        $depsContent = Get-Content $depsFile.FullName | ConvertFrom-Json -ErrorAction SilentlyContinue
        if ($depsContent.libraries) {
            foreach ($lib in $depsContent.libraries.PSObject.Properties.Name) {
                $packageName = ($lib -split '/')[0]
                if ($allPackages.ContainsKey($packageName) -and -not $usedPackages.ContainsKey($packageName)) {
                    $usedPackages[$packageName] = $true
                    $usageEvidence[$packageName] = @("Referenced as runtime dependency in $($depsFile.Name)")
                }
            }
        }
    }
    catch {
        Write-Host "  Warning: Could not parse deps file $($depsFile.Name)" -ForegroundColor Yellow
    }
}

# Find unused packages
$unusedPackages = @{}
foreach ($package in $allPackages.Keys) {
    if (-not $usedPackages.ContainsKey($package)) {
        $unusedPackages[$package] = $allPackages[$package]
    }
}

# Generate the report
Write-Host "`nPackage Usage Report:" -ForegroundColor Green
Write-Host "Total packages referenced: $($allPackages.Count)" -ForegroundColor Cyan
Write-Host "Packages used in code: $($usedPackages.Count)" -ForegroundColor Cyan
Write-Host "Potentially unused packages: $($unusedPackages.Count)" -ForegroundColor Cyan

if ($showUsageDetails -and $usedPackages.Count -gt 0) {
    Write-Host "`nUsed Package Details:" -ForegroundColor Green
    foreach ($package in $usedPackages.Keys | Sort-Object) {
        Write-Host "  - $package ($($allPackages[$package]))" -ForegroundColor Green
        if ($usageEvidence.ContainsKey($package)) {
            foreach ($evidence in $usageEvidence[$package]) {
                Write-Host "      $evidence" -ForegroundColor Gray
            }
        }
    }
}

if ($unusedPackages.Count -gt 0) {
    Write-Host "`nPotentially Unused Packages:" -ForegroundColor Yellow
    foreach ($package in $unusedPackages.Keys | Sort-Object) {
        Write-Host "  - $package ($($unusedPackages[$package]))" -ForegroundColor Red
        
        # Show which projects reference this package
        foreach ($project in $projectPackageMap.Keys) {
            if ($projectPackageMap[$project].ContainsKey($package)) {
                Write-Host "      Referenced in: $project" -ForegroundColor Gray
            }
        }
    }
    
    Write-Host "`nNOTE: This analysis is based on pattern matching and may produce false positives." -ForegroundColor Yellow
    Write-Host "      Packages could be used indirectly, through reflection, or as build/analyzer tools." -ForegroundColor Yellow
    Write-Host "      Please verify before removing any packages." -ForegroundColor Yellow
    Write-Host "      Use -showUsageDetails to see where packages are used." -ForegroundColor Yellow
    Write-Host "      Use -excludePackages to exclude known tools from analysis." -ForegroundColor Yellow
}
else {
    Write-Host "`nAll NuGet packages appear to be used in the code." -ForegroundColor Green
}
