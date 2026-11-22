$root = 'D:\opencode_workspace\wow-forever-addons\tools\holybulwark'
$listener = New-Object System.Net.Sockets.TcpListener([System.Net.IPAddress]::Loopback, 8765)
$listener.Start()
while ($true) {
    $client = $listener.AcceptTcpClient()
    try {
        $stream = $client.GetStream()
        $reader = New-Object System.IO.StreamReader($stream, [System.Text.Encoding]::ASCII)
        $line = $reader.ReadLine()
        while ($true) {
            $h = $reader.ReadLine()
            if ($null -eq $h -or $h -eq '') { break }
        }
        $path = '/'
        if ($line -match '^GET\s+(\S+)') { $path = $Matches[1] }
        $path = $path.Split('?')[0].TrimStart('/')
        if ($path -eq '') { $path = 'syntax-check.html' }
        $file = Join-Path $root $path
        if (Test-Path $file -PathType Leaf) {
            $bytes = [System.IO.File]::ReadAllBytes($file)
            $ext = [System.IO.Path]::GetExtension($file)
            $ct = 'application/octet-stream'
            if ($ext -eq '.html') { $ct = 'text/html; charset=utf-8' }
            elseif ($ext -eq '.js') { $ct = 'application/javascript; charset=utf-8' }
            $head = "HTTP/1.1 200 OK`r`nContent-Type: $ct`r`nContent-Length: $($bytes.Length)`r`nConnection: close`r`n`r`n"
            $hb = [System.Text.Encoding]::ASCII.GetBytes($head)
            $stream.Write($hb, 0, $hb.Length)
            $stream.Write($bytes, 0, $bytes.Length)
        } else {
            $body = [System.Text.Encoding]::UTF8.GetBytes('not found')
            $head = "HTTP/1.1 404 Not Found`r`nContent-Type: text/plain`r`nContent-Length: $($body.Length)`r`nConnection: close`r`n`r`n"
            $hb = [System.Text.Encoding]::ASCII.GetBytes($head)
            $stream.Write($hb, 0, $hb.Length)
            $stream.Write($body, 0, $body.Length)
        }
        $stream.Flush()
    } catch {
    } finally {
        $client.Close()
    }
}
