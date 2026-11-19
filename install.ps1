# Liga a pasta do projeto a pasta de addons do WoW Forever, via junction.
$addons = 'C:\Program Files (x86)\World of Warcraft\_forever_\Interface\AddOns'
$link = Join-Path $addons 'Qolly'

New-Item -ItemType Directory -Force -Path $addons | Out-Null

# Junction antiga de quando o addon se chamava Snipe. "rmdir" de junction apaga so o
# link, nunca os arquivos do projeto.
$old = Get-Item -LiteralPath (Join-Path $addons 'Snipe') -Force -ErrorAction SilentlyContinue
if ($old -and $old.LinkType -eq 'Junction' -and $old.Target -contains $PSScriptRoot) {
    cmd /c rmdir "`"$($old.FullName)`""
    Write-Output "Removida a junction antiga: $($old.FullName)"
}

$existing = Get-Item -LiteralPath $link -Force -ErrorAction SilentlyContinue
if ($existing) {
    if ($existing.LinkType -eq 'Junction' -and $existing.Target -contains $PSScriptRoot) {
        Write-Output "Ja instalado: $link"
        exit 0
    }
    Write-Error "$link ja existe e nao aponta para este projeto. Nada foi alterado."
    exit 1
}

New-Item -ItemType Junction -Path $link -Target $PSScriptRoot | Out-Null
Write-Output "Instalado: $link -> $PSScriptRoot"
