#
# Module manifest for module 'WindowsSettings'
#
@{
    # Script module or binary module file associated with this manifest.
    RootModule = 'WindowsSettings.psm1'

    # Version number of this module.
    ModuleVersion = '2.0.0'

    # Supported PSEditions
    CompatiblePSEditions = @('Core')

    # ID used to uniquely identify this module
    GUID = 'a84e9c7d-3d44-469a-9e12-88fb40d1283c'

    # Author of this module
    Author = 'Brian Bechtel'

    # Description of the functionality provided by this module
    Description = 'Modern Windows Developer Workstation Shell Module (Oh My Posh, Git, eza, zoxide, uutils, completions)'

    # Minimum version of the PowerShell engine required by this module
    PowerShellVersion = '7.0'

    # Functions to export from this module, for best performance, do not use wildcards
    FunctionsToExport = @(
        'gco', 'gcb', 'gcm', 'gcd', 'ga', 'gaa', 'gst', 'gss', 'gd', 'gds',
        'gl', 'gp', 'gb', 'gba', 'gbd', 'gbD', 'gsta', 'gstp', 'gstl',
        'glog', 'glo', 'grb', 'grba', 'grbc', 'grbi', 'grh', 'grhh',
        'gsw', 'gswc', 'gcp', 'gcpa', 'gcpc', 'gcommit', 'gamend',
        'gfetch', 'gpush', 'gpushf', 'gpull', 'gup', 'gprune', 'guser-branch',
        'fix-abcxyz-branch-name', 'gsync',
        'go-testall', 'go-buildall', 'go-lint', 'yaml-lint',
        'go_testall', 'go_buildall', 'go_lint', 'yaml_lint',
        'ls', 'll', 'la', 'lt', 'Format-PathTree', 'fs',
        'gen-passwd', 'repeat-until-success', 'sum'
    )

    # Cmdlets to export from this module
    CmdletsToExport = @()

    # Variables to export from this module
    VariablesToExport = @('LS_COLORS', 'STARSHIP_CONFIG')

    # Aliases to export from this module
    AliasesToExport = @('tf', 'vi')
}
