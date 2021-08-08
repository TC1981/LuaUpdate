# LuaUpdate for OPNsense

Shell script to check WAN interface IP change and if the IP has been changed then update the DNS A record.

## Installation steps:
1. Add cron job to OPNsense GUI
    ```bash
    $ cp actions_luaupdate.conf /usr/local/opnsense/service/conf/actions.d/
    ```
2. Add script to /usr/home
    ```bash
    $ cp luaupdate.sh /usr/home
    ```
4. Restart configd
    ```bash
    $ service configd restart
    ```
5. Test cron job
    ```bash
    $ configctl luaupdate start
    ```