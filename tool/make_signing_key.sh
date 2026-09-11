#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# 把 keystore 转成 Base64，用来填 GitHub Secret: SIGNING_KEY
#
#   bash tool/make_signing_key.sh android/app/release.jks
#
# 输出会直接打印到终端（并可选写到文件），复制整行内容粘进
# GitHub → Settings → Secrets and variables → Actions → New secret 即可。
# ---------------------------------------------------------------------------
set -euo pipefail

KEYSTORE="${1:-android/app/release.jks}"

if [[ ! -f "$KEYSTORE" ]]; then
  echo "找不到 keystore: $KEYSTORE" >&2
  echo "用法: bash tool/make_signing_key.sh <path-to-keystore>" >&2
  exit 1
fi

# -w 0 表示不换行（GNU）；macOS 的 base64 没有 -w，用 tr 兜底。
if base64 --help 2>&1 | grep -q -- '-w'; then
  BASE64_VALUE="$(base64 -w 0 "$KEYSTORE")"
else
  BASE64_VALUE="$(base64 "$KEYSTORE" | tr -d '\n')"
fi

OUT_FILE="${KEYSTORE}.base64"
printf '%s' "$BASE64_VALUE" > "$OUT_FILE"

echo "已生成: $OUT_FILE"
echo "长度: ${#BASE64_VALUE} 字符"
echo
echo "----------------------------------------------------------------------"
echo "复制下面这一整行，填入 GitHub Secret: SIGNING_KEY"
echo "----------------------------------------------------------------------"
echo "$BASE64_VALUE"
echo "----------------------------------------------------------------------"
echo
echo "还需要配置这几个 Secret："
echo "  KEY_ALIAS        keystore 里的 key 别名（例如 pkwdwpl）"
echo "  KEY_PASSWORD     key 密码"
echo "  STORE_PASSWORD   keystore 密码"
echo
echo "⚠️  别把 keystore / .base64 文件提交到仓库（.gitignore 已忽略 *.jks / *.keystore）"
