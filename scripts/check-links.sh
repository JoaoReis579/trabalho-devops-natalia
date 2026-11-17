#!/usr/bin/env bash
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

errors=0

while IFS= read -r -d '' html_file; do
  while IFS=$'\t' read -r line_number target; do
    [[ -n "$target" ]] || continue
    normalized="${target,,}"

    case "$normalized" in
      \#*|mailto:*|tel:*|javascript:*)
        continue
        ;;
      http://*|https://*)
        status="$(curl -o /dev/null -s -L --max-time 20 -A "Mozilla/5.0" -w "%{http_code}" "$target" || true)"
        if [[ "$status" == "000" || ( "$status" =~ ^[0-9]{3}$ && "$status" -ge 400 && "$status" != "999" ) ]]; then
          printf '::error file=%s,line=%s::Link externo inválido (%s): HTTP %s\n' "${html_file#./}" "$line_number" "$target" "$status"
          errors=$((errors + 1))
        fi
        ;;
      //*)
        status="$(curl -o /dev/null -s -L --max-time 20 -A "Mozilla/5.0" -w "%{http_code}" "https:$target" || true)"
        if [[ "$status" == "000" || ( "$status" =~ ^[0-9]{3}$ && "$status" -ge 400 && "$status" != "999" ) ]]; then
          printf '::error file=%s,line=%s::Link externo inválido (https:%s): HTTP %s\n' "${html_file#./}" "$line_number" "$target" "$status"
          errors=$((errors + 1))
        fi
        ;;
      *)
        local_path="${target%%\?*}"
        local_path="${local_path%%\#*}"
        [[ -n "$local_path" ]] || continue
        if [[ "$local_path" == /* ]]; then
          resolved="$ROOT/${local_path#/}"
        else
          resolved="$(dirname "$ROOT/${html_file#./}")/$local_path"
        fi
        if [[ ! -e "$resolved" ]]; then
          printf '::error file=%s,line=%s::Caminho local não encontrado: %s\n' "${html_file#./}" "$line_number" "$target"
          errors=$((errors + 1))
        fi
        ;;
    esac
  done < <(python3 - "$html_file" <<'PY'
from html.parser import HTMLParser
import sys

class LinkParser(HTMLParser):
    def handle_starttag(self, tag, attrs):
        if tag in {"a", "link", "img"}:
            for name, value in attrs:
                if name in {"href", "src"} and value is not None:
                    print(f"{self.getpos()[0]}\t{value}")

with open(sys.argv[1], encoding="utf-8") as source:
    parser = LinkParser()
    parser.feed(source.read())
PY
  )
done < <(find . -type d -name node_modules -prune -o -type f -name '*.html' -print0)

if (( errors > 0 )); then
  printf 'Verificação de links concluída com %s erro(s).\n' "$errors"
  exit 1
fi

printf 'Verificação de links concluída sem erros.\n'
