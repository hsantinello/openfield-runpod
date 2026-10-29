#!/bin/bash
# OpenField no RunPod: instala (no 1º boot) e liga ComfyUI + OpenField + portão com senha.
# Chamado pelo template "OpenField (auto)". Tudo fica no volume /workspace,
# então os boots seguintes só ligam o que já está instalado.
#
# Variáveis do template:
#   OPENFIELD_PASSWORD  senha do portão (8+ caracteres). Vazia = gera uma e mostra no log.
#   HF_TOKEN            token de leitura do Hugging Face, com a licença do LTX-2.5 aceita.
#   OPENFIELD_BUNDLES   pacotes de modelos (padrão: ltx25,qwen,edit,cutout,ltx-tools).
#   OPENFIELD_REF       commit/branch do OpenField (padrão: commit testado abaixo).

VOL=/workspace
OF=$VOL/.openfield-runpod
LOGS=$VOL/logs
NODE_VER=v22.21.0
OPENFIELD_REF="${OPENFIELD_REF:-64f5440254235e15b90ad7148ba23d33e57df903}"
BUNDLES="${OPENFIELD_BUNDLES:-ltx25,qwen,edit,cutout,ltx-tools}"
GATE_PORT=3170

export HOME=$VOL
mkdir -p "$OF" "$LOGS"
log() { printf '\n[openfield] %s\n' "$*"; }
up() { curl -fsS -o /dev/null --max-time 2 "$1"; }

# ----------------------------------------------------------------- senha ----
PASS_FILE=$OF/gate.pass
if [ "${#OPENFIELD_PASSWORD}" -ge 8 ]; then
  printf '%s' "$OPENFIELD_PASSWORD" > "$PASS_FILE"
elif [ ! -s "$PASS_FILE" ]; then
  tr -dc 'A-Za-z0-9' < /dev/urandom | head -c 12 > "$PASS_FILE"
  log "OPENFIELD_PASSWORD vazia ou curta. Senha gerada: $(cat "$PASS_FILE")"
else
  log "Usando a senha salva em $PASS_FILE: $(cat "$PASS_FILE")"
fi
chmod 600 "$PASS_FILE"

# --------------------------------------------------- portão (já no início) ----
# Liga antes de tudo para o link da porta responder com o andamento da instalação.
cat > "$OF/gate.js" <<'GATE'
// Portão com senha na frente do OpenField (que não tem login).
// 0.0.0.0:3170 -> 127.0.0.1:3161, reescrevendo Host/Origin para o OpenField aceitar.
const http = require('http'), net = require('net'), fs = require('fs'), crypto = require('crypto');
const PASS = fs.readFileSync(process.env.GATE_PASS_FILE, 'utf8').trim();
const LISTEN = Number(process.env.GATE_PORT || 3170);
const TARGET = { host: '127.0.0.1', port: Number(process.env.GATE_TARGET_PORT || 3161) };
const STATUS_FILE = process.env.GATE_STATUS_FILE;
const TOKEN = crypto.createHash('sha256').update('ofgate:' + PASS).digest('hex');
const sha = s => crypto.createHash('sha256').update(s).digest();

function auth(req) {
  if ((req.headers.cookie || '').split(/;\s*/).includes('ofgate=' + TOKEN)) return 'cookie';
  const h = req.headers.authorization || '';
  if (!h.startsWith('Basic ')) return null;
  const pass = Buffer.from(h.slice(6), 'base64').toString().split(':').slice(1).join(':');
  return crypto.timingSafeEqual(sha(pass), sha(PASS)) ? 'basic' : null;
}
function upstreamHeaders(h) {
  const out = { ...h, host: `${TARGET.host}:${TARGET.port}` };
  if (out.origin) out.origin = `http://${TARGET.host}:${TARGET.port}`;
  delete out.authorization;
  return out;
}
function statusPage(res, code) {
  let s = '';
  try { s = fs.readFileSync(STATUS_FILE, 'utf8'); } catch {}
  res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8', 'Refresh': '15' });
  res.end(`<!doctype html><meta charset="utf-8"><title>OpenField ligando</title>
<body style="font:16px system-ui;background:#111;color:#eee;padding:40px;max-width:720px;margin:auto">
<h2>OpenField ainda está ligando…</h2><p>Esta página atualiza sozinha a cada 15 s.</p>
<p>No primeiro boot ele instala tudo e baixa os modelos (dezenas de GB), o que pode levar de 20 a 40 minutos.</p>
<pre style="background:#222;padding:12px;white-space:pre-wrap">${(s || 'iniciando').replace(/[<&]/g, c => c === '<' ? '&lt;' : '&amp;')}</pre>
<small>(${code})</small></body>`);
}

const server = http.createServer((req, res) => {
  const how = auth(req);
  if (!how) {
    res.writeHead(401, { 'WWW-Authenticate': 'Basic realm="OpenField"', 'Content-Type': 'text/plain; charset=utf-8' });
    return res.end('Senha necessária.');
  }
  const up = http.request({ ...TARGET, method: req.method, path: req.url, headers: upstreamHeaders(req.headers) }, r => {
    const headers = { ...r.headers };
    if (how === 'basic') headers['set-cookie'] = [].concat(headers['set-cookie'] || [], `ofgate=${TOKEN}; Path=/; HttpOnly; SameSite=Lax; Max-Age=2592000`);
    res.writeHead(r.statusCode, headers);
    r.pipe(res);
  });
  up.on('error', e => {
    if (res.headersSent) return res.end();
    if (req.method === 'GET' && (req.headers.accept || '').includes('text/html')) return statusPage(res, e.code);
    res.writeHead(502, { 'Content-Type': 'text/plain; charset=utf-8' });
    res.end('OpenField ainda está ligando. (' + e.code + ')');
  });
  req.pipe(up);
});

// WebSocket (/live): repassa o handshake e depois só copia bytes.
server.on('upgrade', (req, sock, head) => {
  if (!auth(req)) return sock.end('HTTP/1.1 401 Unauthorized\r\n\r\n');
  const up = net.connect(TARGET.port, TARGET.host, () => {
    let s = `${req.method} ${req.url} HTTP/1.1\r\n`;
    for (const [k, v] of Object.entries(upstreamHeaders(req.headers)))
      for (const x of [].concat(v)) s += `${k}: ${x}\r\n`;
    up.write(s + '\r\n');
    if (head && head.length) up.write(head);
    up.pipe(sock); sock.pipe(up);
  });
  up.on('error', () => sock.destroy());
  sock.on('error', () => up.destroy());
});

server.requestTimeout = 0;
server.listen(LISTEN, '0.0.0.0', () => console.log(`Portão OpenField em 0.0.0.0:${LISTEN} -> ${TARGET.host}:${TARGET.port}`));
GATE

STATUS=$OF/status.txt
status() { log "$*"; printf '%s  %s\n' "$(date -u +%H:%M:%S)" "$*" >> "$STATUS"; }
: > "$STATUS"

# Node no volume (o disco do container é apagado a cada boot)
NODE_DIR=$OF/node
if [ ! -x "$NODE_DIR/bin/node" ]; then
  status "Baixando Node $NODE_VER"
  rm -rf "$NODE_DIR"; mkdir -p "$NODE_DIR"
  curl -fsSL "https://nodejs.org/dist/$NODE_VER/node-$NODE_VER-linux-x64.tar.xz" | tar -xJ -C "$NODE_DIR" --strip-components=1
fi
export PATH="$NODE_DIR/bin:$PATH"

pkill -f "$OF/gate.js" 2>/dev/null
GATE_PASS_FILE=$PASS_FILE GATE_PORT=$GATE_PORT GATE_STATUS_FILE=$STATUS \
  nohup node "$OF/gate.js" >> "$LOGS/gate.log" 2>&1 &
if [ -n "$RUNPOD_POD_ID" ]; then
  log "Link: https://${RUNPOD_POD_ID}-${GATE_PORT}.proxy.runpod.net  (usuário: qualquer um; senha: a do OPENFIELD_PASSWORD)"
fi

# --------------------------------------------------------------- sistema ----
if ! command -v ffmpeg >/dev/null || ! command -v ffprobe >/dev/null; then
  status "Instalando ffmpeg"
  apt-get update -qq && DEBIAN_FRONTEND=noninteractive apt-get install -y -qq ffmpeg libgl1 libglib2.0-0 python3-venv >/dev/null
fi

# ------------------------------------------------------------- OpenField ----
cd "$VOL"
if [ ! -d "$VOL/openfield/.git" ]; then
  status "Baixando o OpenField"
  git clone https://github.com/wexloops/openfield.git "$VOL/openfield"
fi
cd "$VOL/openfield"
if [ "$(git rev-parse HEAD)" != "$(git rev-parse "$OPENFIELD_REF^{commit}" 2>/dev/null)" ]; then
  git fetch -q origin && git checkout -q "$OPENFIELD_REF" && rm -f "$OF/installed"
fi

# HF_TOKEN do template vai para o .env (o install.sh não sobrescreve um que já exista)
if [ -n "$HF_TOKEN" ] && [ -f .env ]; then
  grep -v '^HF_TOKEN=' .env > .env.tmp && echo "HF_TOKEN=$HF_TOKEN" >> .env.tmp && cat .env.tmp > .env && rm -f .env.tmp
fi

# Instalador oficial, sem perguntas (ComfyUI em /workspace/ComfyUI, nodes, proxy, .env, npm ci).
# Só roda no 1º boot ou depois de trocar de versão; é seguro repetir.
if [ ! -f "$OF/installed" ]; then
  status "Instalando ComfyUI, PyTorch e dependências (só no 1º boot, ~10 min)"
  if bash scripts/install.sh --yes < /dev/null; then
    touch "$OF/installed"
    rm -rf dist
  else
    status "O instalador falhou. Veja o log do pod; o próximo boot tenta de novo."
  fi
  pkill -f "ComfyUI/main.py" 2>/dev/null; sleep 2
fi

# Modelos: retomável, pula o que já baixou
if [ "${OPENFIELD_SKIP_DOWNLOAD:-0}" != "1" ]; then
  status "Conferindo/baixando modelos: $BUNDLES (1º boot: dezenas de GB)"
  [ -n "$HF_TOKEN" ] || grep -q '^HF_TOKEN=.' .env 2>/dev/null || status "Sem HF_TOKEN: os modelos do LTX (vídeo) vão falhar."
  npm run -s models -- --only "$BUNDLES" || status "Alguns downloads falharam. Reinicie o pod para retomar."
fi

[ -d dist ] || { status "Compilando o OpenField"; npm run build; }

# --------------------------------------------------------------- ComfyUI ----
if ! up http://127.0.0.1:8188/system_stats; then
  status "Ligando o ComfyUI"
  CL=$(grep -m1 '^COMFY_LAUNCH=' .env | cut -d= -f2- | sed 's/^["'\'']//;s/["'\'']$//')
  [ -n "$CL" ] || CL="$VOL/ComfyUI/venv/bin/python $VOL/ComfyUI/main.py --listen 127.0.0.1 --port 8188 --preview-method auto"
  (cd "$VOL/ComfyUI" && nohup bash -c "$CL" >> "$LOGS/comfyui.log" 2>&1 &)
  for _ in $(seq 1 300); do up http://127.0.0.1:8188/system_stats && break; sleep 2; done
fi

# ------------------------------------------------------------- OpenField ----
if ! up http://127.0.0.1:3161; then
  status "Ligando o OpenField"
  npm run -s doctor || true
  OPENFIELD_HOST=127.0.0.1 nohup npm start >> "$LOGS/openfield.log" 2>&1 &
fi
status "Pronto. Se esta página não sumir em 1 minuto, recarregue."
