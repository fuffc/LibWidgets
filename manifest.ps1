# LibWidgets manifest generator -- lists this library's shippable files
# (relative to this folder) so a consuming addon's own packaging script can
# include exactly those files instead of a blind recursive copy of this
# folder. That distinction matters since this folder is a git submodule: a
# plain recursive copy would also sweep up version-control metadata and other
# files that don't belong in a shipped addon.
#
# This is NOT a load-time file list -- there is no single manifest file a
# consuming addon's .toc can reference once to pull in the whole library on
# this client, so each consumer's own .toc must list every one of this
# library's .lua files directly (today just LibWidgets.lua); growing this
# library to more files means every consumer's .toc needs a new line too.
# $luaFiles below is only this function's own record of which files exist,
# for packaging purposes.
#
# Meant to be dot-sourced (". manifest.ps1") by:
#   - a consuming addon's own packaging script
#   - a future standalone packaging script for this library on its own (not
#     needed today, so not written yet -- but this function is exactly what
#     it would call too)

function Get-LibWidgetsManifest {
    param([Parameter(Mandatory)][string]$LibRoot)

    $luaFiles = @("LibWidgets.lua")

    $textureFiles = @()
    $texDir = Join-Path $LibRoot "textures"
    if (Test-Path $texDir) {
        $textureFiles = Get-ChildItem -Path $texDir -File | ForEach-Object { Join-Path "textures" $_.Name }
    }

    $relPaths = $luaFiles + $textureFiles
    return $relPaths | ForEach-Object { Join-Path $LibRoot $_ }
}
