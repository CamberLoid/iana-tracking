#!/usr/bin/env bash
# 从 ./.targets 读取：
#   "# url [file-name]"
#   第一列为 URL，第二列可选指定保存文件名；若未给则用 URL 路径的 basename。
# 仅在内容变化时覆盖，最终将 UPDATED_COUNT 写入 $GITHUB_ENV 供后续步骤使用。

set -euo pipefail

TARGETS_FILE="${TARGETS_FILE:-./.targets}"
#CURL_UA="${CURL_UA:-iana-tracker/1.0 (+github-actions)}"

if [[ ! -f "${TARGETS_FILE}" ]]; then
  echo "::error::Targets file not found: ${TARGETS_FILE}"
  exit 1
fi

updated=0
touched=0
export UPDATED_COUNT

while IFS= read -r line; do
  # trim
  line="$(echo "$line" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
  # skip comments/blank
  [[ -z "$line" || "${line:0:1}" == "#" ]] && continue

  # 解析两列：url [fname]
  # URL 不含空格，直接用 read 拆分
  url=""
  fname=""
  # shellcheck disable=SC2086
  read -r url fname <<<"$line"

  if [[ -z "${url}" ]]; then
    echo "Skip invalid line (no url): $line"
    continue
  fi

  # 去掉 URL 的 query/fragment
  clean_url="${url%%\#*}"
  clean_url="${clean_url%%\?*}"

  # 未给文件名则取 basename
  if [[ -z "${fname}" ]]; then
    # basename 的目标至少要有路径
    path_part="${clean_url}"
    # 删除协议部分
    path_part="${path_part#*://}"
    # 去掉主机名，保留路径
    path_part="${path_part#*/}"
    # 如果仍为空，给个兜底文件名
    if [[ -z "${path_part}" ]]; then
      fname="downloaded"
    else
      fname="$(basename -- "${path_part}")"
      # 如果 URL 以斜杠结尾导致 basename 为空，兜底
      [[ -z "${fname}" || "${fname}" == "/" ]] && fname="downloaded"
    fi
  fi

  mkdir -p "$(dirname "$fname")"
  tmp="${fname}.tmp"

  if ! curl -fSLS --retry 3 "${clean_url}" -o "${tmp}"; then
    echo "::warning::failed to fetch ${url}"
    rm -f "${tmp}"
    continue
  fi

  touched=$((touched + 1))

  if [[ -f "${fname}" ]] && cmp -s "${tmp}" "${fname}"; then
    rm -f "${tmp}"
  else
    mv "${tmp}" "${fname}"
    updated=$((updated + 1))
    echo "Updated: ${fname}"
  fi
done < "${TARGETS_FILE}"

echo "Touched: ${touched}, Updated: ${updated}"

# 输出 UPDATED_COUNT
if [[ -n "${GITHUB_ENV:-}" ]]; then
  echo "UPDATED_COUNT=${updated}" >> "$GITHUB_ENV"
else
  export UPDATED_COUNT="${updated}"
fi
