Import-Module .\VirtualDesktop.dll

Add-Type -AssemblyName PresentationFramework

# Define Windows API functions at the top level
Add-Type -MemberDefinition @'
[DllImport("user32.dll")]
public static extern bool SetWindowPos(IntPtr hWnd, IntPtr hWndInsertAfter, int X, int Y, int cx, int cy, uint uFlags);

[DllImport("user32.dll")]
public static extern int SetWindowLong(IntPtr hWnd, int nIndex, int dwNewLong);

[DllImport("user32.dll")]
public static extern int GetWindowLong(IntPtr hWnd, int nIndex);

[DllImport("user32.dll", SetLastError = true)]
public static extern IntPtr FindWindowEx(IntPtr hP, IntPtr hC, string sC, string sW);

[DllImport("user32.dll", CharSet = CharSet.Auto, SetLastError = true)]
public static extern bool EnumWindows(EnumedWindow lpEnumFunc, System.Collections.ArrayList lParam);

public delegate bool EnumedWindow(IntPtr handleWindow, System.Collections.ArrayList handles);

public static bool GetWindowHandle(IntPtr windowHandle, System.Collections.ArrayList windowHandles)
{
    windowHandles.Add(windowHandle);
    return true;
}
'@ -Name 'Win32Functions' -Namespace Win32Functions

# Constants for SetWindowLong
$GWL_EXSTYLE = -20
$WS_EX_TOOLWINDOW = 0x00000080
$WS_EX_NOACTIVATE = 0x08000000


# XAML for the right window and button
$xamlRight = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        Width="100" Height="60" WindowStyle="None" AllowsTransparency="True"
        Background="Transparent" Topmost="True" ShowInTaskbar="False" ResizeMode="NoResize"
        Opacity="0.5">
    <Grid>
        <Button Name="RightDesktopSwitchBtn" Content="&gt;&gt;&gt;"
                Background="Blue" Foreground="White"
                FontWeight="Bold" FontSize="16"
                HorizontalAlignment="Stretch" VerticalAlignment="Stretch"
                Margin="0" />
    </Grid>
</Window>
"@

# XAML for the left window and button
$xamlLeft = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        Width="100" Height="60" WindowStyle="None" AllowsTransparency="True"
        Background="Transparent" Topmost="True" ShowInTaskbar="False" ResizeMode="NoResize"
        Opacity="0.5">
    <Grid>
        <Button Name="LeftDesktopSwitchBtn" Content="&lt;&lt;&lt;"
                Background="Green" Foreground="White"
                FontWeight="Bold" FontSize="16"
                HorizontalAlignment="Stretch" VerticalAlignment="Stretch"
                Margin="0" />
    </Grid>
</Window>
"@

# Load XAML for right window
$readerRight = [System.Xml.XmlNodeReader]::new([xml]$xamlRight)
$windowRight = [Windows.Markup.XamlReader]::Load($readerRight)

# Load XAML for left window
$readerLeft = [System.Xml.XmlNodeReader]::new([xml]$xamlLeft)
$windowLeft = [Windows.Markup.XamlReader]::Load($readerLeft)

# Get screen dimensions
$screen = [System.Windows.SystemParameters]::PrimaryScreenWidth
$height = [System.Windows.SystemParameters]::PrimaryScreenHeight

# Set right window position (bottom right)
$windowRight.Left = $screen - $windowRight.Width - 20
$windowRight.Top = $height - $windowRight.Height - 60

# Set left window position (bottom left)
$windowLeft.Left = 20
$windowLeft.Top = $height - $windowLeft.Height - 60

# Right button click event
$buttonRight = $windowRight.FindName("RightDesktopSwitchBtn")
$buttonRight.Add_Click({
        [WindowsDesktop.VirtualDesktop]::GetDesktops().GetRight().Switch()
    })

# Left button click event
$buttonLeft = $windowLeft.FindName("LeftDesktopSwitchBtn")
$buttonLeft.Add_Click({
        $id = [WindowsDesktop.VirtualDesktop]::GetDesktops().GetLeft().Id.ToString()
        [WindowsDesktop.VirtualDesktop]::FromId($id).Switch()
    })


# Set up the window BEFORE showing it
$windowRight.add_SourceInitialized({
        $hwnd = (New-Object System.Windows.Interop.WindowInteropHelper $windowRight).Handle
        
        # Make window a tool window and no-activate (excludes from Alt+Tab)
        $exStyle = [Win32Functions.Win32Functions]::GetWindowLong($hwnd, $GWL_EXSTYLE)
        $null = [Win32Functions.Win32Functions]::SetWindowLong($hwnd, $GWL_EXSTYLE, $exStyle -bor $WS_EX_TOOLWINDOW -bor $WS_EX_NOACTIVATE)
    })

$windowLeft.add_SourceInitialized({
        $hwnd = (New-Object System.Windows.Interop.WindowInteropHelper $windowLeft).Handle
        
        # Make window a tool window and no-activate (excludes from Alt+Tab)
        $exStyle = [Win32Functions.Win32Functions]::GetWindowLong($hwnd, $GWL_EXSTYLE)
        $null = [Win32Functions.Win32Functions]::SetWindowLong($hwnd, $GWL_EXSTYLE, $exStyle -bor $WS_EX_TOOLWINDOW -bor $WS_EX_NOACTIVATE)
    })

# Show windows

$windowRight.Show()
$windowLeft.Show()

# Handle CTRL+C and script termination to properly close the windows
$cleanup = {
    if ($windowRight -and $windowRight.IsLoaded) {
        $windowRight.Close()
    }
    if ($windowLeft -and $windowLeft.IsLoaded) {
        $windowLeft.Close()
    }
    if ($app) {
        $app.Shutdown()
    }
}

# Handle window closed events
$windowRight.Add_Closed({
        & $cleanup
    })

$windowLeft.Add_Closed({
        & $cleanup
    })

# Add a try/finally block to ensure cleanup on any exit
try {
    # Keep the application running with a non-blocking dispatcher
    $dispatcher = [System.Windows.Threading.Dispatcher]::CurrentDispatcher
    while ($windowRight.IsLoaded -or $windowLeft.IsLoaded) {
        try {
            $dispatcher.Invoke([Action] {}, [System.Windows.Threading.DispatcherPriority]::Background)
        }
        catch{}
        Start-Sleep -Milliseconds 100
    }
}
finally {
    # Cleanup when script exits for any reason
    & $cleanup
}