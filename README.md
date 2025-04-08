# Find Unused NuGet Packages Script

This PowerShell script analyzes C#, VB.NET, and F# projects to identify potentially unused NuGet package references.

## Purpose

The script helps maintain cleaner projects by identifying NuGet packages that might not be directly used in the code. This can help reduce project bloat and potential security vulnerabilities from unnecessary dependencies.

## Usage

```powershell
.\FindUnusedNuGetPackages.ps1 [-projectPath <path>]
```

### Parameters

- `projectPath`: Optional. The path to the project directory to analyze. Defaults to the current directory.

## How It Works

1. Scans for project files (*.csproj, *.vbproj, *.fsproj)
2. Extracts NuGet package references from each project
3. Searches through code files (*.cs, *.vb, *.fs, *.xaml, *.razor)
4. Identifies packages that don't appear to be referenced in code

## Output

The script provides:
- Total count of referenced packages
- Number of packages found in use
- List of potentially unused packages with:
  - Package name and version
  - Projects that reference each unused package

## Example Output

```
Package Usage Report:
Total packages referenced: 50
Packages used in code: 45
Potentially unused packages: 5

Potentially Unused Packages:
  - Newtonsoft.Json (13.0.1)
      Referenced in: Project1.csproj
  - Microsoft.Extensions.Logging (6.0.0)
      Referenced in: Project2.csproj
```

## Important Notes

⚠️ The analysis has some limitations:
- Based on string matching
- May produce false positives
- Cannot detect indirect usage through reflection
- Cannot detect transitive dependencies
- Always verify before removing any packages

## Best Practices

1. Run the script periodically during maintenance
2. Review each flagged package carefully
3. Test thoroughly after removing any packages
4. Consider keeping packages that are:
   - Used indirectly
   - Required by other packages
   - Used only in specific configurations
