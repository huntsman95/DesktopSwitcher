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
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

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
        param($sourceWindow, $e)
        try {
            $hwnd = (New-Object System.Windows.Interop.WindowInteropHelper($sourceWindow)).Handle
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

# Helper function to create system tray icon
function New-TrayIcon {
    param(
        [scriptblock]$ExitAction
    )
    
    # Create NotifyIcon
    $trayIcon = New-Object System.Windows.Forms.NotifyIcon
    $trayIcon.Icon = [System.Drawing.Icon]::ExtractAssociatedIcon("$PSScriptRoot\icons\icon.ico")
    $trayIcon.Text = "Desktop Switcher - Click buttons on screen edges to switch virtual desktops"
    $trayIcon.Visible = $true
    
    # Create context menu
    $contextMenu = New-Object System.Windows.Forms.ContextMenuStrip
    
    # Add Show/Hide Windows menu item
    $toggleMenuItem = New-Object System.Windows.Forms.ToolStripMenuItem
    $toggleMenuItem.Text = "Toggle Windows Visibility"
    $toggleMenuItem.Add_Click({
        if ($script:windowRight.Visibility -eq [System.Windows.Visibility]::Visible) {
            $script:windowRight.Hide()
            $script:windowLeft.Hide()
        } else {
            $script:windowRight.Show()
            $script:windowLeft.Show()
        }
    })
    $contextMenu.Items.Add($toggleMenuItem)
    
    # Add separator
    $contextMenu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))
    
    # Add Exit menu item
    $exitMenuItem = New-Object System.Windows.Forms.ToolStripMenuItem
    $exitMenuItem.Text = "Exit"
    $exitMenuItem.Add_Click($ExitAction)
    $contextMenu.Items.Add($exitMenuItem)
    
    # Assign context menu to tray icon
    $trayIcon.ContextMenuStrip = $contextMenu
    
    # Add double-click event to toggle windows
    $trayIcon.Add_DoubleClick({
        if ($script:windowRight.Visibility -eq [System.Windows.Visibility]::Visible) {
            $script:windowRight.Hide()
            $script:windowLeft.Hide()
        } else {
            $script:windowRight.Show()
            $script:windowLeft.Show()
        }
    })
    
    return $trayIcon
}

# Create windows using the helper function
$xamlRight = New-DesktopSwitchWindow -ButtonName "RightDesktopSwitchBtn" -Content "&#xf0da;" -Color $RightColor -CornerRadius "20,0,0,20"
$xamlLeft = New-DesktopSwitchWindow -ButtonName "LeftDesktopSwitchBtn" -Content "&#xf0d9;" -Color $LeftColor -CornerRadius "0,20,20,0"

# Load XAML and create windows
$script:windowRight = [Windows.Markup.XamlReader]::Parse($xamlRight)
$script:windowLeft = [Windows.Markup.XamlReader]::Parse($xamlLeft)

# Store button names in window tags for helper function
$script:windowRight.Tag = "RightDesktopSwitchBtn"
$script:windowLeft.Tag = "LeftDesktopSwitchBtn"

# Get screen dimensions and position windows
$screen = [System.Windows.SystemParameters]::PrimaryScreenWidth
$height = [System.Windows.SystemParameters]::PrimaryScreenHeight

$script:windowRight.Left = $screen - $script:windowRight.Width
$script:windowRight.Top = ($height - $script:windowRight.Height) / 2
$script:windowLeft.Left = 0
$script:windowLeft.Top = ($height - $script:windowLeft.Height) / 2

# Configure window properties and event handlers
Set-WindowProperties -Window $script:windowRight -ClickAction { [WindowsDesktop.VirtualDesktop]::Current.GetRight().Switch() }
Set-WindowProperties -Window $script:windowLeft -ClickAction { [WindowsDesktop.VirtualDesktop]::Current.GetLeft().Switch() }

# Show windows
$script:windowRight.Show()
$script:windowLeft.Show()

# Cleanup function
$cleanup = {
    @($script:windowRight, $script:windowLeft) | Where-Object { $_ -and $_.IsLoaded } | ForEach-Object { $_.Close() }
    if ($script:trayIcon) {
        $script:trayIcon.Visible = $false
        $script:trayIcon.Dispose()
    }
    [System.Windows.Forms.Application]::Exit()
}

# Create system tray icon
$script:trayIcon = New-TrayIcon -ExitAction $cleanup

# Handle window closed events
$script:windowRight.Add_Closed($cleanup)
$script:windowLeft.Add_Closed($cleanup)

# Keep the application running
try {
    $dispatcher = [System.Windows.Threading.Dispatcher]::CurrentDispatcher
    while ($script:windowRight.IsLoaded -or $script:windowLeft.IsLoaded) {
        try {
            # Process WPF events
            $dispatcher.Invoke([Action] {}, [System.Windows.Threading.DispatcherPriority]::Background)
            # Process Windows Forms events (for tray icon)
            [System.Windows.Forms.Application]::DoEvents()
        }
        catch { }
        Start-Sleep -Milliseconds 50
    }
}
finally {
    & $cleanup
}