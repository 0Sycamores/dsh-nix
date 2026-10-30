#!@SHELL@
# DSH 桌面端启动器：固定 GTK/GIO 环境（等价于 wrapGAppsHook3 的包装结果），
# libstdc++ 供 Electron 侧原生模块 dlopen 使用。
export GIO_EXTRA_MODULES="@GIO_EXTRA_MODULES@"
export GDK_PIXBUF_MODULE_FILE="@GDK_PIXBUF_MODULE_FILE@"
export XDG_DATA_DIRS="@XDG_DATA_DIRS@${XDG_DATA_DIRS:+:$XDG_DATA_DIRS}"
export LD_LIBRARY_PATH="@LD_LIBRARY_PATH@${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
export CHROME_DESKTOP="deepseek-harness"
exec "@PKG@/dsh-desktop" "$@"
