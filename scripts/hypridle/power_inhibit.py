#!/usr/bin/python3
import os
import signal
import sys

import dbus
import dbus.service
from dbus.mainloop.glib import DBusGMainLoop
from gi.repository import GLib


INTERFACE = "org.freedesktop.PowerManagement.Inhibit"


class PowerInhibit(dbus.service.Object):
    def __init__(self, bus, name):
        super().__init__(name, "/org/freedesktop/PowerManagement/Inhibit")
        self.requests = {}
        self.next_cookie = 1
        self.login = dbus.Interface(dbus.SystemBus().get_object(
            "org.freedesktop.login1", "/org/freedesktop/login1"),
            "org.freedesktop.login1.Manager")
        bus.add_signal_receiver(self.owner_changed, signal_name="NameOwnerChanged",
                                dbus_interface="org.freedesktop.DBus")

    @dbus.service.method(INTERFACE, in_signature="ss", out_signature="u", sender_keyword="sender")
    def Inhibit(self, application, reason, sender=None):
        fd = self.login.Inhibit("idle", application, reason, "block").take()
        cookie = self.next_cookie
        self.next_cookie += 1
        self.requests[cookie] = (sender, fd)
        return dbus.UInt32(cookie)

    @dbus.service.method(INTERFACE, in_signature="u", out_signature="", sender_keyword="sender")
    def UnInhibit(self, cookie, sender=None):
        request = self.requests.get(cookie)
        if request and request[0] == sender:
            os.close(self.requests.pop(cookie)[1])

    @dbus.service.method(INTERFACE, in_signature="", out_signature="b")
    def HasInhibit(self):
        return bool(self.requests)

    def owner_changed(self, name, old_owner, new_owner):
        if new_owner:
            return
        for cookie, (owner, fd) in list(self.requests.items()):
            if owner == name:
                os.close(fd)
                del self.requests[cookie]

    def close(self):
        for owner, fd in self.requests.values():
            os.close(fd)
        self.requests.clear()


def main():
    DBusGMainLoop(set_as_default=True)
    bus = dbus.SessionBus()
    try:
        name = dbus.service.BusName("org.freedesktop.PowerManagement", bus, do_not_queue=True)
    except dbus.exceptions.NameExistsException:
        return
    service = PowerInhibit(bus, name)
    loop = GLib.MainLoop()
    GLib.unix_signal_add(GLib.PRIORITY_DEFAULT, signal.SIGTERM, lambda: loop.quit())
    GLib.unix_signal_add(GLib.PRIORITY_DEFAULT, signal.SIGINT, lambda: loop.quit())
    GLib.io_add_watch(sys.stdin, GLib.IO_HUP, lambda *_: loop.quit())
    try:
        loop.run()
    finally:
        service.close()


if __name__ == "__main__":
    main()
