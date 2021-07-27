# LuaUpdate for OPNsense

Shell cript to check WAN interface IP change and if the IP has been changed then update the DNS A record.

## Installation steps:
 1. Add cron job to OPNsense GUI
    ```bash
    cp actions_luaupdate.conf /usr/local/opnsense/service/conf/actions.d/
    ```
 2. Test cron job
    ```bash
    configctl luaupdate start
    ```
 3. Add script to /usr/home
    ```bash
    cp luaupdate.sh /usr/home
    ```
    or if copy not permitted due to some misterious write protection reason then
    ```bash
    nano /usr/home/luaupdate.sh
    ```

