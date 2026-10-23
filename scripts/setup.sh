#!/usr/bin/env bash
# Instala o Node.js localmente quando necessario, sem alterar o sistema.
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.."
project_dir="$PWD"
export PATH="$project_dir/.tools/node/bin:$PATH"

node_ok() {
  command -v node >/dev/null 2>&1 && command -v npm >/dev/null 2>&1 &&
    node -e 'const [major, minor] = process.versions.node.split(".").map(Number); process.exit(major >= 22 && (major !== 22 || minor >= 12) ? 0 : 1)'
}

download() {
  if command -v curl >/dev/null 2>&1; then
    curl --fail --location --silent --show-error "$1" -o "$2"
  elif command -v wget >/dev/null 2>&1; then
    wget -q "$1" -O "$2"
  else
    echo 'Instale curl ou wget pelo gerenciador de pacotes da sua distribuicao e execute novamente.' >&2
    exit 1
  fi
}

if ! node_ok; then
  [[ "$(uname -s)" == Linux ]] || { echo 'Este script de instalacao do Node suporta Linux.' >&2; exit 1; }
  case "$(uname -m)" in
    x86_64) arch=x64 ;;
    aarch64|arm64) arch=arm64 ;;
    *) echo 'Arquitetura sem instalacao automatica. Instale Node.js 22.12+ e npm e execute novamente.' >&2; exit 1 ;;
  esac
  for tool in tar xz sha256sum; do
    command -v "$tool" >/dev/null 2>&1 || { echo "Instale $tool pelo gerenciador de pacotes e execute novamente." >&2; exit 1; }
  done
  temp_dir="$(mktemp -d)"
  trap 'rm -rf -- "$temp_dir"' EXIT
  base_url=https://nodejs.org/dist/latest-v22.x
  echo 'Baixando Node.js 22 e npm do site oficial...'
  download "$base_url/SHASUMS256.txt" "$temp_dir/SHASUMS256.txt"
  archive="$(awk -v suffix="-linux-$arch.tar.xz" 'substr($2, length($2)-length(suffix)+1)==suffix {print $2; exit}' "$temp_dir/SHASUMS256.txt")"
  [[ -n "$archive" && "$archive" != */* ]] || { echo 'Arquivo do Node nao encontrado.' >&2; exit 1; }
  download "$base_url/$archive" "$temp_dir/$archive"
  (cd "$temp_dir"; awk -v file="$archive" '$2==file' SHASUMS256.txt | sha256sum --check --status)
  mkdir -p .tools/node
  tar -xJf "$temp_dir/$archive" -C .tools/node --strip-components=1
  hash -r
fi
node_ok || { echo 'Nao foi possivel configurar Node.js 22.12+ e npm.' >&2; exit 1; }
echo "Node $(node --version) / npm $(npm --version)"

# npm ls verifica tambem as dependencias de desenvolvimento usadas pelo Vite.
if ! npm ls --include=dev --all >/dev/null 2>&1 || [[ ! -x node_modules/.bin/vite || ! -x node_modules/.bin/tsc || ! -x node_modules/.bin/vitest ]] || [[ ! -f node_modules/.setup-lock.sha256 ]] || ! sha256sum --check --status node_modules/.setup-lock.sha256; then
  echo 'Instalando dependencias do projeto...'
  npm ci --include=dev
  sha256sum package-lock.json > node_modules/.setup-lock.sha256
else
  echo 'As dependencias do projeto ja estao instaladas.'
fi
printf '\nPreparacao concluida. Para iniciar neste terminal:\n'
printf 'cd %q\n' "$project_dir"
printf 'export PATH="%s/.tools/node/bin:$PATH"\n' "$project_dir"
printf 'npm run dev\nAbra o endereco informado pelo Vite (normalmente http://127.0.0.1:5173/).\n'
