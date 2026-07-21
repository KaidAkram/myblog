<#
.SYNOPSIS
    Creates a new blog post with Vagabond frontmatter for 0xAkr4m's blog.

.DESCRIPTION
    Generates a new blog post folder with index.md containing pre-filled
    frontmatter and a random Vagabond header image. Just drop your content
    below the frontmatter and push.

.PARAMETER Slug
    URL-friendly name for the post (e.g., "responder-htb", "ai-jailbreak-research")

.PARAMETER Title
    The display title of the post

.PARAMETER Tags
    Comma-separated tags (e.g., "htb,windows,ntlm")

.PARAMETER Description
    One-liner description for SEO and post cards

.PARAMETER HeaderNum
    Specific Vagabond header image number (1-6). Random if not specified.

.EXAMPLE
    .\new-post.ps1 -Slug "responder-htb" -Title "Responder — HTB Walkthrough" -Tags "htb,windows" -Description "LFI to admin shell in 5 steps"
#>

param(
    [Parameter(Mandatory=$true)]
    [string]$Slug,

    [Parameter(Mandatory=$true)]
    [string]$Title,

    [string]$Tags = "",

    [string]$Description = "A new post by 0xAkr4m",

    [int]$HeaderNum = 0
)

# Pick a random Vagabond header if not specified
if ($HeaderNum -eq 0) {
    $HeaderNum = Get-Random -Minimum 1 -Maximum 7
}

$headerImage = "../images/headers/vagabond-0$HeaderNum.png"

# Format tags
$tagsArray = if ($Tags -ne "") {
    ($Tags -split "," | ForEach-Object { """$($_.Trim())""" }) -join ", "
} else {
    """writeup"""
}

# Get today's date
$today = Get-Date -Format "yyyy-MM-dd"

# Create the post directory
$postDir = "src/content/blog/$Slug"
New-Item -ItemType Directory -Force -Path $postDir | Out-Null

# Generate the frontmatter
$content = @"
---
title: "$Title"
description: "$Description"
date: $today
tags: [$tagsArray]
authors: ["0xakr4m"]
image: $headerImage
draft: false
---

> "Perceive that which cannot be seen with the eye." — Miyamoto Musashi

<!-- Drop your README.md content below this line -->


"@

$filePath = "$postDir/index.md"
Set-Content -Path $filePath -Value $content -Encoding UTF8

Write-Host ""
Write-Host "  ⚔️  New post created!" -ForegroundColor Red
Write-Host ""
Write-Host "  📁 Path:   $filePath" -ForegroundColor DarkGray
Write-Host "  🎨 Header: vagabond-0$HeaderNum.png" -ForegroundColor DarkGray
Write-Host "  📅 Date:   $today" -ForegroundColor DarkGray
Write-Host "  🏷️  Tags:   $Tags" -ForegroundColor DarkGray
Write-Host ""
Write-Host "  Next steps:" -ForegroundColor Yellow
Write-Host "  1. Paste your writeup content into: $filePath" -ForegroundColor DarkGray
Write-Host "  2. Run 'npm run dev' to preview" -ForegroundColor DarkGray
Write-Host "  3. git add, commit, push → auto-deploys via GitHub Actions" -ForegroundColor DarkGray
Write-Host ""
