#!/bin/zsh
set -e
cd "${0:A:h}"
/usr/bin/python3 scripts/install.py
printf '\n按回车关闭窗口。'
read
