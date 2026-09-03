#!/usr/bin/env bash
# Launches iloader on Wayland/KDE.
# WEBKIT_DISABLE_DMABUF_RENDERER=1 fixes "EGL_BAD_PARAMETER" abort on WebKitGTK.
# NOTE: do NOT force GDK_BACKEND=x11 — that breaks EGL on this machine.
cd "$(dirname "$0")"
export WEBKIT_DISABLE_DMABUF_RENDERER=1
exec ./iloader.AppImage "$@"
