param (
    # Path to the project directory to analyze
    [string]$projectPath = (Get-Location).Path
)

Write-Host "Analyzing NuGet package usage in $projectPath" -ForegroundColor Cyan

# Find all project files
$projectFiles = Get-ChildItem -Path $projectPath -Recurse -Include "*.csproj", "*.vbproj", "*.fsproj"

$allPackages = @{}
$projectPackageMap = @{}

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
        
        if (-not [string]::IsNullOrEmpty($packageId)) {
            $projectPackages[$packageId] = $packageVersion
            $allPackages[$packageId] = $packageVersion
        }
    }
    
    $projectPackageMap[$projectFile.Name] = $projectPackages
    Write-Host "  Found $($projectPackages.Count) package references" -ForegroundColor Gray
}

# Get all code files
$codeFiles = Get-ChildItem -Path $projectPath -Recurse -Include "*.cs", "*.vb", "*.fs", "*.xaml", "*.razor" |
             Where-Object { -not $_.FullName.Contains('\obj\') -and -not $_.FullName.Contains('\bin\') }

Write-Host "Scanning $($codeFiles.Count) code files for package usage..." -ForegroundColor Yellow

$usedPackages = @{}

# Find NuGet package references in using statements and code
foreach ($codeFile in $codeFiles) {
    $content = Get-Content $codeFile.FullName -Raw
    
    foreach ($package in $allPackages.Keys) {
        # Create variations of the package name to search for
        $packageNameVariations = @(
            $package,
            ($package -replace '\.','\.')  # For regex matching
        )
        
        # Extract potential namespace parts
        $namespaceParts = $package -split '\.'
        foreach ($part in $namespaceParts) {
            if ($part.Length -gt 2 -and $part -ne "Core" -and $part -ne "Common") {
                $packageNameVariations += $part
            }
        }
        
        foreach ($variation in $packageNameVariations) {
            if ($content -match $variation) {
                $usedPackages[$package] = $true
                break
            }
        }
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
    
    Write-Host "`nNOTE: This analysis is based on string matching and may produce false positives." -ForegroundColor Yellow
    Write-Host "      Packages could be used indirectly or through reflection." -ForegroundColor Yellow
    Write-Host "      Please verify before removing any packages." -ForegroundColor Yellow
}
else {
    Write-Host "`nAll NuGet packages appear to be used in the code." -ForegroundColor Green
}
