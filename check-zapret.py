#!/usr/bin/env python3
import os
import sys

def is_zapret_active():
    """Detect if any Zapret component (nfqws, tpws, zapret service) is active."""
    target_names = {"nfqws", "tpws"}
    try:
        for pid in os.listdir("/proc"):
            if not pid.isdigit():
                continue
            try:
                with open(f"/proc/{pid}/comm", "r") as f:
                    comm = f.read().strip()
                if comm in target_names or "zapret" in comm.lower():
                    return True
                with open(f"/proc/{pid}/cmdline", "rb") as f:
                    cmdline = f.read().replace(b"\x00", b" ").decode(errors="ignore").lower()
                if ("nfqws" in cmdline or "tpws" in cmdline or "zapret" in cmdline) and "check-zapret" not in cmdline and "python" not in cmdline:
                    return True
            except (FileNotFoundError, PermissionError, ProcessLookupError):
                continue
    except Exception:
        pass

    # Fallback: check systemd services if systemctl is available
    for svc in ("zapret-discord-youtube", "zapret", "zapret-service"):
        try:
            res = os.system(f"systemctl is-active --quiet {svc} 2>/dev/null")
            if res == 0:
                return True
        except Exception:
            pass

    return False

def main():
    # Ignore version/help requests
    for arg in sys.argv[1:]:
        if arg in ("--version", "-v", "--help", "-h"):
            sys.exit(0)

    # Ignore headless environments
    if not os.environ.get("DISPLAY") and not os.environ.get("WAYLAND_DISPLAY"):
        sys.exit(0)

    if not is_zapret_active():
        sys.exit(0)

    # Prevent duplicate warning windows if one is already open
    my_pid = os.getpid()
    for pid in os.listdir("/proc"):
        if not pid.isdigit() or int(pid) == my_pid:
            continue
        try:
            with open(f"/proc/{pid}/cmdline", "rb") as f:
                cmd = f.read().decode(errors="ignore")
                if "check-zapret.py" in cmd:
                    sys.exit(0)
        except (FileNotFoundError, PermissionError, ProcessLookupError):
            continue

    try:
        import gi
        gi.require_version("Gtk", "3.0")
        from gi.repository import Gtk

        is_ru = any("ru" in os.environ.get(k, "").lower() for k in ["LANG", "LC_ALL", "LC_MESSAGES"])
        if is_ru:
            title = "INCY — Предупреждение о конфликте"
            primary = "Обнаружен активный сервис Zapret (DPI Bypass)"
            secondary = (
                "В системе запущен Zapret (процессы nfqws / tpws).\n\n"
                "Zapret перехватывает и модифицирует сетевые пакеты через NFQUEUE (iptables).\n"
                "При одновременной работе с INCY (Xray / TUN) это часто приводит к "
                "ошибкам TLS-сертификатов (Certificate verification failed) "
                "или полной блокировке соединения.\n\n"
                "Если у вас не работает подключение или возникают ошибки, временно остановите "
                "сервис вашего обхода (обратитесь к инструкции используемой сборки Zapret)."
            )
        else:
            title = "INCY — Conflict Warning"
            primary = "Active Zapret Service Detected (DPI Bypass)"
            secondary = (
                "Zapret (nfqws / tpws processes) is running on your system.\n\n"
                "Zapret intercepts and modifies packets via NFQUEUE / iptables.\n"
                "Running it simultaneously with INCY (Xray / TUN) often leads to "
                "TLS handshake errors (certificate validation failures) or dropped connections.\n\n"
                "If INCY fails to connect or throws certificate errors, temporarily stop your "
                "DPI bypass service (refer to the documentation of your specific Zapret setup)."
            )

        dialog = Gtk.MessageDialog(
            transient_for=None,
            flags=0,
            message_type=Gtk.MessageType.WARNING,
            buttons=Gtk.ButtonsType.OK,
            text=primary
        )
        dialog.format_secondary_text(secondary)
        dialog.set_title(title)
        dialog.set_position(Gtk.WindowPosition.CENTER)
        dialog.set_keep_above(True)
        dialog.show_all()
        dialog.run()
        dialog.destroy()
        while Gtk.events_pending():
            Gtk.main_iteration()

    except Exception as e:
        print(f"[INCY Warning] Zapret is active: {e}", file=sys.stderr)

if __name__ == "__main__":
    main()
