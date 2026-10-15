#!/usr/bin/env bash
# Download the free datasets used for training. Run from the ml/ folder.
#   bash download_datasets.sh            # ESC-50 + FSDD (required, ~1.5 GB)
#   bash download_datasets.sh --all      # also DEMAND + MUSAN (background/noise, ~13 GB)
set -e
cd "$(dirname "$0")/data"

if [ ! -d ESC-50 ]; then
  echo "== ESC-50 (home/safety sounds, CC BY-NC)"
  git clone --depth 1 https://github.com/karolpiczak/ESC-50 && rm -rf ESC-50/.git
fi
if [ ! -d FSDD ]; then
  echo "== Free Spoken Digit Dataset (speech, CC BY-SA)"
  git clone --depth 1 https://github.com/Jakobovski/free-spoken-digit-dataset FSDD && rm -rf FSDD/.git
fi

if [ "$1" == "--all" ]; then
  if [ ! -d DEMAND ]; then
    echo "== DEMAND (real environment recordings, CC BY-SA) — 16 kHz versions, ~1.5 GB"
    mkdir -p DEMAND && cd DEMAND
    for env in DKITCHEN DLIVING DWASHING NFIELD NPARK NRIVER OHALLWAY OMEETING OOFFICE \
               PCAFETER PRESTO PSTATION SPSQUARE STRAFFIC TBUS TCAR TMETRO; do
      [ -d "$env" ] && continue
      curl -L -o "${env}_16k.zip" "https://zenodo.org/records/1227121/files/${env}_16k.zip?download=1"
      unzip -q "${env}_16k.zip" && rm "${env}_16k.zip"
    done
    cd ..
  fi
  if [ ! -d musan ]; then
    echo "== MUSAN (noise + music + speech, CC BY) — ~11 GB"
    curl -L -o musan.tar.gz https://www.openslr.org/resources/17/musan.tar.gz
    tar xzf musan.tar.gz && rm musan.tar.gz
  fi
fi
echo "done. now: python3 prepare_data.py && python3 extract_embeddings.py && python3 train_head.py"
