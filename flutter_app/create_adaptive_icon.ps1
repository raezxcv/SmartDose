Add-Type -AssemblyName System.Drawing

$srcPath = "C:\Users\User\SmartDose\flutter_app\assets\Smart Dose App Logo.png"
$dstPath = "C:\Users\User\SmartDose\flutter_app\assets\adaptive_foreground.png"

$srcBmp = [System.Drawing.Bitmap]::FromFile($srcPath)

$canvasSize = 2000
$targetBmp = New-Object System.Drawing.Bitmap($canvasSize, $canvasSize)
$graphics = [System.Drawing.Graphics]::FromImage($targetBmp)

$graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
$graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
$graphics.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
$graphics.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality

$graphics.Clear([System.Drawing.Color]::Transparent)

# Scale down logo to 68% so it fits inside Android 72dp / 108dp safe zone
$logoSize = [int]($canvasSize * 0.68)
$offset = [int](($canvasSize - $logoSize) / 2)

$destRect = New-Object System.Drawing.Rectangle($offset, $offset, $logoSize, $logoSize)
$srcRect = New-Object System.Drawing.Rectangle(0, 0, $srcBmp.Width, $srcBmp.Height)

$graphics.DrawImage($srcBmp, $destRect, $srcRect, [System.Drawing.GraphicsUnit]::Pixel)

$targetBmp.Save($dstPath, [System.Drawing.Imaging.ImageFormat]::Png)

$graphics.Dispose()
$targetBmp.Dispose()
$srcBmp.Dispose()

Write-Host "Created adaptive_foreground.png successfully at $dstPath"
