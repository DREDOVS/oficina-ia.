#!/usr/bin/env bash
# Respaldo cifrado de Oficina IA en un repositorio privado.
# Ejecutar desde el Codespace que contiene el TAR original.
set -Eeuo pipefail
umask 077

SOURCE="/workspaces/respaldos-oficina-ia/oficina-ia-20261113T213243Z.tar.gz"
EXPECTED_SHA="045ace922fc0a7176aca06d19821ded8f3dfef4a9e6f3f5b131c2a53726ae097"
TARGET="DREDOVS/oficina-ia-respaldos"
BACKUP_DIR="/workspaces/respaldos-oficina-ia"

for cmd in gh git openssl tar sha256sum awk mktemp date; do
  command -v "$cmd" >/dev/null || { echo "Falta $cmd" >&2; exit 1; }
done
[[ -s "$SOURCE" ]] || { echo "Falta el archivo $SOURCE" >&2; exit 1; }
[[ "$(sha256sum "$SOURCE" | awk '{print $1}')" == "$EXPECTED_SHA" ]] || {
  echo "SHA-256 original incorrecto. No se subira nada." >&2; exit 1;
}

entries=$(tar -tzf "$SOURCE")
for entry in "/dolt-native/" "/codex-sesiones.tar.gz" "/ramas-git.bundle"; do
  grep -Fq "$entry" <<< "$entries" || { echo "Respaldo incompleto: $entry" >&2; exit 1; }
done

gh auth status >/dev/null
login=$(gh api user --jq .login)
[[ "${login,,}" == "dredovs" ]] || {
  echo "GitHub CLI conectado como $login, no DREDOVS. No se subira nada." >&2; exit 1;
}

if gh repo view "$TARGET" --json visibility --jq .visibility >/dev/null 2>&1; then
  visibility=$(gh repo view "$TARGET" --json visibility --jq .visibility)
  [[ "$visibility" == PRIVATE ]] || { echo "El repositorio existente es publico: $TARGET" >&2; exit 1; }
else
  gh repo create "$TARGET" --private --description "Respaldo cifrado Gas City y Beads"
  visibility=$(gh repo view "$TARGET" --json visibility --jq .visibility)
  [[ "$visibility" == PRIVATE ]] || { echo "No se pudo confirmar privacidad. Abortado." >&2; exit 1; }
fi

stamp=$(date -u +%Y%m%dT%H%M%SZ)
branch="respaldo-$stamp"
keyfile="$BACKUP_DIR/CLAVE-PRIVADA-oficina-ia-$stamp.txt"
[[ ! -e "$keyfile" ]] || { echo "La clave ya existe: $keyfile" >&2; exit 1; }
temp=$(mktemp -d)
trap 'rm -rf -- "$temp"' EXIT
openssl rand -hex 32 > "$keyfile"
chmod 600 "$keyfile"
encrypted="$(basename "$SOURCE").enc"
openssl enc -aes-256-cbc -pbkdf2 -iter 600000 -salt \
  -in "$SOURCE" -out "$temp/$encrypted" -pass "file:$keyfile"

# Verificar que puede descifrarse y que los bytes coinciden con el original.
decoded_hash=$(openssl enc -d -aes-256-cbc -pbkdf2 -iter 600000 \
  -in "$temp/$encrypted" -pass "file:$keyfile" | sha256sum | awk '{print $1}')
[[ "$decoded_hash" == "$EXPECTED_SHA" ]] || { echo "Error de verificacion de cifrado" >&2; exit 1; }

cat > "$temp/README.md" <<EOF
# Oficina IA — respaldo cifrado
Fecha UTC: $stamp.

**Mantener este repositorio PRIVADO.**

Archivo: `$encrypted`.
SHA-256 antes de cifrar: `$EXPECTED_SHA`.
SHA-256 cifrado: `$(sha256sum "$temp/$encrypted" | awk '{print $1}')`.

Cifrado: OpenSSL AES-256-CBC, PBKDF2, 600000 iteraciones, salt.
La clave se guarda SOLO en el Codespace, en:
`$keyfile`
Debe descargarse a un lugar seguro **por separado**. No subirla a GitHub.

Restaurar el TAR original:
```bash
openssl enc -d -aes-256-cbc -pbkdf2 -iter 600000 -in "$encrypted" -out "$(basename "$SOURCE")" -pass file:CLAVE-PRIVADA.txt
sha256sum "$(basename "$SOURCE")"
```
EOF

cd "$temp"
git init -q -b "$branch"
git add README.md "$encrypted"
git -c user.name="Oficina IA Backup" -c user.email="backup@users.noreply.github.com" commit -q -m "Respaldo cifrado $stamp"
git remote add origin "https://github.com/$TARGET.git"
git push -u origin "HEAD:refs/heads/$branch"
[[ "$(git ls-remote origin "refs/heads/$branch" | awk '{print $1}')" == "$(git rev-parse HEAD)" ]] || {
  echo "No se pudo verificar la subida" >&2; exit 1;
}

echo "Respaldo cifrado verificado en https://github.com/$TARGET/tree/$branch"
echo "SHA-256 original: $EXPECTED_SHA"
echo "IMPORTANTE: conserva la clave privada FUERA de Codespaces: $keyfile"
