#!/usr/bin/env bash

# cd to silisili/resources/i18n
cd "$(dirname "$0")/../resources/i18n" || exit

LANG_PATH="$HOME/Downloads/silisili (translations)"

if [ -n "$1" ] ;then
  LANG_PATH=$1
fi

echo "Load language files from: $LANG_PATH"

cp "$LANG_PATH/ja/hints.json" ./ja
cp "$LANG_PATH/ja/silisili.json" ./ja
cp "$LANG_PATH/ry/hints.json" ./ja-RYU
cp "$LANG_PATH/ry/silisili.json" ./ja-RYU
cp "$LANG_PATH/ko/hints.json" ./ko
cp "$LANG_PATH/ko/silisili.json" ./ko
cp "$LANG_PATH/zh-CN/hints.json" ./zh-Hans
cp "$LANG_PATH/zh-CN/silisili.json" ./zh-Hans
cp "$LANG_PATH/zh-TW/hints.json" ./zh-Hant
cp "$LANG_PATH/zh-TW/silisili.json" ./zh-Hant
cp "$LANG_PATH/it/hints.json" ./it
cp "$LANG_PATH/it/silisili.json" ./it

echo "Load language files done"

rm -r "$LANG_PATH"