# Regenerate original Jax platform icons. Requires Windows PowerShell 5.1+.
# No fonts, network access or third-party image libraries are used.
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
$repo = Split-Path -Parent $PSScriptRoot
[xml]$svg = Get-Content -LiteralPath (Join-Path $repo 'assets/branding/jax_icon.svg') -Raw
$rect = $svg.DocumentElement.SelectSingleNode('*[local-name()="rect"]')
$mark = $svg.DocumentElement.SelectSingleNode('*[local-name()="path"]')
$background = [Drawing.ColorTranslator]::FromHtml($rect.fill)
$foreground = [Drawing.ColorTranslator]::FromHtml($mark.stroke)
$invariant = [Globalization.CultureInfo]::InvariantCulture
$stroke = [single]::Parse($mark.GetAttribute('stroke-width'), $invariant)
# Deliberately small SVG subset used by the source: M, H, V and cubic C.
$tokens = [regex]::Matches($mark.d, '[MHVC]|-?\d+(?:\.\d+)?')
$path = [Drawing.Drawing2D.GraphicsPath]::new()
$x = [single]0; $y = [single]0; $i = 0
while ($i -lt $tokens.Count) {
    $command = $tokens[$i++].Value
    switch ($command) {
        'M' { $x = [single]::Parse($tokens[$i++].Value,$invariant); $y = [single]::Parse($tokens[$i++].Value,$invariant); $path.StartFigure() }
        'H' { $nx = [single]::Parse($tokens[$i++].Value,$invariant); $path.AddLine($x,$y,$nx,$y); $x=$nx }
        'V' { $ny = [single]::Parse($tokens[$i++].Value,$invariant); $path.AddLine($x,$y,$x,$ny); $y=$ny }
        'C' {
            $n = @(); for ($j=0;$j -lt 6;$j++) { $n += [single]::Parse($tokens[$i++].Value,$invariant) }
            $path.AddBezier($x,$y,$n[0],$n[1],$n[2],$n[3],$n[4],$n[5]); $x=$n[4]; $y=$n[5]
        }
        default { throw 'Unsupported SVG path command.' }
    }
}
function Render-JaxIcon([int]$Size, [bool]$Round) {
    $factor = 4
    $large = [Drawing.Bitmap]::new($Size*$factor, $Size*$factor)
    $g = [Drawing.Graphics]::FromImage($large)
    $brush = [Drawing.SolidBrush]::new($background)
    $pen = [Drawing.Pen]::new($foreground,$stroke)
    $shape = [Drawing.Drawing2D.GraphicsPath]::new()
    try {
        $g.Clear([Drawing.Color]::Transparent)
        $g.SmoothingMode = [Drawing.Drawing2D.SmoothingMode]::AntiAlias
        $g.ScaleTransform($Size*$factor/108.0,$Size*$factor/108.0)
        if ($Round) { $g.FillEllipse($brush,0,0,108,108) }
        else {
            $radius=[single]::Parse($rect.rx,$invariant); $diameter=2*$radius
            $shape.AddArc(0,0,$diameter,$diameter,180,90)
            $shape.AddArc(108-$diameter,0,$diameter,$diameter,270,90)
            $shape.AddArc(108-$diameter,108-$diameter,$diameter,$diameter,0,90)
            $shape.AddArc(0,108-$diameter,$diameter,$diameter,90,90)
            $shape.CloseFigure(); $g.FillPath($brush,$shape)
        }
        $pen.StartCap=[Drawing.Drawing2D.LineCap]::Round
        $pen.EndCap=[Drawing.Drawing2D.LineCap]::Round
        $pen.LineJoin=[Drawing.Drawing2D.LineJoin]::Round
        $g.DrawPath($pen,$path)
        $small=[Drawing.Bitmap]::new($Size,$Size)
        $sg=[Drawing.Graphics]::FromImage($small)
        $stream=[IO.MemoryStream]::new()
        try {
            $sg.InterpolationMode=[Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
            $sg.PixelOffsetMode=[Drawing.Drawing2D.PixelOffsetMode]::HighQuality
            $sg.DrawImage($large,0,0,$Size,$Size)
            $small.Save($stream,[Drawing.Imaging.ImageFormat]::Png)
            return ,$stream.ToArray()
        } finally { $stream.Dispose(); $sg.Dispose(); $small.Dispose() }
    } finally { $shape.Dispose(); $pen.Dispose(); $brush.Dispose(); $g.Dispose(); $large.Dispose() }
}
$res = Join-Path $repo 'android/app/src/main/res'
try {
    foreach ($entry in @(@('mdpi',48),@('hdpi',72),@('xhdpi',96),@('xxhdpi',144),@('xxxhdpi',192))) {
        $dir=Join-Path $res ('mipmap-'+$entry[0]); [IO.Directory]::CreateDirectory($dir) | Out-Null
        [IO.File]::WriteAllBytes((Join-Path $dir 'ic_launcher.png'),(Render-JaxIcon $entry[1] $false))
        [IO.File]::WriteAllBytes((Join-Path $dir 'ic_launcher_round.png'),(Render-JaxIcon $entry[1] $true))
    }
    $sizes=@(16,24,32,48,64,128,256)
    $images=[Collections.Generic.List[byte[]]]::new()
    foreach ($size in $sizes) { $images.Add((Render-JaxIcon $size $false)) }
    $ico=[IO.MemoryStream]::new(); $writer=[IO.BinaryWriter]::new($ico)
    try {
        $writer.Write([uint16]0); $writer.Write([uint16]1); $writer.Write([uint16]$sizes.Count)
        $offset=6+16*$sizes.Count
        for ($k=0;$k -lt $sizes.Count;$k++) {
            $dimension=if ($sizes[$k] -eq 256) {0} else {$sizes[$k]}
            $writer.Write([byte]$dimension); $writer.Write([byte]$dimension)
            $writer.Write([byte]0); $writer.Write([byte]0)
            $writer.Write([uint16]1); $writer.Write([uint16]32)
            $writer.Write([uint32]$images[$k].Length); $writer.Write([uint32]$offset)
            $offset+=$images[$k].Length
        }
        foreach ($bytes in $images) { $writer.Write($bytes) }
        [IO.File]::WriteAllBytes((Join-Path $repo 'windows/runner/resources/app_icon.ico'),$ico.ToArray())
    } finally { $writer.Dispose(); $ico.Dispose() }
    $encoding=[Text.UTF8Encoding]::new($false)
    [IO.File]::WriteAllText((Join-Path $res 'values/jax_icon_colors.xml'), "<resources>`n    <color name=`"jax_icon_background`">$($rect.fill)</color>`n</resources>`n", $encoding)
    $vector="<vector xmlns:android=`"http://schemas.android.com/apk/res/android`" android:width=`"108dp`" android:height=`"108dp`" android:viewportWidth=`"108`" android:viewportHeight=`"108`">`n    <path android:pathData=`"$($mark.d)`" android:fillColor=`"#00000000`" android:strokeColor=`"$($mark.stroke)`" android:strokeWidth=`"$stroke`" android:strokeLineCap=`"round`" android:strokeLineJoin=`"round`"/>`n</vector>`n"
    [IO.File]::WriteAllText((Join-Path $res 'drawable/jax_icon_foreground.xml'),$vector,$encoding)
    foreach ($api in @(26,33)) {
        $dir=Join-Path $res "mipmap-anydpi-v$api"; [IO.Directory]::CreateDirectory($dir) | Out-Null
        $mono=if ($api -ge 33) { "    <monochrome android:drawable=`"@drawable/jax_icon_foreground`"/>`n" } else { '' }
        $adaptive="<adaptive-icon xmlns:android=`"http://schemas.android.com/apk/res/android`">`n    <background android:drawable=`"@color/jax_icon_background`"/>`n    <foreground android:drawable=`"@drawable/jax_icon_foreground`"/>`n${mono}</adaptive-icon>`n"
        foreach ($name in @('ic_launcher','ic_launcher_round')) { [IO.File]::WriteAllText((Join-Path $dir "$name.xml"),$adaptive,$encoding) }
    }
    Write-Output 'Generated Jax Android legacy/round/adaptive icons and Windows ICO (16-256).'
} finally { $path.Dispose() }
