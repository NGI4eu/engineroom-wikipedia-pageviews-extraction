#!/usr/bin/env bash
SOURCED=false && [ "$0" = "$BASH_SOURCE" ] || SOURCED=true

# get script path
# See:
# https://stackoverflow.com/questions/630372
# SCRIPT_PATH="$( cd "$(dirname "$0")" && pwd )"

PAGE=()
debug=false
date_start=''
date_end=''
lang=''
gzdir=''
datadir=''
prefix=''
word=false
no_simplify=false
no_build_index=false
read -rd '' docstring <<EOF
Usage:
  extract_all.sh [options] -g GZDIR PAGE ...
  extract_all.sh ( -h | --help )
  extract_all.sh ( --version )

  Options:
    -d, --debug                 Enable debug mode.
    --datadir DATADIR           Temporary data directory [default: ./data]
    --date-start YEAR_START     Starting year [default: 2007-12].
    --date-end YEAR_END         Ending year [default: 2016-07].
    -o, --outputdir OUTPUTDIR   Output directory [default: ./output]
    -p, --prefix PREFIX         Prefix to use for the output file name [default: pageviews]
    -g, --gzdir gzdir           Directory with the .gz files.
    -i, --indexdir INDEXDIR     Index directory [default: ./indexes].
    -f, --file INFILE           File with the list of titles to search.
    -y, --yearmonth YEARMONTH   Year and month to analyze, in the format
                                YYYY-MM
    -l, --lang LANG             Language [default: en]
    -n, --dry-run               Dry run, only show the commands to be executed.
    --no-simplify               Do not use simplified quoted redirects.
    --no-build-index            Do not build indexes.
    -w, --word                  Extract whole words.
    -h, --help                  Show this help message and exits.
    --version                   Print version and copyright information.
----
extract_all.sh 1.0.0
copyright (c) 2018 Cristian Consonni
MIT License
This is free software: you are free to change and redistribute it.
There is NO WARRANTY, to the extent permitted by law.
EOF

eval "$(echo "$docstring" | docopts -V - -h - : "$@" )"

# Bash strict mode
# See:
# https://balist.es/blog/2017/03/21/
#     enhancing-the-unofficial-bash-strict-mode/ 
if ! $SOURCED; then
  set -euo pipefail
  IFS=$'\n\t'
fi

#################### Utils
if $debug; then
  echodebug_skip_header=false
  echodebug() {
    local numargs="$#"

    if ! $echodebug_skip_header; then
      echo -en "[$(date '+%F_%k:%M:%S')][debug]\\t"
    else
      echodebug_skip_header=false
    fi

    if [ "$numargs" -gt 1 ] && [[ "$1" =~ ^'-n'* ]]; then
      echodebug_skip_header=true
    fi
    echo "$@" 1>&2
  }
else
  echodebug() { true; }
fi
####################
year_start="$(echo "$date_start" | cut -c 1-4)"
month_start="$(echo "$date_start" | cut -c 6-8)"
year_end="$(echo "$date_end" | cut -c 1-4)"
month_end="$(echo "$date_end" | cut -c 6-8)"

GZDIR="$gzdir"

if $debug; then
    echodebug "--- ARGUMENTS ---"
    echodebug "PAGES: "
    for page in "${PAGE[@]}"; do
      echodebug "  * $page"
    done
    echodebug "GZDIR: $GZDIR"
    echodebug
    echodebug "year_start:  $year_start"
    echodebug "month_start: $month_start"
    echodebug "year_end:    $year_end"
    echodebug "month_end:   $month_end"
    echodebug
    echodebug "debug (-d): $debug"
    echodebug "datadir (--datadir): $datadir"
    echodebug "lang (-l): $lang"
    echodebug "prefix (-p): $prefix"
    echodebug "---"
fi

set -x
export TMPDIR="$(realpath "$datadir")"
tmpdir=$(mktemp -p "$(realpath "$datadir")" -d -t tmp.extract_all.XXXXXXXXXX)
function finish {
  rm -rf "$tmpdir"
}
trap finish EXIT
set +x

startdate=$(date -d "${year_start}-${month_start}-01" +%s)
enddate=$(date -d "${year_end}-${month_end}-01" +%s)

if [ "$startdate" -ge "$enddate" ]; then
    (>&2 echo "Error: end date must be greater than start date")
fi

function skip_years() {
  if [ "$1" -le "$year_start" ] && [ "$2" -lt "$month_start" ]; then return 0; fi
  if [ "$1" -ge "$year_end" ] && [ "$2" -gt "$month_end" ]; then return 0; fi

  return 1
}

year=''
month=''
for page in "${PAGE[@]}"; do
  echo "> $page"

  clean_pagename=${page//[^a-zA-Z0-9]/}
  page_datadir="${tmpdir}/${clean_pagename}"
  mkdir -p "${page_datadir}"

  for year in $(seq "$year_start" "$year_end"); do
    for month in {01..12}; do
      if skip_years "$year" "$month"; then continue; fi

      echo "  - ${year}-${month}"

      page=$(echo "$page" | tr ' ' '_')
      quoted_redirects_file="./output/${lang}/${page}.quoted-redirects.txt"

      if [ ! -f "$quoted_redirects_file" ]; then
        (>&2 echo "ERROR: redirect file")
        (>&2 echo "  $quoted_redirects_file" )
        (>&2 echo "not found")
        exit 1
      fi

      options=()
      if $word; then
        options+=('--word')
      fi

      if $no_simplify; then
        options+=('--no-simplify')
      fi

      if $no_build_index; then
        options+=('--no-build-index')
      fi

      set +u
      set -x
      ./scripts/extract_data.sh -d \
        "${options[@]}" \
        -l "$lang" \
        --datadir "${page_datadir}" \
        --prefix "$prefix" \
        -f "$quoted_redirects_file" \
        -y "${year}-${month}" \
        -g "${gzdir}"
      set +x
      set -u

    done

    echodebug "Removing data for year $year"
    rm -rf "${page_datadir}/${year}-"*
    echodebug 'done'

  done
done
