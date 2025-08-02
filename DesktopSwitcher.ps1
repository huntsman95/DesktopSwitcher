[CmdletBinding()]
param (
    [Parameter()]
    [ValidateSet("Black","Blue","Green","Purple","Yellow","Orange")]
    [string]
    $LeftColor = "Blue"
    ,
    [Parameter()]
    [ValidateSet("Black", "Blue", "Green", "Purple", "Yellow", "Orange")]
    [string]
    $RightColor = "Blue"
)

Import-Module $PSScriptRoot\VirtualDesktop.dll

Add-Type -AssemblyName PresentationFramework

# Define Windows API functions (only what we actually use)
if (-not ([System.Management.Automation.PSTypeName]'Win32Functions.Win32Functions').Type) {
    Add-Type -MemberDefinition @'
[DllImport("user32.dll")]
public static extern int SetWindowLong(IntPtr hWnd, int nIndex, int dwNewLong);

[DllImport("user32.dll")]
public static extern int GetWindowLong(IntPtr hWnd, int nIndex);
'@ -Name 'Win32Functions' -Namespace Win32Functions
}

# Constants for SetWindowLong
$script:GWL_EXSTYLE = -20
$script:WS_EX_TOOLWINDOW = 0x00000080
$script:WS_EX_NOACTIVATE = 0x08000000

# Helper function to create window XAML
function New-DesktopSwitchWindow {
    param(
        [string]$ButtonName,
        [string]$Content,
        [string]$Color,
        [string]$CornerRadius
    )
    
    return @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Width="40" Height="100" WindowStyle="None" AllowsTransparency="True"
        Background="Transparent" Topmost="True" ShowInTaskbar="False" ResizeMode="NoResize"
        Opacity="0.5">
    <Grid>
        <Button Name="$ButtonName" Content="$Content"
                Background="$Color" Foreground="White"
                FontFamily="$PSScriptRoot\fonts\Font Awesome 7 Free-Solid-900.otf#Font Awesome 7 Free Solid"
                FontWeight="Bold" FontSize="16"
                HorizontalAlignment="Stretch" VerticalAlignment="Stretch"
                Margin="0">
            <Button.Style>
                <Style TargetType="Button">
                    <Setter Property="Template">
                        <Setter.Value>
                            <ControlTemplate TargetType="Button">
                                <Border Background="{TemplateBinding Background}"
                                        CornerRadius="$CornerRadius">
                                    <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                                </Border>
                            </ControlTemplate>
                        </Setter.Value>
                    </Setter>
                </Style>
            </Button.Style>
        </Button>
    </Grid>
</Window>
"@
}

# Helper function to configure window properties
function Set-WindowProperties {
    param(
        [System.Windows.Window]$Window,
        [scriptblock]$ClickAction
    )
    
    # Set up window style before showing
    $Window.add_SourceInitialized({
        param($sender, $e)
        try {
            $hwnd = (New-Object System.Windows.Interop.WindowInteropHelper($sender)).Handle
            if ($hwnd -ne [System.IntPtr]::Zero) {
                $exStyle = [Win32Functions.Win32Functions]::GetWindowLong($hwnd, $script:GWL_EXSTYLE)
                $null = [Win32Functions.Win32Functions]::SetWindowLong($hwnd, $script:GWL_EXSTYLE, $exStyle -bor $script:WS_EX_TOOLWINDOW -bor $script:WS_EX_NOACTIVATE)
            }
        }
        catch {
            Write-Warning "Failed to set window properties: $($_.Exception.Message)"
        }
    })
    
    # Add click event to button
    $button = $Window.FindName($Window.Tag)
    if ($button) {
        $button.Add_Click($ClickAction)
    }
}

# Create windows using the helper function
$xamlRight = New-DesktopSwitchWindow -ButtonName "RightDesktopSwitchBtn" -Content "&#xf0da;" -Color $RightColor -CornerRadius "20,0,0,20"
$xamlLeft = New-DesktopSwitchWindow -ButtonName "LeftDesktopSwitchBtn" -Content "&#xf0d9;" -Color $LeftColor -CornerRadius "0,20,20,0"

# Load XAML and create windows
$windowRight = [Windows.Markup.XamlReader]::Parse($xamlRight)
$windowLeft = [Windows.Markup.XamlReader]::Parse($xamlLeft)

# Store button names in window tags for helper function
$windowRight.Tag = "RightDesktopSwitchBtn"
$windowLeft.Tag = "LeftDesktopSwitchBtn"

# Get screen dimensions and position windows
$screen = [System.Windows.SystemParameters]::PrimaryScreenWidth
$height = [System.Windows.SystemParameters]::PrimaryScreenHeight

$windowRight.Left = $screen - $windowRight.Width
$windowRight.Top = ($height - $windowRight.Height) / 2
$windowLeft.Left = 0
$windowLeft.Top = ($height - $windowLeft.Height) / 2

# Configure window properties and event handlers
Set-WindowProperties -Window $windowRight -ClickAction { [WindowsDesktop.VirtualDesktop]::Current.GetRight().Switch() }
Set-WindowProperties -Window $windowLeft -ClickAction { [WindowsDesktop.VirtualDesktop]::Current.GetLeft().Switch() }

# Show windows
$windowRight.Show()
$windowLeft.Show()

# Cleanup function
$cleanup = {
    @($windowRight, $windowLeft) | Where-Object { $_ -and $_.IsLoaded } | ForEach-Object { $_.Close() }
}

# Handle window closed events
$windowRight.Add_Closed($cleanup)
$windowLeft.Add_Closed($cleanup)

# Keep the application running
try {
    $dispatcher = [System.Windows.Threading.Dispatcher]::CurrentDispatcher
    while ($windowRight.IsLoaded -or $windowLeft.IsLoaded) {
        try {
            $dispatcher.Invoke([Action] {}, [System.Windows.Threading.DispatcherPriority]::Background)
        }
        catch { }
        Start-Sleep -Milliseconds 100
    }
}
finally {
    & $cleanup
}